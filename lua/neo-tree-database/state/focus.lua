--- Sets the tree buffer's `b:db` and `b:db_name`, which vim-dadbod and db-query
--- read, to the connection of the node under the cursor.

local events = require("neo-tree.events")
local manager = require("neo-tree.sources.manager")

local M = {}

--- Returns the `b:db_name` for `node`, such as `warehouse/sales` for the `sales`
--- database on the `warehouse` connection, or nil for a node above a connection.
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
local function set_from_cursor(source_name)
  local state = manager.get_state_for_window()
  if not state or state.name ~= source_name or not state.tree then
    return
  end
  local node = state.tree:get_node()
  vim.b.db = node and node.extra.url
  vim.b.db_name = node and M.db_name(node)
end

--- Updates `b:db` and `b:db_name` whenever the cursor enters or moves in the
--- tree of `source_name`.
---@param source_name string
function M.follow_cursor(source_name)
  for _, event in ipairs({ events.NEO_TREE_BUFFER_ENTER, events.VIM_CURSOR_MOVED }) do
    manager.subscribe(source_name, {
      event = event,
      handler = function()
        set_from_cursor(source_name)
      end,
    })
  end
end

return M
