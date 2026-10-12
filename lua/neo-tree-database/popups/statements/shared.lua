--- Splits an object's stored definition into the lines a statement shows.

local M = {}

--- Returns the lines of `record.definition`, or a comment saying it has none.
---@param record { name: string, definition: string|nil }
---@return string[]
function M.definition_lines(record)
  if not record.definition then
    return { "-- " .. record.name .. " has no definition" }
  end
  return vim.split(record.definition, "\n", { plain = true })
end

return M
