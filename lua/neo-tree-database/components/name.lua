--- Defines the name component, which draws each node's name.

local neo_highlights = require("neo-tree.ui.highlights")

local M = {}

-- neo-tree fills `config.highlight` from `default_component_configs` for every
-- component, so it is never nil, and this table is read before it.
local NAME_HIGHLIGHT = {
  root = neo_highlights.ROOT_NAME,
  connection = neo_highlights.DIRECTORY_NAME,
  catalog = neo_highlights.DIRECTORY_NAME,
  schema = neo_highlights.DIRECTORY_NAME,
  folder = neo_highlights.DIRECTORY_NAME,
  grant_catalog = neo_highlights.DIRECTORY_NAME,
  loading = neo_highlights.DIM_TEXT,
  message = neo_highlights.MESSAGE,
}

---@param config table
---@param node NuiTree.Node
---@return neotree.Render.Node
M.name = function(config, node, _)
  return {
    text = node.name,
    highlight = NAME_HIGHLIGHT[node.type] or config.highlight or neo_highlights.FILE_NAME,
  }
end

return M
