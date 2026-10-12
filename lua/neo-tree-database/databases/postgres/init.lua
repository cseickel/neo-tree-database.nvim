--- Builds the psql requests for a server's databases and their contents.

local ddl = require("neo-tree-database.databases.postgres.ddl")
local queries = require("neo-tree-database.databases.postgres.sql")
local quote = require("neo-tree-database.shared.quote")
local url = require("neo-tree-database.shared.url")

local M = {
  quoting = quote.ANSI,
  ddl = ddl.ddl,
  column_definition = ddl.column_definition,
}

--- Returns a request that runs `commands` in order on one psql connection.
---@param connection string
---@param commands string[]
---@return dbtree.Request
local function request_for(connection, commands)
  -- -X skips psqlrc, and -q keeps a SET from printing its command tag.
  local argv = { "psql", connection, "-X", "-q", "-A", "-t", "-v", "ON_ERROR_STOP=1" }
  for _, command in ipairs(commands) do
    vim.list_extend(argv, { "-c", command })
  end
  return { argv = argv }
end

local SET_LOCK_TIMEOUT = "set lock_timeout = '5s'"
-- psql shows an error's SQLSTATE only at verbose verbosity.
local VERBOSE_ERRORS = "\\set VERBOSITY verbose"
local LOCK_TIMEOUT_SQLSTATE = "55P03"

--- Returns the url of `catalog` on the server that `connection` reaches. postgres
--- queries one database per connection.
---@param connection string
---@param catalog string
---@return string
function M.catalog_url(connection, catalog)
  return url.with_database(connection, catalog)
end

---@param connection string
---@return dbtree.Request
function M.catalogs(connection)
  return request_for(connection, { queries.CATALOGS })
end

--- Returns a request that reads `catalog` with sizes measured on disk. Measuring
--- takes locks, so when it times out waiting for one, the request falls back to
--- the sizes that pg_class last recorded.
---@param catalog_url string
---@param catalog string
---@return dbtree.Request
function M.introspect(catalog_url, catalog)
  local request = request_for(catalog_url, { VERBOSE_ERRORS, SET_LOCK_TIMEOUT, queries.INTROSPECT })
  request.fallback = {
    error = LOCK_TIMEOUT_SQLSTATE,
    request = request_for(catalog_url, { SET_LOCK_TIMEOUT, queries.INTROSPECT_ESTIMATED }),
  }
  return request
end

--- Returns the name path that db-query's catalog knows a relation by. It starts
--- at the schema, because db-query keeps one catalog per database.
---@param catalog string
---@param schema string
---@param relation string
---@return string[]
function M.catalog_name(catalog, schema, relation)
  return { schema, relation }
end

return M
