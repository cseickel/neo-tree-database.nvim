--- Builds the sql that lists a postgres server's databases and roles, and the sql
--- that reads everything one database holds.

local M = {}

--- Returns sql for a json list of the grants in the acl that the expression `acl`
--- reads, one entry per grantee. PUBLIC is grantee 0 and gets a null `grantee`.
--- aclexplode returns a row per grantor, so a privilege that two roles granted
--- becomes one privilege, grantable when either grant is.
---@param acl string
---@return string
local function grants_json(acl)
  return [[coalesce((
    select json_agg(json_build_object(
      'grantee', g.grantee,
      'privileges', g.privileges
    ) order by g.grantee nulls first)
    from (
      select case when e.grantee = 0 then null else pg_get_userbyid(e.grantee) end as grantee,
             json_agg(json_build_object(
               'name', e.privilege_type,
               'grantable', e.is_grantable
             ) order by e.privilege_type) as privileges
      from (
        select x.grantee, x.privilege_type, bool_or(x.is_grantable) as is_grantable
        from aclexplode(]] .. acl .. [[) as x
        group by x.grantee, x.privilege_type
      ) as e
      group by e.grantee
    ) as g
  ), '[]'::json)]]
end

--- Returns `grants_json` for `acl`, using the privileges that `acldefault` gives
--- an object of `kind` owned by `owner` when `acl` is null. postgres keeps a
--- null acl until a privilege on the object is first granted or revoked.
---@param acl string
---@param kind string The `acldefault` object type, such as `r` for a relation.
---@param owner string
---@return string
local function grants_or_default_json(acl, kind, owner)
  return grants_json(("coalesce(%s, acldefault('%s', %s))"):format(acl, kind, owner))
end

--- Returns sql that is true when the object `oid` in the catalog `class` has a
--- pg_depend row with one of `deptypes`. `e` marks an object an extension
--- created, and `i` marks a sequence behind an identity column.
---@param class string
---@param oid string
---@param deptypes string
---@return string
local function has_dependency(class, oid, deptypes)
  return ([[exists (
    select 1 from pg_depend dep
    where dep.classid = '%s'::regclass and dep.objid = %s and dep.deptype in (%s)
  )]]):format(class, oid, deptypes)
end

---@class dbtree.SizeSql How a catalog query measures a relation.
---@field total fun(oid: string): string Sql for the bytes of the relation, its toast and its indexes.
---@field estimated boolean

-- pg_total_relation_size takes a lock on each relation it measures.
---@type dbtree.SizeSql
M.EXACT_SIZES = {
  total = function(oid)
    return ("pg_total_relation_size(%s)"):format(oid)
  end,
  estimated = false,
}

-- Reads the page counts that vacuum and analyze last recorded in pg_class, which
-- takes no lock. A sequence's relpages stays 0, so it counts as its one page.
---@type dbtree.SizeSql
M.ESTIMATED_SIZES = {
  total = function(oid)
    return ([[(
      select sum(case when part.relkind = 'S' then 1 else part.relpages end)::bigint
             * current_setting('block_size')::bigint
      from pg_class whole
      cross join lateral (
        select whole.oid
        union all select whole.reltoastrelid
        union all select part_index.indexrelid from pg_index part_index
                  where part_index.indrelid in (whole.oid, whole.reltoastrelid)
      ) as member(oid)
      join pg_class part on part.oid = member.oid
      where whole.oid = %s
    )]]):format(oid)
  end,
  estimated = true,
}

local NO_SIZE = "'size', null"

--- Returns the `size` key and value of a json object, followed by
--- `size_estimated` when the size is an estimate.
---@param sizes dbtree.SizeSql
---@param expression string
---@return string
local function size_json_pairs(sizes, expression)
  if sizes.estimated then
    return "'size', " .. expression .. ", 'size_estimated', true"
  end
  return "'size', " .. expression
end

--- Returns the size json pairs for the schema `n`, which is what its tables,
--- materialized views and sequences take, or a null size when `sizes` is nil.
---@param sizes dbtree.SizeSql|nil
---@return string
local function schema_size_json(sizes)
  if not sizes then
    return NO_SIZE
  end
  return size_json_pairs(sizes, [[(
      select coalesce(sum(]] .. sizes.total("c.oid") .. [[), 0)::bigint
      from pg_class c
      where c.relnamespace = n.oid and c.relkind in ('r', 'm', 'S')
    )]])
end

--- Returns the size json pairs for a relation, or a null size when `sizes` is
--- nil. A partitioned table or index has no storage of its own, so its size is
--- the sum of its partitions, and a view or a foreign table has no size. The
--- partitions are found through pg_inherits, because pg_partition_tree locks
--- each one.
---@param sizes dbtree.SizeSql|nil
---@param oid string
---@param relkind string
---@return string
local function relation_size_json(sizes, oid, relkind)
  if not sizes then
    return NO_SIZE
  end
  return size_json_pairs(sizes, ([[case
    when %s in ('v', 'f') then null
    when %s in ('p', 'I') then (
      with recursive tree(relid) as (
        select %s
        union all
        select inh.inhrelid from pg_inherits inh join tree on inh.inhparent = tree.relid
      )
      select sum(%s)::bigint from tree
    )
    else %s
  end]]):format(relkind, relkind, oid, sizes.total("tree.relid"), sizes.total(oid)))
end

--- Returns the sql that lists the server's databases, each with its size when
--- `read_sizes` is set, and its roles. pg_database_size raises an error for a
--- database the role cannot connect to. Since postgres 16 a role can hold the
--- same membership from several grantors, so the membership lists use
--- `distinct`.
---@param read_sizes boolean
---@return string
function M.catalogs(read_sizes)
  local size = read_sizes and "case when has_database_privilege(oid, 'CONNECT') then pg_database_size(oid) end"
    or "null"
  return [[
select json_build_object(
  'catalogs', coalesce((
    select json_agg(json_build_object(
      'name', datname,
      'size', ]] .. size .. "\n" .. [[    ) order by datname)
    from pg_database where datallowconn and not datistemplate
  ), '[]'::json),
  'roles', coalesce((
    select json_agg(json_build_object(
      'name', r.rolname,
      'attributes', (
        select coalesce(json_agg(a.keyword order by a.n), '[]'::json)
        from (values
          (1, 'SUPERUSER', r.rolsuper),
          (2, 'LOGIN', r.rolcanlogin),
          (3, 'CREATEDB', r.rolcreatedb),
          (4, 'CREATEROLE', r.rolcreaterole),
          (5, 'REPLICATION', r.rolreplication),
          (6, 'BYPASSRLS', r.rolbypassrls),
          (7, 'NOINHERIT', not r.rolinherit)
        ) as a(n, keyword, held)
        where a.held
      ),
      'member_of', coalesce((
        select json_agg(distinct g.rolname order by g.rolname)
        from pg_auth_members m
        join pg_roles g on g.oid = m.roleid
        where m.member = r.oid
      ), '[]'::json),
      'members', coalesce((
        select json_agg(distinct u.rolname order by u.rolname)
        from pg_auth_members m
        join pg_roles u on u.oid = m.member
        where m.roleid = r.oid
      ), '[]'::json)
    ) order by r.rolname)
    from pg_roles r
  ), '[]'::json)
)
]]
end

---@class dbtree.PostgresIntrospect
---@field sizes dbtree.SizeSql|nil How to measure each relation, or nil to read no sizes or row counts.
---@field grants boolean

--- Returns the sql that reads everything the connected database holds. It
--- relies on these postgres behaviors:
--- - reltuples is -1 until the table is analyzed.
--- - indkey holds 0 for an expression column, so index columns come from
---   pg_get_indexdef.
--- - Since postgres 17, each NOT NULL is also a constraint with contype `n`.
--- - A column has no privileges of its own until one is granted on it, so its
---   acl has no default.
--- - pg_get_functiondef raises an error for an aggregate.
--- - proallargtypes is null when every argument is an input, and proargtypes
---   holds the same types then.
--- - A procedure's prorettype is void.
---@param spec dbtree.PostgresIntrospect
---@return string
function M.introspect(spec)
  local sizes = spec.sizes
  local rows = sizes and "case when c.reltuples < 0 then null else c.reltuples::bigint end" or "null"

  ---@param acl string
  ---@param kind string
  ---@param owner string
  ---@return string
  local function acl_grants(acl, kind, owner)
    return spec.grants and grants_or_default_json(acl, kind, owner) or "null"
  end

  local database_grants = spec.grants
      and ("(\n    select " .. grants_or_default_json("d.datacl", "d", "d.datdba") .. [[
    from pg_database d
    where d.datname = current_database()
  )]])
    or "null"

  return [[
select json_build_object(
  'grants', ]] .. database_grants .. [[,
  'schemas', coalesce((
  select json_agg(json_build_object(
    'name', n.nspname,
    'grants', ]] .. acl_grants("n.nspacl", "n", "n.nspowner") .. [[,
    ]] .. schema_size_json(sizes) .. [[,
    'relations', coalesce((
      select json_agg(json_build_object(
        'name', c.relname,
        'kind', case c.relkind
                  when 'v' then 'view'
                  when 'm' then 'materialized_view'
                  else 'table'
                end,
        'rows', ]] .. rows .. [[,
        ]] .. relation_size_json(sizes, "c.oid", "c.relkind") .. [[,
        'definition', case when c.relkind in ('v', 'm')
                        then 'CREATE '
                             || case c.relkind when 'm' then 'MATERIALIZED ' else '' end
                             || 'VIEW ' || quote_ident(n.nspname) || '.' || quote_ident(c.relname)
                             || ' AS ' || pg_get_viewdef(c.oid, true)
                        else null
                      end,
        'grants', ]] .. acl_grants("c.relacl", "r", "c.relowner") .. [[,
        'columns', coalesce((
          select json_agg(json_build_object(
            'name', a.attname,
            'type', format_type(a.atttypid, a.atttypmod),
            'nullable', not a.attnotnull,
            'default', pg_get_expr(d.adbin, d.adrelid),
            'identity', nullif(a.attidentity, ''),
            'generated', nullif(a.attgenerated, ''),
            'position', a.attnum,
            'grants', ]] .. (spec.grants and grants_json("a.attacl") or "null") .. [[
          ) order by a.attnum)
          from pg_attribute a
          left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
          where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
        ), '[]'::json),
        'indexes', coalesce((
          select json_agg(json_build_object(
            'name', ic.relname,
            'unique', i.indisunique,
            ]] .. relation_size_json(sizes, "i.indexrelid", "ic.relkind") .. [[,
            'definition', pg_get_indexdef(i.indexrelid),
            'owned_by_constraint', exists (
              select 1 from pg_constraint pc where pc.conindid = i.indexrelid
            ),
            'columns', coalesce((
              select json_agg(pg_get_indexdef(i.indexrelid, key.n::integer, true) order by key.n)
              from generate_series(1, i.indnkeyatts) as key(n)
            ), '[]'::json)
          ) order by ic.relname)
          from pg_index i
          join pg_class ic on ic.oid = i.indexrelid
          where i.indrelid = c.oid
        ), '[]'::json),
        'constraints', coalesce((
          select json_agg(json_build_object(
            'name', k.conname,
            'type', case k.contype
                      when 'p' then 'PRIMARY KEY'
                      when 'f' then 'FOREIGN KEY'
                      when 'u' then 'UNIQUE'
                      when 'c' then 'CHECK'
                      when 'x' then 'EXCLUDE'
                      when 't' then 'TRIGGER'
                      else k.contype::text
                    end,
            'definition', pg_get_constraintdef(k.oid)
          ) order by k.conname)
          from pg_constraint k
          where k.conrelid = c.oid and k.contype <> 'n'
        ), '[]'::json)
      ) order by c.relname)
      from pg_class c
      where c.relnamespace = n.oid
        and c.relkind in ('r', 'p', 'v', 'm', 'f')
        and not c.relispartition
    ), '[]'::json),
    'sequences', coalesce((
      select json_agg(json_build_object(
        'name', c.relname,
        'definition', 'CREATE SEQUENCE ' || quote_ident(n.nspname) || '.' || quote_ident(c.relname)
                      || ' AS ' || format_type(s.seqtypid, null)
                      || ' INCREMENT BY ' || s.seqincrement
                      || ' MINVALUE ' || s.seqmin
                      || ' MAXVALUE ' || s.seqmax
                      || ' START WITH ' || s.seqstart
                      || ' CACHE ' || s.seqcache
                      || case when s.seqcycle then ' CYCLE' else ' NO CYCLE' end
                      || ';',
        ]] .. relation_size_json(sizes, "c.oid", "c.relkind") .. [[,
        'grants', ]] .. acl_grants("c.relacl", "s", "c.relowner") .. [[
      ) order by c.relname)
      from pg_class c
      join pg_sequence s on s.seqrelid = c.oid
      where c.relnamespace = n.oid
        and not ]] .. has_dependency("pg_class", "c.oid", "'e', 'i'") .. [[
    ), '[]'::json),
    'functions', coalesce((
      select json_agg(json_build_object(
        'name', p.proname,
        'arguments', pg_get_function_identity_arguments(p.oid),
        'kind', case p.prokind
                  when 'p' then 'procedure'
                  when 'a' then 'aggregate'
                  else 'function'
                end,
        'args', coalesce((
          select json_agg(json_build_object(
            'name', nullif(a.name, ''),
            'type', format_type(a.type, null),
            'mode', case a.mode
                      when 'o' then 'out'
                      when 'b' then 'inout'
                      when 'v' then 'variadic'
                      when 't' then 'table'
                      else 'in'
                    end,
            'default', pg_get_function_arg_default(p.oid, a.n::integer)
          ) order by a.n)
          from unnest(
            coalesce(p.proallargtypes, p.proargtypes::oid[]),
            p.proargmodes,
            p.proargnames
          ) with ordinality as a(type, mode, name, n)
        ), '[]'::json),
        'returns', case when p.prokind <> 'p' then json_build_object(
          'type', format_type(p.prorettype, null),
          'set', p.proretset,
          'columns', (
            select json_agg(json_build_object(
              'name', ra.attname,
              'type', format_type(ra.atttypid, ra.atttypmod)
            ) order by ra.attnum)
            from pg_type rt
            join pg_attribute ra on ra.attrelid = rt.typrelid
            where rt.oid = p.prorettype and ra.attnum > 0 and not ra.attisdropped
          )
        ) end,
        'definition', case when p.prokind <> 'a' then rtrim(pg_get_functiondef(p.oid), E'\n') || ';' end,
        'grants', ]] .. acl_grants("p.proacl", "f", "p.proowner") .. [[
      ) order by p.proname, pg_get_function_identity_arguments(p.oid))
      from pg_proc p
      where p.pronamespace = n.oid
        and not ]] .. has_dependency("pg_proc", "p.oid", "'e'") .. [[
    ), '[]'::json)
  ) order by n.nspname)
  from pg_namespace n
  where n.nspname not in ('pg_catalog', 'information_schema')
    and n.nspname not like 'pg_toast%'
    and n.nspname not like 'pg_temp%'
), '[]'::json))
]]
end

return M
