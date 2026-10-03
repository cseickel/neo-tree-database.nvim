--[[
The statements for a sequence and a function.

A function of any postgres kind is named in a statement as a ROUTINE, which
postgres accepts for a function, a procedure and an aggregate alike. A duckdb
macro is dropped by its own keyword and cannot be altered.
]]

local items = require("neo-tree-database.items")
local quote = require("neo-tree-database.quote")

---@type dbtree.Statements
local M = { info = {}, drop = {}, change = {} }

--- The keyword each kind of function is dropped by.
local DROP_KEYWORD = {
  ["function"] = "ROUTINE",
  procedure = "ROUTINE",
  aggregate = "ROUTINE",
  macro = "MACRO",
  table_macro = "MACRO TABLE",
}

---@param node NuiTree.Node
---@return dbtree.Statement
local function definition(node)
  local record = node.extra.record
  local title = node.extra.schema .. "." .. node.name
  if not record.definition then
    return { title = title, lines = { "-- " .. node.name .. " has no definition" } }
  end
  return { title = title, lines = vim.split(record.definition, "\n", { plain = true }) }
end

M.info.sequence = definition
M.info.routine = definition

M.drop.sequence = function(node, scheme)
  return {
    title = "Drop " .. node.extra.schema .. "." .. node.name,
    lines = { "DROP SEQUENCE " .. quote.qualified(node.extra.schema, node.extra.record.name, scheme.quoting) .. ";" },
  }
end

--- `schema`.`name`(arguments) of the function `node`.
---@param node NuiTree.Node
---@param quoting dbtree.Quoting
---@return string
local function routine_name(node, quoting)
  local record = node.extra.record
  return items.signature(quote.qualified(node.extra.schema, record.name, quoting), record.arguments)
end

M.drop.routine = function(node, scheme)
  return {
    title = "Drop " .. node.extra.schema .. "." .. node.name,
    lines = { "DROP " .. DROP_KEYWORD[node.extra.record.kind] .. " " .. routine_name(node, scheme.quoting) .. ";" },
  }
end

M.change.routine = function(node, scheme)
  local record = node.extra.record
  if record.kind == "macro" or record.kind == "table_macro" then
    return nil, "duckdb cannot alter a macro"
  end
  return {
    title = "Alter " .. node.extra.schema .. "." .. node.name,
    lines = {
      "ALTER ROUTINE "
        .. routine_name(node, scheme.quoting)
        .. " RENAME TO "
        .. quote.identifier(record.name, scheme.quoting)
        .. ";",
    },
  }
end

return M
