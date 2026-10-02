--[[
The tree buffer's `b:db` and `b:db_name` name the connection of the node under
the cursor, so vim-dadbod and db-query commands run from the tree reach the
database in focus. A node above a connection names none, and clears both.
]]

local events = require("neo-tree.events")
local manager = require("neo-tree.sources.manager")

local M = {}

--- The name `b:db_name` takes for `node`, such as `warehouse/sales` for a
--- database on the `warehouse` connection, or nil above a connection.
---@param node NuiTree.Node
---@return string|nil
function M.db_name(node)
  local extra = node.extra
  if not extra.connection then
    return nil
  end
  if extra.catalog then
    return extra.connection.name .. "/" .. extra.catalog
  end
  return extra.connection.name
end

---@param source_name string
local function follow(source_name)
  local state = manager.get_state_for_window()
  if not state or state.name ~= source_name or not state.tree then
    return
  end
  local node = state.tree:get_node()
  vim.b.db = node and node.extra.url
  vim.b.db_name = node and M.db_name(node)
end

--- Keeps the tree buffer's connection on the node under the cursor, from
--- entering the window and on every move after.
---@param source_name string
function M.track(source_name)
  for _, event in ipairs({ events.NEO_TREE_BUFFER_ENTER, events.VIM_CURSOR_MOVED }) do
    manager.subscribe(source_name, {
      event = event,
      handler = function()
        follow(source_name)
      end,
    })
  end
end

return M
