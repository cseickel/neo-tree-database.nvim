--[[
duckdb.

The `duckdb_*()` table functions are used rather than `information_schema`,
because they carry the index sql, the constraint names and the referenced table
that the standard views leave out. They also avoid the `.tables` dot command,
whose output format changed in duckdb 1.5.1.

A duckdb process sees only the catalogs it attached itself, so the catalog list
holds the file this connection names and nothing else. What another process
attached is invisible, which is the truth about what this connection reaches.
]]

local quote = require("neo-tree-database.quote")
local url = require("neo-tree-database.url")

local M = {}

M.quoting = quote.ANSI

--- Every invocation prints one row of one column with no header and no padding,
--- so stdout is the json document and nothing else.
---@param connection string
---@param sql string
---@return dbtree.Request
local function invoke(connection, sql)
  local argv = { "duckdb" }
  local file = url.file(connection)
  if file ~= "" then
    -- Read-only leaves the file unlocked for the user's own duckdb session.
    -- duckdb rejects the flag outright for the in-memory database, which is
    -- what an empty file name means.
    vim.list_extend(argv, { file, "-readonly" })
  end
  vim.list_extend(argv, { "-noheader", "-list", "-c", sql })
  return { argv = argv }
end

--- Every catalog is reached through the one file, so the connection url answers
--- for all of them.
---@param connection string
---@return string
function M.catalog_url(connection)
  return connection
end

---@param connection string
---@return dbtree.Request
function M.catalogs(connection)
  return invoke(
    connection,
    [[select json_object('catalogs', coalesce(
      (select to_json(list(database_name order by database_name))
       from duckdb_databases() where not internal),
      '[]'::json))]]
  )
end

-- NOT NULL is a constraint of its own in duckdb, and the Columns node already
-- says which columns are nullable, so it is dropped here rather than listed
-- once per column under Constraints.
local INTROSPECT = [[
select json_object('schemas', coalesce((
  select to_json(list(json_object(
    'name', s.schema_name,
    'relations', coalesce((
      select to_json(list(json_object(
        'name', r.name,
        'kind', r.kind,
        'rows', r.rows,
        'definition', r.sql,
        'columns', coalesce((
          select to_json(list(json_object(
            'name', c.column_name,
            'type', c.data_type,
            'nullable', c.is_nullable,
            'default', c.column_default,
            'position', c.column_index
          ) order by c.column_index))
          from duckdb_columns() c
          where c.database_name = r.database_name
            and c.schema_name = r.schema_name
            and c.table_name = r.name
        ), '[]'::json),
        'indexes', coalesce((
          select to_json(list(json_object(
            'name', i.index_name,
            'unique', i.is_unique,
            'columns', to_json(string_split(trim(i.expressions, '[]'), ', ')),
            'definition', i.sql
          ) order by i.index_name))
          from duckdb_indexes() i
          where i.database_name = r.database_name
            and i.schema_name = r.schema_name
            and i.table_name = r.name
        ), '[]'::json),
        'constraints', coalesce((
          select to_json(list(json_object(
            'name', k.constraint_name,
            'type', k.constraint_type,
            'definition', k.constraint_text
          ) order by k.constraint_name))
          from duckdb_constraints() k
          where k.database_name = r.database_name
            and k.schema_name = r.schema_name
            and k.table_name = r.name
            and k.constraint_type <> 'NOT NULL'
        ), '[]'::json)
      ) order by r.name))
      from (
        select database_name, schema_name, table_name as name, 'table' as kind,
               estimated_size as rows, sql
        from duckdb_tables()
        union all
        select database_name, schema_name, view_name as name, 'view' as kind,
               null as rows, sql
        from duckdb_views() where not internal
      ) r
      where r.database_name = s.database_name and r.schema_name = s.schema_name
    ), '[]'::json)
  ) order by s.schema_name))
  from duckdb_schemas() s
  where s.database_name = @catalog
), '[]'::json))
]]

---@param catalog_url string
---@param catalog string
---@return dbtree.Request
function M.introspect(catalog_url, catalog)
  return invoke(catalog_url, quote.render(INTROSPECT, {
    catalog = quote.literal(catalog),
  }))
end

--- How `column` reads inside a CREATE TABLE or after an ADD COLUMN.
---@param column dbtree.Column
---@return string
function M.column_definition(column)
  local text = quote.identifier(column.name, M.quoting) .. " " .. (column.type or "")
  if column.default then
    text = text .. " DEFAULT " .. column.default
  end
  if not column.nullable then
    text = text .. " NOT NULL"
  end
  return text
end

--- duckdb keeps the statement each object was created with, so nothing is
--- rebuilt here. An index is created separately from its table and is appended
--- so the whole table arrives in one piece.
---@param relation dbtree.Relation
---@param schema string
---@return string[]
function M.ddl(relation, schema)
  local lines = {}
  if relation.definition then
    vim.list_extend(lines, vim.split(relation.definition, "\n", { plain = true }))
  end
  for _, index in ipairs(relation.indexes or {}) do
    if index.definition then
      table.insert(lines, "")
      vim.list_extend(lines, vim.split(index.definition, "\n", { plain = true }))
    end
  end
  return lines
end

return M
