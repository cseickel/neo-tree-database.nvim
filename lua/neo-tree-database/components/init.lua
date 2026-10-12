--- Collects the components that draw each part of a line in the tree, on top of
--- neo-tree's shared ones.

local common = require("neo-tree.sources.common.components")

return vim.tbl_extend(
  "force",
  common,
  require("neo-tree-database.components.icon"),
  require("neo-tree-database.components.name"),
  require("neo-tree-database.components.detail"),
  require("neo-tree-database.components.size"),
  require("neo-tree-database.components.privilege")
)
