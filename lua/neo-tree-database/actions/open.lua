--- Defines the actions that expand, collapse and refresh nodes.

local manager = require("neo-tree.sources.manager")
local nodes = require("neo-tree-database.nodes")
local renderer = require("neo-tree.ui.renderer")
local shared = require("neo-tree-database.actions.shared")

local M = {}

--- Expands or collapses the node under the cursor, loading its children the
--- first time it expands.
---@param state neotree.StateWithTree
function M.open(state)
  local node = shared.node_under_cursor(state)
  if not node then
    return
  end

  if node:is_expanded() then
    node:collapse()
    return renderer.redraw(state)
  end

  if not node.loaded and nodes.is_container(node) then
    return nodes.expand(state, node)
  end

  if node:has_children() then
    node:expand()
    renderer.redraw(state)
  end
end

--- Rebuilds the tree from the connection list and keeps the cached answers.
---@param state neotree.StateWithTree
function M.refresh(state)
  manager.navigate(state)
end

--- Queries the database again for the nearest node at or above the cursor that
--- holds `documents`.
---@param state neotree.StateWithTree
function M.refresh_node(state)
  local node = state.tree:get_node()
  while node and not (node.extra and node.extra.documents) do
    local parent_id = node:get_parent_id()
    node = parent_id and state.tree:get_node(parent_id) or nil
  end

  if not node then
    return vim.notify("neo-tree database: nothing here to refresh", vim.log.levels.WARN)
  end
  nodes.refresh(state, node)
end

return M
