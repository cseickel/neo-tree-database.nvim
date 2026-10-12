--- Defines the action that shows db-query's description of a table, view or
--- column.

local databases = require("neo-tree-database.databases")
local focus = require("neo-tree-database.state.focus")
local shared = require("neo-tree-database.actions.shared")
local window = require("neo-tree-database.popups.window")

local M = {}

local DESCRIBABLE_TYPES = { table = true, view = true, materialized_view = true, column = true }

-- db-query's describe reports these errors as codes and every other error as a
-- sentence.
---@type table<string, fun(node: NuiTree.Node): string>
local DESCRIBE_ERROR_MESSAGES = {
  ["reading"] = function(node)
    return ("db-query is still reading the catalog of %s. Try again in a moment."):format(focus.db_name(node))
  end,
  ["no catalog"] = function(node)
    return ("db-query could not read the catalog of %s. Run :DBRefreshCatalog to try again."):format(
      focus.db_name(node)
    )
  end,
  ["not found"] = function(node)
    return ("db-query's catalog of %s has no %s. If it was created after the catalog was read, run :DBRefreshCatalog."):format(
      focus.db_name(node),
      node.name
    )
  end,
}

---@param state neotree.StateWithTree
function M.describe(state)
  local node = shared.node_under_cursor(state)
  if not node or not DESCRIBABLE_TYPES[node.type] then
    return vim.notify("neo-tree database: nothing here to describe", vim.log.levels.WARN)
  end

  local scheme = databases.of(node.extra.url)
  if not scheme then
    return vim.notify("neo-tree database: cannot describe " .. node.extra.url, vim.log.levels.WARN)
  end

  local extra = node.extra
  local lines, err = require("db-query").describe({
    url = extra.url,
    relation = scheme.catalog_name(extra.catalog, extra.schema, extra.relation),
    column = node.type == "column" and extra.record.name or nil,
  })
  if not lines then
    local message_for = DESCRIBE_ERROR_MESSAGES[err]
    return vim.notify("neo-tree database: " .. (message_for and message_for(node) or err), vim.log.levels.WARN)
  end

  local title = node.type == "column" and (extra.relation .. "." .. extra.record.name)
    or (extra.schema .. "." .. extra.relation)
  window.show({ title = title, lines = lines, language = "markdown" })
end

return M
