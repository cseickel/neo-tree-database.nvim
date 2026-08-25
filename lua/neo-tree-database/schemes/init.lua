--[[
Choosing what speaks a url.

Each scheme module owns everything its database does differently: how its client
is invoked, what sql lists its catalogs, what sql describes one, and how its
ddl is produced. Adding a database is adding a module and a line here, and
touches nothing else.
]]

local url = require("neo-tree-database.url")

local M = {}

--- Both spellings of the postgres url scheme reach the same module, because
--- vim-dadbod accepts either and a connections file may hold either.
local MODULES = {
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

--- The module that speaks `connection`, nil when nothing here does.
---
--- A node above a connection carries no url, and asking what speaks for it is
--- how a command written for one node reaches the root, so a missing url is
--- answered rather than raised.
---@param connection string|nil
---@return dbtree.Scheme|nil
function M.of(connection)
  if type(connection) ~= "string" then
    return nil
  end

  local name = MODULES[url.scheme(connection)]
  if not name then
    return nil
  end
  return require("neo-tree-database.schemes." .. name)
end

--- Every url scheme the tree can browse, sorted, for the message a connection
--- it cannot browse renders.
---@return string[]
function M.supported()
  local names = vim.tbl_keys(MODULES)
  table.sort(names)
  return names
end

return M
