--[[
What each line of the tree shows.

`icon` says what kind of thing a node is, and `detail` says the one fact about
it worth reading without opening it: how many relations a schema holds, what
type a column or an argument is, what an index covers, what a function returns.
`rows` and `size` are right-aligned columns holding a relation's row estimate
and an object's size on disk.
`privilege` is one column of a grant row's privileges.

The common components are merged in below, so `indent`, `container` and the
rest stay available to a renderer.
]]

local common = require("neo-tree.sources.common.components")
local groups = require("neo-tree-database.highlights")
local highlights = require("neo-tree.ui.highlights")
local privileges = require("neo-tree-database.privileges")
local routines = require("neo-tree-database.routines")
local url = require("neo-tree-database.url")

local M = {}

--- Nerd font glyphs, written as escapes because they sit in the private use
--- area and a tool that drops what it cannot display would leave them empty.
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

--- The groups a node type is coloured with when this source has an opinion.
---
--- Neo-tree merges `default_component_configs.icon.highlight` and `.name`
--- into every component's config, so `config.highlight` is never nil and
--- reading it first would make every line the same two colours. It is read
--- only where this source has nothing to say.
local ICON_HIGHLIGHT = {
  root = highlights.ROOT_NAME,
  connection = highlights.DIRECTORY_ICON,
  catalog = highlights.DIRECTORY_ICON,
  schema = highlights.DIRECTORY_ICON,
  folder = highlights.DIRECTORY_ICON,
  grant_catalog = highlights.DIRECTORY_ICON,
  loading = highlights.DIM_TEXT,
  message = highlights.MESSAGE,
}

local NAME_HIGHLIGHT = {
  root = highlights.ROOT_NAME,
  connection = highlights.DIRECTORY_NAME,
  catalog = highlights.DIRECTORY_NAME,
  schema = highlights.DIRECTORY_NAME,
  folder = highlights.DIRECTORY_NAME,
  grant_catalog = highlights.DIRECTORY_NAME,
  loading = highlights.DIM_TEXT,
  message = highlights.MESSAGE,
}

---@param config table
---@param node NuiTree.Node
---@return neotree.Render.Node
M.icon = function(config, node, _)
  local icons = config.icons or {}

  local text
  if node.type == "folder" then
    -- A folder here is a heading rather than a database object, so it takes
    -- whatever folder icon the rest of neo-tree was configured with.
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
    highlight = ICON_HIGHLIGHT[node.type] or config.highlight or highlights.FILE_ICON,
  }
end

---@param config table
---@param node NuiTree.Node
---@return neotree.Render.Node
M.name = function(config, node, _)
  return {
    text = node.name,
    highlight = NAME_HIGHLIGHT[node.type] or config.highlight or highlights.FILE_NAME,
  }
end

---@param count integer
---@param noun string
---@return string
local function counted(count, noun)
  return count .. " " .. noun .. (count == 1 and "" or "s")
end

---@type table<string, fun(node: NuiTree.Node): string|nil>
local DETAIL = {}

DETAIL.connection = function(node)
  return url.scheme(node.extra.url)
end

DETAIL.schema = function(node)
  local schema = node.extra.record
  local relations = #(schema.relations or {})
  if relations > 0 then
    return counted(relations, "relation")
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
  return counted(#node.extra.record, "overload")
end

--- An overload is told apart from its siblings by how many arguments it takes.
DETAIL.routine = function(node)
  if not node.extra.overload then
    return nil
  end
  return counted(#routines.inputs(node.extra.record), "arg")
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
  local describe = DETAIL[node.type]
  if not describe or not node.extra then
    return {}
  end

  local text = describe(node)
  if not text or text == "" then
    return {}
  end

  return {
    text = " " .. text,
    highlight = config.highlight or highlights.DIM_TEXT,
  }
end

---@class dbtree.Unit
---@field base number
---@field suffix string
---@field highlight string

---@type dbtree.Unit[]
local ROW_UNITS = {
  { base = 1e12, suffix = "T", highlight = groups.ROWS_B },
  { base = 1e9, suffix = "B", highlight = groups.ROWS_B },
  { base = 1e6, suffix = "M", highlight = groups.ROWS_M },
  { base = 1e3, suffix = "K", highlight = groups.ROWS_K },
  { base = 1, suffix = "", highlight = groups.ROWS_K },
}

---@type dbtree.Unit[]
local BYTE_UNITS = {
  { base = 2 ^ 40, suffix = " TB", highlight = groups.SIZE_GB },
  { base = 2 ^ 30, suffix = " GB", highlight = groups.SIZE_GB },
  { base = 2 ^ 20, suffix = " MB", highlight = groups.SIZE_MB },
  { base = 2 ^ 10, suffix = " KB", highlight = groups.SIZE_KB },
  { base = 1, suffix = " B", highlight = groups.SIZE_KB },
}

--- The widest a rows cell can be, such as `~999K rows`.
local ROWS_WIDTH = 10
--- The widest a size cell can be, such as `~973 KB`.
local SIZE_WIDTH = 7

--- Returns `value` in the largest unit it rounds to at least 1 of, with one
--- decimal below 10, and the unit's highlight. The last unit is the base,
--- written as a whole number.
---@param value number
---@param units dbtree.Unit[]
---@return string text
---@return string highlight
local function scaled(value, units)
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

--- Returns a right-aligned cell `width` wide holding `text`. neo-tree places
--- right-aligned cells end to end without measuring them, so a cell of any
--- other width would move the ones to its left out of line.
---@param text string
---@param width integer
---@param highlight string|nil
---@return neotree.Render.Node
local function stat(text, width, highlight)
  return { text = " " .. string.rep(" ", width - #text) .. text, highlight = highlight }
end

--- The database's own row estimate, which is never exact, as the `~` says.
--- A node without one gets a blank cell.
---@param node NuiTree.Node
---@return neotree.Render.Node
M.rows = function(_, node, _)
  local rows = node.extra.record.rows
  if not rows then
    return stat("", ROWS_WIDTH)
  end
  local amount, highlight = scaled(rows, ROW_UNITS)
  return stat(("~%s %s"):format(amount, rows == 1 and "row" or "rows"), ROWS_WIDTH, highlight)
end

--- An estimated size is marked with a `~`, as a row estimate is.
---@param node NuiTree.Node
---@return neotree.Render.Node
M.size = function(_, node, _)
  local record = node.extra.record
  if not record.size then
    return stat("", SIZE_WIDTH)
  end
  local amount, highlight = scaled(record.size, BYTE_UNITS)
  return stat((record.size_estimated and "~" or "") .. amount, SIZE_WIDTH, highlight)
end

M.privilege = privileges.cell

return vim.tbl_deep_extend("force", common, M)
