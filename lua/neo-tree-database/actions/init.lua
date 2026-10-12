--- Collects the actions this source's keys run, on top of neo-tree's shared ones.

local cc = require("neo-tree.sources.common.commands")
local describe = require("neo-tree-database.actions.describe")
local open = require("neo-tree-database.actions.open")
local scratch = require("neo-tree-database.actions.scratch")
local statement = require("neo-tree-database.actions.statement")
local yank_name = require("neo-tree-database.actions.yank_name")

local M = {
  open = open.open,
  -- neo-tree's shared toggle_node expands a node without loading its children.
  toggle_node = open.open,
  refresh = open.refresh,
  refresh_node = open.refresh_node,
  yank_name = yank_name.yank_name,
  describe = describe.describe,
  object_info = statement.object_info,
  object_drop = statement.object_drop,
  object_change = statement.object_change,
  open_scratch = scratch.open_scratch,
}

for _, name in ipairs({
  "cancel",
  "close_all_nodes",
  "close_all_subnodes",
  "close_node",
  "close_window",
  "next_source",
  "prev_source",
  "show_help",
  "toggle_auto_expand_width",
}) do
  M[name] = cc[name]
end

return M
