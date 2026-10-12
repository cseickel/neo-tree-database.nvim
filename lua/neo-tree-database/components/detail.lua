--- Defines the detail component, which draws the text after a node's name, such
--- as a column's type.

local highlights = require("neo-tree-database.shared.highlights")
local routine = require("neo-tree-database.nodes.function")
local url = require("neo-tree-database.shared.url")

local utils = require("neo-tree.utils")

local M = {}

---@param count integer
---@param noun string
---@return string
local function format_count(count, noun)
  return count .. " " .. noun .. (count == 1 and "" or "s")
end

---@param text string
---@return neotree.Render.Node[]
local function described(text)
  return { { text = text, highlight = highlights.DETAIL } }
end

-- Each long type name that postgres and duckdb print, with the shorter alias
-- both accept. The first pattern that matches the lowercased name applies.
local SHORT_TYPES = {
  { "^timestamp(%(%d+%)) with time zone", "timestamptz%1" },
  { "^timestamp with time zone", "timestamptz" },
  { "^timestamp(%(%d+%)) without time zone", "timestamp%1" },
  { "^timestamp without time zone", "timestamp" },
  { "^time(%(%d+%)) with time zone", "timetz%1" },
  { "^time with time zone", "timetz" },
  { "^time(%(%d+%)) without time zone", "time%1" },
  { "^time without time zone", "time" },
  { "^character varying", "varchar" },
  { "^character", "char" },
  { "^double precision", "float8" },
  { "^bit varying", "varbit" },
}

---@param type_name string
---@return string
local function short_type(type_name)
  local lowered = type_name:lower()
  for _, rule in ipairs(SHORT_TYPES) do
    local shortened, matches = lowered:gsub(rule[1], rule[2])
    if matches > 0 then
      return shortened
    end
  end
  return type_name
end

--- Returns `type_name`, shortened, in the type highlight, followed by `rest`
--- when there is any.
---@param type_name string|nil
---@param rest string|nil
---@return neotree.Render.Node[]
local function typed(type_name, rest)
  local parts = { { text = type_name and short_type(type_name) or "", highlight = highlights.TYPE } }
  if rest then
    table.insert(parts, { text = rest, highlight = highlights.DETAIL })
  end
  return parts
end

--- Returns `parts` while `node` is collapsed. A count of what a node holds says
--- nothing once its children show.
---@param node NuiTree.Node
---@param parts neotree.Render.Node[]
---@return neotree.Render.Node[]|nil
local function while_collapsed(node, parts)
  if node:is_expanded() then
    return nil
  end
  return parts
end

---@type table<string, fun(node: NuiTree.Node): neotree.Render.Node[]|nil>
local DETAIL = {}

DETAIL.connection = function(node)
  return described(url.scheme(node.extra.url))
end

DETAIL.schema = function(node)
  local schema = node.extra.record
  local relation_count = #(schema.relations or {})
  if relation_count > 0 then
    return while_collapsed(node, described(format_count(relation_count, "relation")))
  end
  if #(schema.sequences or {}) + #(schema.functions or {}) == 0 then
    return while_collapsed(node, described("empty"))
  end
  return nil
end

DETAIL.column = function(node)
  local column = node.extra.record
  return typed(column.type, column.nullable == false and " not null" or nil)
end

DETAIL.index = function(node)
  return node.extra.record.unique and described("unique") or nil
end

DETAIL.constraint = function(node)
  return described(node.extra.record.type)
end

DETAIL.overloaded_routine = function(node)
  return while_collapsed(node, described(format_count(#node.extra.record, "overload")))
end

DETAIL.routine = function(node)
  if not node.extra.overload then
    return nil
  end
  return while_collapsed(node, described(format_count(#routine.inputs(node.extra.record), "arg")))
end

DETAIL["return"] = function(node)
  local text = node.extra.record.text
  local set_of, type_name = text:match("^(SETOF )(.+)$")
  if set_of then
    return typed(set_of .. short_type(type_name))
  end
  return typed(text)
end

DETAIL.field = function(node)
  local field = node.extra.record
  return typed(field.type, field.default and (" DEFAULT " .. field.default) or nil)
end

DETAIL.role = function(node)
  return described(table.concat(node.extra.record.attributes, ", "):lower())
end

local DEFAULT_WIDTH = 21
-- Leaves room for a character and the ellipsis.
local MIN_WIDTH = 4
local ELLIPSIS = "…"

--- Returns `parts` in a cell `width` columns wide after a space, padded when
--- shorter and cut with an ellipsis when longer. neo-tree places right-aligned
--- cells end to end without measuring them, so every cell in a column has to
--- be the same width.
---@param parts neotree.Render.Node[]
---@param width integer
---@return neotree.Render.Node[]
local function fitted(parts, width)
  local full_width = 0
  for _, part in ipairs(parts) do
    full_width = full_width + vim.api.nvim_strwidth(part.text)
  end
  local is_cut = full_width > width
  -- The ellipsis takes two columns when `ambiwidth` is double.
  local ellipsis_width = vim.api.nvim_strwidth(ELLIPSIS)
  local room = is_cut and width - ellipsis_width or width

  local cell, used = {}, 0
  for _, part in ipairs(parts) do
    local text, text_width = utils.truncate_by_cell(part.text, room - used)
    if text_width > 0 then
      table.insert(cell, { text = text, highlight = part.highlight })
      used = used + text_width
    end
  end
  if is_cut and #cell > 0 then
    -- neo-tree pads a part that does not start with a space, so the ellipsis
    -- joins the text before it.
    cell[#cell].text = cell[#cell].text .. ELLIPSIS
    used = used + ellipsis_width
  end

  table.insert(cell, 1, { text = " " })
  if used < width then
    table.insert(cell, { text = string.rep(" ", width - used) })
  end
  return cell
end

--- Returns `parts` starting 2 cells after the widest name among `node`'s
--- siblings, as the types line up in a CREATE TABLE.
---@param parts neotree.Render.Node[]
---@param node NuiTree.Node
---@return neotree.Render.Node[]
local function after_name(parts, node)
  if #parts == 0 then
    return parts
  end
  local name_width = node.extra.name_width or vim.api.nvim_strwidth(node.name)
  local gap = name_width - vim.api.nvim_strwidth(node.name) + 2
  parts[1].text = string.rep(" ", gap) .. parts[1].text
  return parts
end

--- Draws the detail in a fixed-width cell when the renderer aligns it right,
--- and after the name otherwise.
---@param config { width: integer|nil, align: string|nil }
---@param node NuiTree.Node
---@return neotree.Render.Node[]
M.detail = function(config, node, _)
  local detail_parts = node.extra and DETAIL[node.type]
  local parts = detail_parts and detail_parts(node) or {}
  if config.align ~= "right" then
    return after_name(parts, node)
  end
  return fitted(parts, math.max(config.width or DEFAULT_WIDTH, MIN_WIDTH))
end

return M
