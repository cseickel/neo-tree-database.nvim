--[[
The two queries postgres is asked: one per connection for its databases and
roles, and one per database for everything that database holds.
]]

local M = {}

--- The grants an acl holds, one entry per grantee, as sql to place where a
--- json value is expected. `acl` is the expression that reads the acl.
---
--- A grantee of 0 is PUBLIC, which has no role name, so its `grantee` is null
--- and the decoded entry has no `grantee` key at all.
---
--- aclexplode returns a row per grantor, and the same privilege granted by two
--- roles is one privilege here, held with grant option if either grant has it.
---@param acl string
---@return string
local function grants(acl)
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

--- A null acl means the object still has the privileges postgres gives every
--- object of its kind, which `acldefault` spells out, so the owner shows as
--- holding them instead of the object showing no grants at all.
---@param acl string
---@param kind string The `acldefault` object type, such as `r` for a relation.
---@param owner string
---@return string
local function grants_or_default(acl, kind, owner)
  return grants(("coalesce(%s, acldefault('%s', %s))"):format(acl, kind, owner))
end

--- An object an extension created, or a sequence behind an identity column.
--- Neither was written by the user, so neither is listed.
---@param class string
---@param oid string
---@param deptypes string
---@return string
local function dependent(class, oid, deptypes)
  return ([[exists (
    select 1 from pg_depend dep
    where dep.classid = '%s'::regclass and dep.objid = %s and dep.deptype in (%s)
  )]]):format(class, oid, deptypes)
end

-- A role belongs to the whole server, so the roles come with the database list
-- rather than with each database. A role can be granted the same membership by
-- several grantors since postgres 16, which `distinct` folds back into one.
M.CATALOGS = [[
select json_build_object(
  'catalogs', coalesce((
    select json_agg(datname order by datname)
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

-- Several things here are not the obvious spelling, and each is deliberate.
-- reltuples is -1 until the table has been analyzed, which is not an estimate
-- of zero. An index column is read back through pg_get_indexdef rather than
-- joined to pg_attribute, because indkey holds 0 for an expression and the
-- join would silently drop it. contype 'n' is the not-null constraint row that
-- postgres 17 began storing, which the column list already reports. A column's
-- acl is read without a default, because a column has no privileges of its own
-- until one is granted on it. pg_get_functiondef raises on an aggregate, and
-- one aggregate would fail the whole query.
M.INTROSPECT = [[
select json_build_object(
  'grants', (
    select ]] .. grants_or_default("d.datacl", "d", "d.datdba") .. [[
    from pg_database d
    where d.datname = current_database()
  ),
  'schemas', coalesce((
  select json_agg(json_build_object(
    'name', n.nspname,
    'grants', ]] .. grants_or_default("n.nspacl", "n", "n.nspowner") .. [[,
    'relations', coalesce((
      select json_agg(json_build_object(
        'name', c.relname,
        'kind', case c.relkind
                  when 'v' then 'view'
                  when 'm' then 'materialized_view'
                  else 'table'
                end,
        'rows', case when c.reltuples < 0 then null else c.reltuples::bigint end,
        'definition', case when c.relkind in ('v', 'm')
                        then 'CREATE '
                             || case c.relkind when 'm' then 'MATERIALIZED ' else '' end
                             || 'VIEW ' || quote_ident(n.nspname) || '.' || quote_ident(c.relname)
                             || ' AS ' || pg_get_viewdef(c.oid, true)
                        else null
                      end,
        'grants', ]] .. grants_or_default("c.relacl", "r", "c.relowner") .. [[,
        'columns', coalesce((
          select json_agg(json_build_object(
            'name', a.attname,
            'type', format_type(a.atttypid, a.atttypmod),
            'nullable', not a.attnotnull,
            'default', pg_get_expr(d.adbin, d.adrelid),
            'identity', nullif(a.attidentity, ''),
            'generated', nullif(a.attgenerated, ''),
            'position', a.attnum,
            'grants', ]] .. grants("a.attacl") .. [[
          ) order by a.attnum)
          from pg_attribute a
          left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
          where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
        ), '[]'::json),
        'indexes', coalesce((
          select json_agg(json_build_object(
            'name', ic.relname,
            'unique', i.indisunique,
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
        'grants', ]] .. grants_or_default("c.relacl", "s", "c.relowner") .. [[
      ) order by c.relname)
      from pg_class c
      join pg_sequence s on s.seqrelid = c.oid
      where c.relnamespace = n.oid
        and not ]] .. dependent("pg_class", "c.oid", "'e', 'i'") .. [[
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
        'definition', case when p.prokind <> 'a' then rtrim(pg_get_functiondef(p.oid), E'\n') || ';' end,
        'grants', ]] .. grants_or_default("p.proacl", "f", "p.proowner") .. [[
      ) order by p.proname, pg_get_function_identity_arguments(p.oid))
      from pg_proc p
      where p.pronamespace = n.oid
        and not ]] .. dependent("pg_proc", "p.oid", "'e'") .. [[
    ), '[]'::json)
  ) order by n.nspname)
  from pg_namespace n
  where n.nspname not in ('pg_catalog', 'information_schema')
    and n.nspname not like 'pg_toast%'
    and n.nspname not like 'pg_temp%'
), '[]'::json))
]]

return M
