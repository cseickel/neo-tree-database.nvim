--- Defines the action that copies the sql name of the node under the cursor.

local quote = require("neo-tree-database.shared.quote")
local shared = require("neo-tree-database.actions.shared")

local M = {}

---@param extra table
---@return string
local function own_name(extra)
  return extra.record.name
end

---@param extra table
---@param quoting dbtree.Quoting
---@return string
local function relation_name(extra, quoting)
  return quote.qualified(extra.schema, extra.relation, quoting)
end

---@type table<string, fun(extra: table, quoting: dbtree.Quoting): string>
local SQL_NAMES = {
  catalog = function(extra, quoting)
    return quote.identifier(extra.catalog, quoting)
  end,
  schema = function(extra, quoting)
    return quote.identifier(extra.schema, quoting)
  end,
  table = relation_name,
  view = relation_name,
  materialized_view = relation_name,
  column = own_name,
  index = own_name,
  constraint = own_name,
  sequence = function(extra, quoting)
    return quote.qualified(extra.schema, extra.record.name, quoting)
  end,
  routine = function(extra, quoting)
    return quote.signature(quote.qualified(extra.schema, extra.record.name, quoting), extra.record.arguments)
  end,
  overloaded_routine = function(extra, quoting)
    return quote.qualified(extra.schema, extra.record[1].name, quoting)
  end,
  role = function(extra, quoting)
    return quote.identifier(extra.record.name, quoting)
  end,
}

---@param node NuiTree.Node
---@return string|nil
local function sql_name(node)
  local name_of = SQL_NAMES[node.type]
  if not name_of then
    return nil
  end
  return name_of(node.extra, shared.quoting_for(node))
end

---@param state neotree.StateWithTree
function M.yank_name(state)
  local node = shared.node_under_cursor(state)
  if not node then
    return
  end

  local name = sql_name(node)
  if not name then
    return vim.notify("neo-tree database: nothing here to name", vim.log.levels.WARN)
  end
  vim.fn.setreg('"', name, "c")
  vim.fn.setreg("+", name, "c")
  vim.fn.setreg("*", name, "c")
  vim.notify("neo-tree database: copied " .. name)
end

return M
