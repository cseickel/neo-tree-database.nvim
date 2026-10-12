--- Builds the statements for a function and for every overload of one name.

local quote = require("neo-tree-database.shared.quote")
local shared = require("neo-tree-database.popups.statements.shared")

---@type dbtree.Statements
local M = { info = {}, drop = {}, change = {} }

---@param schema string
---@param routine dbtree.Routine
---@param quoting dbtree.Quoting
---@return string
local function qualified_signature(schema, routine, quoting)
  return quote.signature(quote.qualified(schema, routine.name, quoting), routine.arguments)
end

---@param schema string
---@param routine dbtree.Routine
---@return string
local function routine_title(schema, routine)
  return schema .. "." .. quote.signature(routine.name, routine.arguments)
end

-- postgres accepts ROUTINE for a function, a procedure and an aggregate alike.
---@param schema string
---@param overloads dbtree.Routine[]
---@param quoting dbtree.Quoting
---@return string
local function drop_statement(schema, overloads, quoting)
  local signatures = vim.tbl_map(function(routine)
    return qualified_signature(schema, routine, quoting)
  end, overloads)
  return "DROP ROUTINE " .. table.concat(signatures, ", ") .. ";"
end

---@param schema string
---@param routine dbtree.Routine
---@param quoting dbtree.Quoting
---@return string
local function rename_statement(schema, routine, quoting)
  return "ALTER ROUTINE "
    .. qualified_signature(schema, routine, quoting)
    .. " RENAME TO "
    .. quote.identifier(routine.name, quoting)
    .. ";"
end

M.info.routine = function(node)
  local routine = node.extra.record
  return { title = routine_title(node.extra.schema, routine), lines = shared.definition_lines(routine) }
end

M.drop.routine = function(node, scheme)
  local routine = node.extra.record
  return {
    title = "Drop " .. routine_title(node.extra.schema, routine),
    lines = { drop_statement(node.extra.schema, { routine }, scheme.quoting) },
  }
end

M.change.routine = function(node, scheme)
  local routine = node.extra.record
  return {
    title = "Alter " .. routine_title(node.extra.schema, routine),
    lines = { rename_statement(node.extra.schema, routine, scheme.quoting) },
  }
end

M.info.overloaded_routine = function(node)
  local overloads = node.extra.record
  local lines = {}
  for _, routine in ipairs(overloads) do
    if routine.definition then
      if #lines > 0 then
        table.insert(lines, "")
      end
      vim.list_extend(lines, shared.definition_lines(routine))
    end
  end
  if #lines == 0 then
    lines = shared.definition_lines(overloads[1])
  end
  return { title = node.extra.schema .. "." .. node.name, lines = lines }
end

M.drop.overloaded_routine = function(node, scheme)
  return {
    title = "Drop " .. node.extra.schema .. "." .. node.name,
    lines = { drop_statement(node.extra.schema, node.extra.record, scheme.quoting) },
  }
end

M.change.overloaded_routine = function(node, scheme)
  local overloads = node.extra.record
  return {
    title = "Alter " .. node.extra.schema .. "." .. node.name,
    lines = vim.tbl_map(function(routine)
      return rename_statement(node.extra.schema, routine, scheme.quoting)
    end, overloads),
  }
end

return M
