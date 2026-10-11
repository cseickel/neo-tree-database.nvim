--- Defines the components that render each part of a line in the tree.

local common = require("neo-tree.sources.common.components")
local db_highlights = require("neo-tree-database.highlights")
local neo_highlights = require("neo-tree.ui.highlights")
local privileges = require("neo-tree-database.privileges")
local routines = require("neo-tree-database.routines")
local url = require("neo-tree-database.url")

local M = {}

-- These nerd font glyphs are written as escapes because they are in the private
-- use area, and some tools drop characters from it.
local ICONS = {
  root = "\u{f1c0}",
  connection = "\u{f01bc}",
  catalog = "\u{e706}",
  schema = "\u{ea8b}",
  folder_closed = "\u{e5ff}",
  folder_open = "\u{e5fe}",
  table = "\u{f0ce}",
  view = "\u{f06e}",
  materialized_view = "\u{ea70}",
  column = "\u{eb5f}",
  index = "\u{f160}",
  constraint = "\u{f023}",
  sequence = "\u{f162}",
  routine = "\u{f0295}",
  overloaded_routine = "\u{f0295}",
  ["return"] = "\u{f061}",
  field = "\u{eb5f}",
  role = "\u{f007}",
  public = "\u{f0c0}",
  grant = "\u{f084}",
  grant_catalog = "\u{e706}",
  loading = "\u{f110}",
  message = "\u{f05a}",
}

-- neo-tree fills `config.highlight` from `default_component_configs` for every
-- component, so it is never nil, and these tables are read before it.
local ICON_HIGHLIGHT = {
  root = neo_highlights.ROOT_NAME,
  connection = neo_highlights.DIRECTORY_ICON,
  catalog = neo_highlights.DIRECTORY_ICON,
  schema = neo_highlights.DIRECTORY_ICON,
  folder = neo_highlights.DIRECTORY_ICON,
  grant_catalog = neo_highlights.DIRECTORY_ICON,
  loading = neo_highlights.DIM_TEXT,
  message = neo_highlights.MESSAGE,
}

local NAME_HIGHLIGHT = {
  root = neo_highlights.ROOT_NAME,
  connection = neo_highlights.DIRECTORY_NAME,
  catalog = neo_highlights.DIRECTORY_NAME,
  schema = neo_highlights.DIRECTORY_NAME,
  folder = neo_highlights.DIRECTORY_NAME,
  grant_catalog = neo_highlights.DIRECTORY_NAME,
  loading = neo_highlights.DIM_TEXT,
  message = neo_highlights.MESSAGE,
}

---@param config table
---@param node NuiTree.Node
---@return neotree.Render.Node
M.icon = function(config, node, _)
  local icons = config.icons or {}

  local text
  if node.type == "folder" then
    if node:is_expanded() then
      text = icons.folder_open or config.folder_open or ICONS.folder_open
    else
      text = icons.folder_closed or config.folder_closed or ICONS.folder_closed
    end
  else
    text = icons[node.type] or ICONS[node.type] or config.default or " "
  end

  return {
    text = text .. " ",
    highlight = ICON_HIGHLIGHT[node.type] or config.highlight or neo_highlights.FILE_ICON,
  }
end

---@param config table
---@param node NuiTree.Node
---@return neotree.Render.Node
M.name = function(config, node, _)
  return {
    text = node.name,
    highlight = NAME_HIGHLIGHT[node.type] or config.highlight or neo_highlights.FILE_NAME,
  }
end

---@param count integer
---@param noun string
---@return string
local function format_count(count, noun)
  return count .. " " .. noun .. (count == 1 and "" or "s")
end

---@type table<string, fun(node: NuiTree.Node): string|nil>
local DETAIL = {}

DETAIL.connection = function(node)
  return url.scheme(node.extra.url)
end

DETAIL.schema = function(node)
  local schema = node.extra.record
  local relation_count = #(schema.relations or {})
  if relation_count > 0 then
    return format_count(relation_count, "relation")
  end
  if #(schema.sequences or {}) + #(schema.functions or {}) == 0 then
    return "empty"
  end
  return nil
end

DETAIL.column = function(node)
  local column = node.extra.record
  local text = column.type or ""
  if column.nullable == false then
    text = text .. " not null"
  end
  return text
end

DETAIL.index = function(node)
  local index = node.extra.record
  local columns = index.columns or {}
  local text = #columns > 0 and ("(" .. table.concat(columns, ", ") .. ")") or ""
  if index.unique then
    text = vim.trim("unique " .. text)
  end
  return text
end

DETAIL.constraint = function(node)
  return node.extra.record.type
end

DETAIL.overloaded_routine = function(node)
  return format_count(#node.extra.record, "overload")
end

DETAIL.routine = function(node)
  if not node.extra.overload then
    return nil
  end
  return format_count(#routines.inputs(node.extra.record), "arg")
end

DETAIL["return"] = function(node)
  return node.extra.record.text
end

DETAIL.field = function(node)
  local field = node.extra.record
  local text = field.type or ""
  if field.default then
    text = text .. " DEFAULT " .. field.default
  end
  return text
end

DETAIL.role = function(node)
  return table.concat(node.extra.record.attributes, ", "):lower()
end

---@param config table
---@param node NuiTree.Node
---@return neotree.Render.Node
M.detail = function(config, node, _)
  local detail_text = DETAIL[node.type]
  if not detail_text or not node.extra then
    return {}
  end

  local text = detail_text(node)
  if not text or text == "" then
    return {}
  end

  return {
    text = " " .. text,
    highlight = config.highlight or neo_highlights.DIM_TEXT,
  }
end

---@class dbtree.Unit
---@field base number
---@field suffix string
---@field highlight string

---@type dbtree.Unit[]
local ROW_UNITS = {
  { base = 1e12, suffix = "T", highlight = db_highlights.ROWS_B },
  { base = 1e9, suffix = "B", highlight = db_highlights.ROWS_B },
  { base = 1e6, suffix = "M", highlight = db_highlights.ROWS_M },
  { base = 1e3, suffix = "K", highlight = db_highlights.ROWS_K },
  { base = 1, suffix = "", highlight = db_highlights.ROWS_K },
}

---@type dbtree.Unit[]
local BYTE_UNITS = {
  { base = 2 ^ 40, suffix = " TB", highlight = db_highlights.SIZE_GB },
  { base = 2 ^ 30, suffix = " GB", highlight = db_highlights.SIZE_GB },
  { base = 2 ^ 20, suffix = " MB", highlight = db_highlights.SIZE_MB },
  { base = 2 ^ 10, suffix = " KB", highlight = db_highlights.SIZE_KB },
  { base = 1, suffix = " B", highlight = db_highlights.SIZE_KB },
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

M.privilege = privileges.cell

return vim.tbl_deep_extend("force", common, M)
