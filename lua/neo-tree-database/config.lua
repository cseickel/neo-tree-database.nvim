--[[
The source's default config: how each node type renders, and what each key does.
]]

---@class (exact) neotree.Config.Database : neotree.Config.Source
---@field connections dbtree.Connection[]|fun(): dbtree.Connection[]|nil
---@field open_scratch fun(spec: dbtree.Scratch)|nil

--- Every node type this source emits needs its own renderer, because a type
--- with none renders as `type: name` with the type spelled out.
---@param indent table
---@param after table[] What follows the name.
---@return table[]
local function line(indent, after)
  local content = { { "name", zindex = 10 } }
  for _, component in ipairs(after) do
    table.insert(content, vim.tbl_extend("force", { zindex = 10 }, component))
  end
  return { indent, { "icon" }, { "container", content = content } }
end

local function branch(...)
  return line({ "indent", with_expanders = true }, { ... })
end

--- A node that never opens, so it draws no expander.
local function leaf(...)
  return line({ "indent" }, { ... })
end

local DETAIL = { "detail" }
--- neo-tree drops a component from every line once the window is narrower
--- than its `required_width`. A node with a size and no rows still takes a
--- blank rows cell, so every size lines up in one column.
local SIZE = { "size", align = "right", required_width = 40 }
local ROWS = { "rows", align = "right", required_width = 50 }

--- The privilege columns a grant row shows. No kind of object can have two of
--- the privileges one column lists, so each cell holds a single word.
local PRIVILEGE_COLUMNS = {
  { "SELECT", "CREATE", "EXECUTE" },
  { "INSERT", "USAGE", "CONNECT" },
  { "UPDATE", "TEMPORARY" },
  { "DELETE" },
  { "TRUNCATE" },
}

local function grant_line()
  local columns = {}
  for _, grants in ipairs(PRIVILEGE_COLUMNS) do
    table.insert(columns, { "privilege", grants = grants, align = "right" })
  end
  return leaf(unpack(columns))
end

--- Keys neo-tree binds for every source that mean nothing here. A database node
--- has no path, so the commands behind these keys either do nothing or reach
--- for a field that is not there. They are turned off rather than left to
--- resolve to a warning and a key that silently does nothing.
local DISABLED = {
  "a",
  "A",
  "T",
  "u",
  "U",
  "r",
  "x",
  "p",
  "m",
  "S",
  "t",
  "w",
  "P",
  "<C-r>",
  "<C-f>",
  "<C-b>",
  "<C-s>",
  "<Tab>",
  "<C-S-i>",
  "<C-;>",
}

local mappings = {
  ["<cr>"] = "open",
  ["<space>"] = "toggle_node",
  ["l"] = "open",
  ["R"] = "refresh_node",
  ["y"] = "yank_name",
  ["K"] = "describe",
  ["i"] = "object_info",
  ["d"] = "object_drop",
  ["c"] = "object_change",
  ["s"] = "open_scratch",
}
for _, key in ipairs(DISABLED) do
  mappings[key] = "noop"
end

return {
  connections = nil,
  open_scratch = nil,
  renderers = {
    root = { { "indent" }, { "icon" }, { "name" } },
    connection = branch(DETAIL),
    catalog = branch(SIZE, ROWS),
    schema = branch(DETAIL, SIZE, ROWS),
    folder = branch(),
    table = branch(SIZE, ROWS),
    view = branch(),
    materialized_view = branch(SIZE, ROWS),
    sequence = branch(SIZE, ROWS),
    overloaded_routine = branch(DETAIL),
    routine = branch(DETAIL),
    ["return"] = branch(DETAIL),
    field = leaf(DETAIL),
    role = branch(DETAIL),
    public = branch(),
    grant_catalog = branch(),
    column = leaf(DETAIL),
    index = leaf(DETAIL, SIZE, ROWS),
    constraint = leaf(DETAIL),
    grant = grant_line(),
    loading = { { "indent" }, { "name" } },
    message = { { "indent", with_markers = false }, { "name" } },
  },
  window = {
    mappings = mappings,
  },
}
