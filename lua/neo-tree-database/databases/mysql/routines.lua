--- Builds a mysql function or procedure from the rows that describe it.

local quote = require("neo-tree-database.shared.quote")

local M = {}

--- Returns the CREATE statement of the routine `row` describes, rebuilt around
--- its body, because information_schema keeps only the body.
---@param catalog string
---@param row table
---@param args dbtree.Argument[]
---@return string
local function definition(catalog, row, args)
  local is_procedure = row.kind == "PROCEDURE"
  local declared = vim.tbl_map(function(arg)
    local mode = is_procedure and (arg.mode:upper() .. " ") or ""
    return mode .. quote.identifier(arg.name or "", quote.MYSQL) .. " " .. (arg.type or "")
  end, args)
  local lines = {
    "CREATE "
      .. row.kind
      .. " "
      .. quote.qualified(catalog, row.name, quote.MYSQL)
      .. "("
      .. table.concat(declared, ", ")
      .. ")",
  }
  if not is_procedure then
    table.insert(lines, "RETURNS " .. row.returns)
  end
  if row.deterministic == "YES" then
    table.insert(lines, "DETERMINISTIC")
  end
  if row.data_access and row.data_access ~= "CONTAINS SQL" then
    table.insert(lines, row.data_access)
  end
  if row.security == "INVOKER" then
    table.insert(lines, "SQL SECURITY INVOKER")
  end
  table.insert(lines, row.body)
  return table.concat(lines, "\n")
end

--- Returns the routine `row` describes, with `params` its parameter rows in
--- order. Its definition is nil when the user may not read its body.
---@param catalog string
---@param row table
---@param params table[]
---@return dbtree.Routine
function M.routine(catalog, row, params)
  local kind = row.kind:lower()
  local args = vim.tbl_map(function(param)
    return { name = param.name, type = param.type, mode = param.mode and param.mode:lower() or "in" }
  end, params)
  return {
    name = row.name,
    kind = kind,
    args = args,
    returns = kind == "function" and { type = row.returns, set = false } or nil,
    definition = row.body and definition(catalog, row, args) or nil,
  }
end

return M
