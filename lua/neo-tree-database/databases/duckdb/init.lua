--- Builds the duckdb requests for a connection's catalogs and their contents.

local client = require("neo-tree-database.databases.client")
local ddl = require("neo-tree-database.databases.duckdb.ddl")
local queries = require("neo-tree-database.databases.duckdb.sql")
local quote = require("neo-tree-database.shared.quote")

local M = {
  quoting = quote.ANSI,
  ddl = ddl.ddl,
  column_definition = ddl.column_definition,
  statements = require("neo-tree-database.databases.duckdb.statements"),
}

---@param connection string
---@param sql string
---@return dbtree.Request
local function request_for(connection, sql)
  return { url = connection, statement = sql, decode = client.json_object }
end

--- Returns `connection` unchanged, because one duckdb process reaches every
--- catalog that the connection's file attaches.
---@param connection string
---@return string
function M.catalog_url(connection)
  return connection
end

--- Returns a request that lists the connection's catalogs.
---@param connection string
---@param features dbtree.Features
---@return dbtree.Request
function M.catalogs(connection, features)
  return request_for(connection, queries.catalogs(features.read_sizes))
end

---@param catalog_url string
---@param catalog string
---@param features dbtree.Features
---@return dbtree.Request
function M.introspect(catalog_url, catalog, features)
  return request_for(catalog_url, quote.render(queries.introspect(features.read_sizes), {
    catalog = quote.literal(catalog, quote.ANSI),
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

return M
