--- Builds the schema nodes and the Grants folder under a database.

local base = require("neo-tree-database.nodes.base")
local grant = require("neo-tree-database.nodes.grant")

local M = {}

---@param node dbtree.Item|NuiTree.Node
---@param document dbtree.Catalog
---@return dbtree.Item[]
function M.schemas(node, document)
  local parent = node.extra
  local result = {}
  for _, schema in ipairs(document.schemas or {}) do
    local id = node.id .. "/" .. base.segment(schema.name)
    table.insert(
      result,
      base.container(id, schema.name, "schema", base.inherit(parent, {
        kind = "schema",
        schema = schema.name,
        record = schema,
      }))
    )
  end
  return vim.list_extend(result, grant.folder(node, grant.rows(grant.database_target(parent.catalog), document.grants)))
end

return M
