--- Builds the psql requests for a server's databases and their contents.

local client = require("neo-tree-database.databases.client")
local ddl = require("neo-tree-database.databases.postgres.ddl")
local queries = require("neo-tree-database.databases.postgres.sql")
local quote = require("neo-tree-database.shared.quote")
local url = require("neo-tree-database.shared.url")

local RELATION_PRIVILEGES = { "SELECT", "INSERT", "UPDATE", "DELETE", "TRUNCATE", "REFERENCES", "TRIGGER", "MAINTAIN" }
local ROUTINE_PRIVILEGES = { "EXECUTE" }

local M = {
  quoting = quote.ANSI,
  ddl = ddl.ddl,
  column_definition = ddl.column_definition,
  privileges = {
    database = { "CONNECT", "CREATE", "TEMPORARY" },
    schema = { "USAGE", "CREATE" },
    table = RELATION_PRIVILEGES,
    view = RELATION_PRIVILEGES,
    materialized_view = RELATION_PRIVILEGES,
    column = { "SELECT", "INSERT", "UPDATE", "REFERENCES" },
    sequence = { "SELECT", "UPDATE", "USAGE" },
    ["function"] = ROUTINE_PRIVILEGES,
    procedure = ROUTINE_PRIVILEGES,
    aggregate = ROUTINE_PRIVILEGES,
  },
}

--- Returns a request that runs `script`, lines of psql input, on `connection`.
---@param connection string
---@param script string[]
---@return dbtree.Request
local function request_for(connection, script)
  return { url = connection, statement = table.concat(script, "\n"), decode = client.json_object }
end

local SET_LOCK_TIMEOUT = "set lock_timeout = '5s';"
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
---@param features dbtree.Features
---@return dbtree.Request
function M.catalogs(connection, features)
  return request_for(connection, { queries.catalogs(features.read_sizes) })
end

--- Returns a request that reads `catalog`. With sizes, it measures them on disk.
--- Measuring takes locks, so when it times out waiting for one, the request
--- falls back to the sizes that pg_class last recorded.
---@param catalog_url string
---@param catalog string
---@param features dbtree.Features
---@return dbtree.Request
function M.introspect(catalog_url, catalog, features)
  local grants = features.read_grants
  if not features.read_sizes then
    return request_for(catalog_url, { VERBOSE_ERRORS, SET_LOCK_TIMEOUT, queries.introspect({ grants = grants }) })
  end
  local request = request_for(catalog_url, {
    VERBOSE_ERRORS,
    SET_LOCK_TIMEOUT,
    queries.introspect({ sizes = queries.EXACT_SIZES, grants = grants }),
  })
  request.fallback = {
    error = LOCK_TIMEOUT_SQLSTATE,
    request = request_for(catalog_url, {
      SET_LOCK_TIMEOUT,
      queries.introspect({ sizes = queries.ESTIMATED_SIZES, grants = grants }),
    }),
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
