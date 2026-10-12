--- Defines the icon component, which draws the glyph before each node's name.

local fetching = require("neo-tree-database.state.fetching")

local neo_highlights = require("neo-tree.ui.highlights")

local M = {}

local SPINNER = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

---@return string
local function spinner_frame()
  local frame = math.floor(vim.uv.hrtime() / 1e6 / fetching.FRAME_MS)
  return SPINNER[frame % #SPINNER + 1]
end

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
  index_column = "\u{eb5f}",
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
-- component, so it is never nil, and this table is read before it.
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

---@param config table
---@param node NuiTree.Node
---@return neotree.Render.Node
M.icon = function(config, node, _)
  local icons = config.icons or {}

  local text
  if fetching.has(node:get_id()) then
    text = spinner_frame()
  elseif node.type == "folder" then
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

return M
