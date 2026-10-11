--- Builds the duckdb queries for a connection's catalogs and their contents, and
--- the ddl of a duckdb relation.

local quote = require("neo-tree-database.quote")
local url = require("neo-tree-database.url")

local M = {}

M.quoting = quote.ANSI

---@param connection string
---@param sql string
---@return dbtree.Request
local function request_for(connection, sql)
  local argv = { "duckdb" }
  local path = url.file(connection)
  if path ~= "" then
    -- -readonly leaves the file unlocked for the user's own duckdb session, and
    -- duckdb rejects it for the in-memory database.
    vim.list_extend(argv, { path, "-readonly" })
  end
  vim.list_extend(argv, { "-noheader", "-list", "-c", sql })
  return { argv = argv }
end

--- Returns `connection` unchanged, because one duckdb process reaches every
--- catalog that the connection's file attaches.
---@param connection string
---@return string
function M.catalog_url(connection)
  return connection
end

-- duckdb reports no blocks for an in-memory database.
local CATALOGS = [[
select json_object('catalogs', coalesce(
  (select to_json(list(json_object(
     'name', d.database_name,
     'size', case when s.total_blocks > 0 then s.block_size * s.total_blocks end
   ) order by d.database_name))
   from duckdb_databases() d
   left join pragma_database_size() s on s.database_name = d.database_name
   where not d.internal),
  '[]'::json))
]]

---@param connection string
---@return dbtree.Request
function M.catalogs(connection)
  return request_for(connection, CATALOGS)
end

-- duckdb lists each NOT NULL as a constraint, which the column rows already
-- show. A macro gets no definition, because duckdb_functions() leaves out
-- parameter defaults.
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
    ), '[]'::json),
    'sequences', coalesce((
      select to_json(list(json_object(
        'name', q.sequence_name,
        'definition', q.sql
      ) order by q.sequence_name))
      from duckdb_sequences() q
      where q.database_name = s.database_name and q.schema_name = s.schema_name
    ), '[]'::json),
    'functions', coalesce((
      select to_json(list(json_object(
        'name', f.function_name,
        'kind', f.function_type,
        'args', to_json(list_transform(
          list_zip(f.parameters, f.parameter_types),
          lambda p: json_object('name', p[1], 'type', p[2], 'mode', 'in')
        ))
      ) order by f.function_name, len(f.parameters), f.parameters::varchar))
      from duckdb_functions() f
      where not f.internal
        and f.database_name = s.database_name and f.schema_name = s.schema_name
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
  return request_for(catalog_url, quote.render(INTROSPECT, {
    catalog = quote.literal(catalog),
  }))
end

--- Returns the name path that db-query's catalog knows a relation by. It starts
--- at the database, because db-query keeps one catalog for every attached
--- database.
---@param catalog string
---@param schema string
---@param relation string
---@return string[]
function M.catalog_name(catalog, schema, relation)
  return { catalog, schema, relation }
end

--- Returns `column` as it reads in a CREATE TABLE or after ADD COLUMN.
---@param column dbtree.Column
---@return string
function M.column_definition(column)
  local definition = quote.identifier(column.name, M.quoting) .. " " .. (column.type or "")
  if column.default then
    definition = definition .. " DEFAULT " .. column.default
  end
  if not column.nullable then
    definition = definition .. " NOT NULL"
  end
  return definition
end

--- Returns the statements that created `relation` and its indexes, as duckdb
--- keeps them.
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
