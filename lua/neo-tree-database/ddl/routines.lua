--- Builds the statements for a sequence and a function.

local items = require("neo-tree-database.items")
local quote = require("neo-tree-database.quote")

---@type dbtree.Statements
local M = { info = {}, drop = {}, change = {} }

-- postgres accepts ROUTINE for a function, a procedure and an aggregate alike.
local DROP_KEYWORD = {
  ["function"] = "ROUTINE",
  procedure = "ROUTINE",
  aggregate = "ROUTINE",
  macro = "MACRO",
  table_macro = "MACRO TABLE",
}

local MACRO_KINDS = { macro = true, table_macro = true }

---@param schema string
---@param routine dbtree.Routine
---@param quoting dbtree.Quoting
---@return string
local function qualified_signature(schema, routine, quoting)
  return items.signature(quote.qualified(schema, routine.name, quoting), routine.arguments)
end

---@param schema string
---@param routine dbtree.Routine
---@return string
local function routine_title(schema, routine)
  return schema .. "." .. items.signature(routine.name, routine.arguments)
end

---@param record dbtree.Sequence|dbtree.Routine
---@return string[]
local function definition_lines(record)
  if not record.definition then
    return { "-- " .. record.name .. " has no definition" }
  end
  return vim.split(record.definition, "\n", { plain = true })
end

M.info.sequence = function(node)
  return { title = node.extra.schema .. "." .. node.name, lines = definition_lines(node.extra.record) }
end

M.drop.sequence = function(node, scheme)
  return {
    title = "Drop " .. node.extra.schema .. "." .. node.name,
    lines = { "DROP SEQUENCE " .. quote.qualified(node.extra.schema, node.extra.record.name, scheme.quoting) .. ";" },
  }
end

---@param schema string
---@param overloads dbtree.Routine[]
---@param quoting dbtree.Quoting
---@return string
local function drop_statement(schema, overloads, quoting)
  -- duckdb reports no argument types, so the overloads of a macro share one
  -- signature.
  local signatures, listed = {}, {}
  for _, routine in ipairs(overloads) do
    local signature = qualified_signature(schema, routine, quoting)
    if not listed[signature] then
      listed[signature] = true
      table.insert(signatures, signature)
    end
  end
  return "DROP " .. DROP_KEYWORD[overloads[1].kind] .. " " .. table.concat(signatures, ", ") .. ";"
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
  return { title = routine_title(node.extra.schema, routine), lines = definition_lines(routine) }
end

M.drop.routine = function(node, scheme)
  local routine = node.extra.record
  if MACRO_KINDS[routine.kind] and node.extra.overload then
    return nil, "duckdb drops every overload of a macro at once, from the macro's name"
  end
  return {
    title = "Drop " .. routine_title(node.extra.schema, routine),
    lines = { drop_statement(node.extra.schema, { routine }, scheme.quoting) },
  }
end

M.change.routine = function(node, scheme)
  local routine = node.extra.record
  if MACRO_KINDS[routine.kind] then
    return nil, "duckdb cannot alter a macro"
  end
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
      vim.list_extend(lines, definition_lines(routine))
    end
  end
  if #lines == 0 then
    lines = definition_lines(overloads[1])
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
  if MACRO_KINDS[overloads[1].kind] then
    return nil, "duckdb cannot alter a macro"
  end
  return {
    title = "Alter " .. node.extra.schema .. "." .. node.name,
    lines = vim.tbl_map(function(routine)
      return rename_statement(node.extra.schema, routine, scheme.quoting)
    end, overloads),
  }
end

return M
