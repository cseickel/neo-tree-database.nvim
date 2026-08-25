--[[
postgres.

`pg_catalog` answers rather than `information_schema`, because `relkind` sorts
tables, views, materialized views and partitioned tables in one pass, and
because the `pg_get_*def` functions hand back the definition text the standard
views do not carry.

A connection reaches one database, so the catalog level lists the others on the
same server and each one carries its own url. Nothing below a catalog crosses
into another, which is what postgres allows rather than a choice made here.

One catalog is one query, so an object the connected role cannot read fails the
whole catalog rather than going missing from it. A permission error naming the
object is the better of the two, because a tree quietly missing a table is a
tree that cannot be trusted.
]]

local quote = require("neo-tree-database.quote")
local url = require("neo-tree-database.url")

local M = {}

M.quoting = quote.ANSI

--- psql prints the one value and nothing else: no alignment, no header, no
--- pager, and no psqlrc that could turn any of those back on.
---@param connection string
---@param sql string
---@return dbtree.Request
local function invoke(connection, sql)
  return {
    argv = { "psql", connection, "-X", "-q", "-A", "-t", "-v", "ON_ERROR_STOP=1", "-c", sql },
  }
end

--- Each database on the server is its own connection, because postgres cannot
--- query across one.
---@param connection string
---@param catalog string
---@return string
function M.catalog_url(connection, catalog)
  return url.with_database(connection, catalog)
end

---@param connection string
---@return dbtree.Request
function M.catalogs(connection)
  return invoke(
    connection,
    [[select json_build_object('catalogs', coalesce(
      (select json_agg(datname order by datname)
       from pg_database where datallowconn and not datistemplate),
      '[]'::json))]]
  )
end

-- Three things here are not the obvious spelling, and each is deliberate.
-- reltuples is -1 until the table has been analyzed, which is not an estimate
-- of zero. An index column is read back through pg_get_indexdef rather than
-- joined to pg_attribute, because indkey holds 0 for an expression and the
-- join would silently drop it. contype 'n' is the not-null constraint row that
-- postgres 17 began storing, which the column list already reports.
local INTROSPECT = [[
select json_build_object('schemas', coalesce((
  select json_agg(json_build_object(
    'name', n.nspname,
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
        'columns', coalesce((
          select json_agg(json_build_object(
            'name', a.attname,
            'type', format_type(a.atttypid, a.atttypmod),
            'nullable', not a.attnotnull,
            'default', pg_get_expr(d.adbin, d.adrelid),
            'identity', nullif(a.attidentity, ''),
            'generated', nullif(a.attgenerated, ''),
            'position', a.attnum
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
    ), '[]'::json)
  ) order by n.nspname)
  from pg_namespace n
  where n.nspname not in ('pg_catalog', 'information_schema')
    and n.nspname not like 'pg_toast%'
    and n.nspname not like 'pg_temp%'
), '[]'::json))
]]

--- The catalog is reached by connecting to it, so the query names no database
--- and carries nothing from the tree into sql.
---@param catalog_url string
---@param catalog string
---@return dbtree.Request
function M.introspect(catalog_url, catalog)
  return invoke(catalog_url, INTROSPECT)
end

--- How a column states where its value comes from. An identity column and a
--- generated column both keep their expression where a default would go, and
--- writing that expression out as a DEFAULT would describe a column that
--- accepts writes when the real one does not.
---@param column dbtree.Column
---@return string
local function column_source(column)
  if column.generated == "s" then
    return " GENERATED ALWAYS AS (" .. (column.default or "") .. ") STORED"
  end
  if column.identity == "a" then
    return " GENERATED ALWAYS AS IDENTITY"
  end
  if column.identity == "d" then
    return " GENERATED BY DEFAULT AS IDENTITY"
  end
  if column.default then
    return " DEFAULT " .. column.default
  end
  return ""
end

--- How `column` reads inside a CREATE TABLE or after an ADD COLUMN.
---@param column dbtree.Column
---@return string
function M.column_definition(column)
  local text = quote.identifier(column.name, M.quoting) .. " " .. (column.type or "")
  text = text .. column_source(column)
  if not column.nullable then
    text = text .. " NOT NULL"
  end
  return text
end

--- Postgres keeps no `CREATE TABLE` text, so a table's statement is rebuilt
--- from the columns and constraints the catalog fetch already returned. A view
--- carries its own definition and is handed back as it came.
---@param relation dbtree.Relation
---@param schema string
---@return string[]
function M.ddl(relation, schema)
  if relation.definition then
    return vim.split(relation.definition, "\n", { plain = true })
  end

  local parts = {}
  for _, column in ipairs(relation.columns or {}) do
    table.insert(parts, M.column_definition(column))
  end
  for _, constraint in ipairs(relation.constraints or {}) do
    if constraint.definition then
      table.insert(
        parts,
        "CONSTRAINT "
          .. quote.identifier(constraint.name, M.quoting)
          .. " "
          .. constraint.definition
      )
    end
  end

  local lines = { "CREATE TABLE " .. quote.qualified(schema, relation.name, M.quoting) .. " (" }
  for index, part in ipairs(parts) do
    table.insert(lines, "    " .. part .. (index < #parts and "," or ""))
  end
  table.insert(lines, ");")

  -- The index behind a primary key or a unique constraint is already stated by
  -- the constraint above, and repeating it as a CREATE INDEX would make the
  -- statement fail against an empty database.
  for _, index in ipairs(relation.indexes or {}) do
    if index.definition and not index.owned_by_constraint then
      table.insert(lines, "")
      table.insert(lines, index.definition .. ";")
    end
  end

  return lines
end

return M
