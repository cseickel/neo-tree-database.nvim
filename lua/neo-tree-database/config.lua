--- Returns the source's default config, which sets how each node type renders and
--- what each key does.

---@class (exact) neotree.Config.Database : neotree.Config.Source
---@field connections dbtree.Connection[]|fun(): dbtree.Connection[]|nil
---@field open_scratch fun(spec: dbtree.Scratch)|nil

---@param indent table
---@param after_name table[]
---@return table[]
local function renderer(indent, after_name)
  local content = { { "name", zindex = 10 } }
  for _, component in ipairs(after_name) do
    table.insert(content, vim.tbl_extend("force", { zindex = 10 }, component))
  end
  return { indent, { "icon" }, { "container", content = content } }
end

local function branch(...)
  return renderer({ "indent", with_expanders = true }, { ... })
end

local function leaf(...)
  return renderer({ "indent" }, { ... })
end

local DETAIL = { "detail" }
local SIZE = { "size", align = "right", required_width = 40 }
local ROWS = { "rows", align = "right", required_width = 50 }

-- No kind of object has more than one of the privileges in a column, so each
-- cell holds one word.
local PRIVILEGE_COLUMNS = {
  { "SELECT", "CREATE", "EXECUTE" },
  { "INSERT", "USAGE", "CONNECT" },
  { "UPDATE", "TEMPORARY" },
  { "DELETE" },
  { "TRUNCATE" },
}

local function grant_renderer()
  local columns = {}
  for _, column_privileges in ipairs(PRIVILEGE_COLUMNS) do
    table.insert(columns, { "privilege", grants = column_privileges, align = "right" })
  end
  return leaf(unpack(columns))
end

-- neo-tree binds these keys in every source to commands that read a node's file
-- path.
local DISABLED_KEYS = {
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
for _, key in ipairs(DISABLED_KEYS) do
  mappings[key] = "noop"
end

return {
  connections = nil,
  open_scratch = nil,
  -- neo-tree renders a node type that has no renderer as `type: name`.
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
    grant = grant_renderer(),
    loading = { { "indent" }, { "name" } },
    message = { { "indent", with_markers = false }, { "name" } },
  },
  window = {
    mappings = mappings,
  },
}
