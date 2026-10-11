--- Picks the scheme module that handles a connection url.

local url = require("neo-tree-database.url")

local M = {}

-- vim-dadbod accepts both `postgres` and `postgresql` urls.
local MODULE_BY_URL_SCHEME = {
  duckdb = "duckdb",
  postgres = "postgres",
  postgresql = "postgres",
}

---@class dbtree.Scheme
---@field quoting dbtree.Quoting
---@field catalogs fun(connection: string): dbtree.Request
---@field catalog_url fun(connection: string, catalog: string): string
---@field introspect fun(catalog_url: string, catalog: string): dbtree.Request
---@field ddl fun(relation: dbtree.Relation, schema: string): string[]
---@field column_definition fun(column: dbtree.Column): string
---@field catalog_name fun(catalog: string, schema: string, relation: string): string[]

--- Returns the scheme module for the url `connection`, or nil when `connection`
--- is nil or no module handles its scheme.
---@param connection string|nil
---@return dbtree.Scheme|nil
function M.of(connection)
  if type(connection) ~= "string" then
    return nil
  end

  local module_name = MODULE_BY_URL_SCHEME[url.scheme(connection)]
  if not module_name then
    return nil
  end
  return require("neo-tree-database.schemes." .. module_name)
end

--- Returns the url schemes the tree can browse, sorted.
---@return string[]
function M.supported_schemes()
  local url_schemes = vim.tbl_keys(MODULE_BY_URL_SCHEME)
  table.sort(url_schemes)
  return url_schemes
end

return M
