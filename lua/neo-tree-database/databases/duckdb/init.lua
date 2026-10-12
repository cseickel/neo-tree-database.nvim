--- Builds the duckdb requests for a connection's catalogs and their contents.

local ddl = require("neo-tree-database.databases.duckdb.ddl")
local queries = require("neo-tree-database.databases.duckdb.sql")
local quote = require("neo-tree-database.shared.quote")
local url = require("neo-tree-database.shared.url")

local M = {
  quoting = quote.ANSI,
  ddl = ddl.ddl,
  column_definition = ddl.column_definition,
}

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

---@param connection string
---@return dbtree.Request
function M.catalogs(connection)
  return request_for(connection, queries.CATALOGS)
end

---@param catalog_url string
---@param catalog string
---@return dbtree.Request
function M.introspect(catalog_url, catalog)
  return request_for(catalog_url, quote.render(queries.INTROSPECT, {
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

return M
