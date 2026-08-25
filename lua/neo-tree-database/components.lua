--[[
What each line of the tree shows.

Two components carry this source. `icon` says what kind of thing a node is, and
`detail` says the one fact about it worth reading without opening it: how many
tables a schema holds, roughly how many rows a table holds, what type a column
is, what an index covers.

The common components are merged in below, so `indent`, `container` and the
rest stay available to a renderer.
]]

local common = require("neo-tree.sources.common.components")
local highlights = require("neo-tree.ui.highlights")
local url = require("neo-tree-database.url")

local M = {}

local ICONS = {
  root = "",
  connection = "󰆼",
  catalog = "",
  schema = "",
  folder_closed = "",
  folder_open = "",
  table = "",
  view = "",
  materialized_view = "",
  column = "",
  index = "",
  constraint = "",
  loading = "",
  message = "",
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
  loading = highlights.DIM_TEXT,
  message = highlights.MESSAGE,
}

local NAME_HIGHLIGHT = {
  root = highlights.ROOT_NAME,
  connection = highlights.DIRECTORY_NAME,
  catalog = highlights.DIRECTORY_NAME,
  schema = highlights.DIRECTORY_NAME,
  folder = highlights.DIRECTORY_NAME,
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

--- A row estimate short enough to sit beside a name. The estimate is the
--- database's own and is never exact, which the leading tilde says.
---@param rows integer
---@return string
local function approximate(rows)
  local units = { { 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } }
  for _, unit in ipairs(units) do
    if rows >= unit[1] then
      return ("~%.1f%s"):format(rows / unit[1], unit[2])
    end
  end
  return ("~%d"):format(rows)
end

---@type table<string, fun(node: NuiTree.Node): string|nil>
local DETAIL = {}

DETAIL.connection = function(node)
  return url.scheme(node.extra.url)
end

DETAIL.schema = function(node)
  local relations = node.extra.record.relations or {}
  if #relations == 0 then
    return "empty"
  end
  return #relations == 1 and "1 relation" or (#relations .. " relations")
end

local function relation_detail(node)
  local rows = node.extra.record.rows
  if type(rows) ~= "number" then
    return nil
  end
  return approximate(rows)
end

DETAIL.table = relation_detail
DETAIL.view = relation_detail
DETAIL.materialized_view = relation_detail

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

  return { text = " " .. text, highlight = config.highlight or highlights.DIM_TEXT }
end

return vim.tbl_deep_extend("force", common, M)
