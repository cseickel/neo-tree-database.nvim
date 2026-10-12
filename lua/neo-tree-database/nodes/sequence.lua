--- Builds the sequence nodes and the Grants folder under each sequence.

local base = require("neo-tree-database.nodes.base")
local grant = require("neo-tree-database.nodes.grant")

local M = {}

--- Returns the sequences in a Sequences folder. A sequence with no grants is a
--- leaf, because its Grants folder is its only child.
---@param node dbtree.Item|NuiTree.Node
---@return dbtree.Item[]
function M.sequences(node)
  local result = {}
  for _, sequence in ipairs(node.extra.record) do
    local id = node.id .. "/" .. base.segment(sequence.name)
    local extra = base.inherit(node.extra, {
      kind = "sequence",
      record = sequence,
      target = grant.sequence_target(node.extra.schema, sequence),
    })
    local make_item = #(sequence.grants or {}) > 0 and base.container or base.leaf
    table.insert(result, make_item(id, sequence.name, "sequence", extra))
  end
  return result
end

---@param node dbtree.Item|NuiTree.Node
---@return dbtree.Item[]
function M.grants(node)
  return grant.folder(node, grant.rows(node.extra.target, node.extra.record.grants))
end

return M
