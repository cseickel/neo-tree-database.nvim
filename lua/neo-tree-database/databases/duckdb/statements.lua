--- Builds the statements that drop or alter a duckdb macro, which take the place
--- of the shared function statements.

local quote = require("neo-tree-database.shared.quote")

---@type dbtree.Statements
local M = { info = {}, drop = {}, change = {} }

local DROP_KEYWORD = { macro = "MACRO", table_macro = "MACRO TABLE" }

-- duckdb reports no argument types, so a macro is dropped by its name alone,
-- which drops every overload.
---@param node NuiTree.Node
---@param macro dbtree.Routine
---@param quoting dbtree.Quoting
---@return dbtree.Statement
local function drop_macro(node, macro, quoting)
  local schema = node.extra.schema
  return {
    title = "Drop " .. schema .. "." .. macro.name,
    lines = { "DROP " .. DROP_KEYWORD[macro.kind] .. " " .. quote.qualified(schema, macro.name, quoting) .. ";" },
  }
end

M.drop.routine = function(node, scheme)
  if node.extra.overload then
    return nil, "duckdb drops every overload of a macro at once, from the macro's name"
  end
  return drop_macro(node, node.extra.record, scheme.quoting)
end

M.drop.overloaded_routine = function(node, scheme)
  return drop_macro(node, node.extra.record[1], scheme.quoting)
end

local function cannot_alter()
  return nil, "duckdb cannot alter a macro"
end

M.change.routine = cannot_alter
M.change.overloaded_routine = cannot_alter

return M
