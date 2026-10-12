--- Keeps the loaded and expanded nodes of each connection when the tree is rebuilt.

local M = {}

--- Returns `node` and everything under it as items that neo-tree can build a
--- tree from.
---@param tree NuiTree
---@param node NuiTree.Node
---@return dbtree.Item
local function to_item(tree, node)
  ---@type dbtree.Item
  local item = { id = node.id, name = node.name, type = node.type, extra = node.extra, loaded = node.loaded }
  if node:has_children() then
    item.children = {}
    for _, child in ipairs(tree:get_nodes(node.id)) do
      table.insert(item.children, to_item(tree, child))
    end
  end
  return item
end

--- Copies each connection's loaded state and children from `tree` into
--- `connection_items`, except for a connection whose url changed. neo-tree
--- reopens nodes after a rebuild only by id, and only the ones in the new items.
---@param tree NuiTree
---@param connection_items dbtree.Item[]
function M.restore(tree, connection_items)
  for _, item in ipairs(connection_items) do
    local previous = tree:get_node(item.id)
    if previous and previous.extra.url == item.extra.url then
      item.loaded = previous.loaded
      item.children = to_item(tree, previous).children
    end
  end
end

return M
