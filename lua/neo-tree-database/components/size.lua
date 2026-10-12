--- Defines the size and rows components, which draw a node's size on disk and its
--- row estimate in right-aligned columns.

local highlights = require("neo-tree-database.shared.highlights")

local M = {}

---@class dbtree.Unit
---@field base number
---@field suffix string
---@field highlight string

---@type dbtree.Unit[]
local ROW_UNITS = {
  { base = 1e12, suffix = "T", highlight = highlights.ROWS_B },
  { base = 1e9, suffix = "B", highlight = highlights.ROWS_B },
  { base = 1e6, suffix = "M", highlight = highlights.ROWS_M },
  { base = 1e3, suffix = "K", highlight = highlights.ROWS_K },
  { base = 1, suffix = "", highlight = highlights.ROWS_K },
}

---@type dbtree.Unit[]
local BYTE_UNITS = {
  { base = 2 ^ 40, suffix = " TB", highlight = highlights.SIZE_GB },
  { base = 2 ^ 30, suffix = " GB", highlight = highlights.SIZE_GB },
  { base = 2 ^ 20, suffix = " MB", highlight = highlights.SIZE_MB },
  { base = 2 ^ 10, suffix = " KB", highlight = highlights.SIZE_KB },
  { base = 1, suffix = " B", highlight = highlights.SIZE_KB },
}

-- Fits `~999K rows`.
local ROWS_WIDTH = 10
-- Fits `~973 KB`.
local SIZE_WIDTH = 7

--- Returns `value` in the largest unit that it rounds to at least 1 of, and that
--- unit's highlight. An amount under 10 gets one decimal, and an amount in the
--- last unit is written as a whole number.
---@param value number
---@param units dbtree.Unit[]
---@return string text
---@return string highlight
local function format_scaled(value, units)
  for i = 1, #units - 1 do
    local unit = units[i]
    local amount = value / unit.base
    local text = ("%.1f"):format(amount)
    if tonumber(text) >= 10 then
      text = ("%.0f"):format(amount)
    end
    if tonumber(text) >= 1 then
      return text .. unit.suffix, unit.highlight
    end
  end
  local unit = units[#units]
  return ("%d%s"):format(value, unit.suffix), unit.highlight
end

--- Returns `text` right-aligned in a cell `width` wide. neo-tree places
--- right-aligned cells end to end without measuring them, so every cell in a
--- column has to be the same width.
---@param text string
---@param width integer
---@param highlight string|nil
---@return neotree.Render.Node
local function right_aligned_cell(text, width, highlight)
  return { text = " " .. string.rep(" ", width - #text) .. text, highlight = highlight }
end

---@param node NuiTree.Node
---@return neotree.Render.Node
M.rows = function(_, node, _)
  local rows = node.extra.record.rows
  if not rows then
    return right_aligned_cell("", ROWS_WIDTH)
  end
  local amount, highlight = format_scaled(rows, ROW_UNITS)
  return right_aligned_cell(("~%s %s"):format(amount, rows == 1 and "row" or "rows"), ROWS_WIDTH, highlight)
end

---@param node NuiTree.Node
---@return neotree.Render.Node
M.size = function(_, node, _)
  local record = node.extra.record
  if not record.size then
    return right_aligned_cell("", SIZE_WIDTH)
  end
  local amount, highlight = format_scaled(record.size, BYTE_UNITS)
  return right_aligned_cell((record.size_estimated and "~" or "") .. amount, SIZE_WIDTH, highlight)
end

return M
