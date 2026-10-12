--- Defines the actions that show the CREATE, DROP or ALTER statement for the node
--- under the cursor in a popup.

local scratch = require("neo-tree-database.actions.scratch")
local shared = require("neo-tree-database.actions.shared")
local statements = require("neo-tree-database.popups.statements")
local window = require("neo-tree-database.popups.window")

local M = {}

--- Shows the statement that `build` returns for the node under the cursor in a
--- popup, which can open it in a scratch buffer.
---@param state dbtree.State
---@param build fun(node: NuiTree.Node): dbtree.Statement|nil, string|nil
local function show_statement(state, build)
  local node = shared.node_under_cursor(state)
  if not node then
    return
  end

  local statement, err = build(node)
  if not statement then
    return vim.notify("neo-tree database: " .. err, vim.log.levels.WARN)
  end

  window.show({
    title = statement.title,
    lines = statement.lines,
    language = "sql",
    on_open = function(lines)
      scratch.open({
        state = state,
        url = node.extra.url,
        lines = lines,
        title = statement.title,
      })
    end,
  })
end

---@param state dbtree.State
function M.object_info(state)
  show_statement(state, statements.info)
end

---@param state dbtree.State
function M.object_drop(state)
  show_statement(state, statements.drop)
end

---@param state dbtree.State
function M.object_change(state)
  show_statement(state, statements.change)
end

return M
