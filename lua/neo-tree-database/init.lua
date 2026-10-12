--- Defines the neo-tree source that browses databases.

local base = require("neo-tree-database.nodes.base")
local connection = require("neo-tree-database.nodes.connection")
local connections = require("neo-tree-database.databases.connections")
local expanded = require("neo-tree-database.state.expanded")

local renderer = require("neo-tree.ui.renderer")

---@class neotree.sources.Database : neotree.Source
local M = {
  name = "database",
  -- The glyph is an escape because it is in the private use area, and some
  -- tools drop characters from it.
  display_name = " \u{f01bc} Database ",
  commands = require("neo-tree-database.actions"),
  components = require("neo-tree-database.components"),
  default_config = require("neo-tree-database.config"),
}

M.config = {}

--- Rebuilds the tree from the connection list.
---@param state neotree.State
---@param path string?
---@param path_to_reveal string?
---@param callback function?
M.navigate = function(state, path, path_to_reveal, callback)
  -- neo-tree rebuilds a dirty tree on every open and focus.
  state.dirty = false
  state.path = base.ROOT

  local connection_list, err = connections.list(M.config.connections)
  local children
  if err then
    children = base.message(base.ROOT, err)
  elseif #connection_list == 0 then
    children = base.message(base.ROOT, "no connections")
  else
    children = connection.connections(connection_list)
    if state.tree then
      expanded.restore(state.tree, children)
    end
  end

  renderer.show_nodes(base.root(children), state)

  if type(callback) == "function" then
    vim.schedule(callback)
  end
end

---@param config neotree.Config.Database
---@param global_config neotree.Config.Base
M.setup = function(config, global_config)
  M.config = config
  require("neo-tree-database.state.focus").follow_cursor(M.name)
  require("neo-tree-database.shared.highlights").setup()
end

return M
