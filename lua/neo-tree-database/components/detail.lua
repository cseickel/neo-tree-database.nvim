--- Defines the detail component, which draws the dimmed text after a node's name,
--- such as a column's type.

local neo_highlights = require("neo-tree.ui.highlights")
local routine = require("neo-tree-database.nodes.function")
local url = require("neo-tree-database.shared.url")

local M = {}

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
  return format_count(#routine.inputs(node.extra.record), "arg")
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

return M
