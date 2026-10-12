--- Finds the node an action works on, and how to quote names for its database.

local databases = require("neo-tree-database.databases")
local quote = require("neo-tree-database.shared.quote")

local M = {}

--- The state neo-tree passes to an action, which it copies from this source's
--- config.
---@class dbtree.State : neotree.StateWithTree, neotree.Config.Database

---@param state neotree.StateWithTree
---@return NuiTree.Node|nil
function M.node_under_cursor(state)
  local node = state.tree:get_node()
  if node and node.extra then
    return node
  end
  return nil
end

---@param node NuiTree.Node
---@return dbtree.Quoting
function M.quoting_for(node)
  local scheme = databases.of(node.extra.url)
  return scheme and scheme.quoting or quote.ANSI
end

return M
