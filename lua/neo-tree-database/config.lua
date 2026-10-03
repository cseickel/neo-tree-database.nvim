--[[
The source's default config: how each node type renders, and what each key does.
]]

---@class (exact) neotree.Config.Database : neotree.Config.Source
---@field connections dbtree.Connection[]|fun(): dbtree.Connection[]|nil
---@field open_scratch fun(spec: dbtree.Scratch)|nil

--- Every node type this source emits needs its own renderer, because a type
--- with none renders as `type: name` with the type spelled out.
local function line(...)
  local components = { { "indent", with_expanders = true }, { "icon" }, { "name" } }
  for _, extra in ipairs({ ... }) do
    table.insert(components, extra)
  end
  return components
end

--- A node that never opens, so it draws no expander.
local function leaf()
  return { { "indent" }, { "icon" }, { "name" }, { "detail" } }
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
    connection = line({ "detail" }),
    catalog = line(),
    schema = line({ "detail" }),
    folder = line(),
    table = line({ "detail" }),
    view = line({ "detail" }),
    materialized_view = line({ "detail" }),
    sequence = line(),
    routine = line({ "detail" }),
    role = line({ "detail" }),
    public = line(),
    grant_catalog = line(),
    column = leaf(),
    index = leaf(),
    constraint = leaf(),
    -- The privileges are dropped when the window is too narrow for them, and
    -- `i` shows them as the GRANT.
    grant = {
      { "indent" },
      { "icon" },
      {
        "container",
        content = {
          { "name", zindex = 10 },
          { "detail", zindex = 10, required_width = 64 },
        },
      },
    },
    loading = { { "indent" }, { "name" } },
    message = { { "indent", with_markers = false }, { "name" } },
  },
  window = {
    mappings = mappings,
  },
}
