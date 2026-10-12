--- Builds what a database node holds: its schemas, or the objects of a database
--- that has no schemas, and its Grants folder.

local base = require("neo-tree-database.nodes.base")
local grant = require("neo-tree-database.nodes.grant")
local schema = require("neo-tree-database.nodes.schema")

local M = {}

---@param node dbtree.Item|NuiTree.Node
---@param catalog dbtree.Catalog
---@return dbtree.Item[]
local function schemas(node, catalog)
  local parent = node.extra
  local result = {}
  for _, record in ipairs(catalog.schemas) do
    local id = node.id .. "/" .. base.segment(record.name)
    table.insert(
      result,
      base.container(id, record.name, "schema", base.inherit(parent, {
        kind = "schema",
        schema = record.name,
        record = record,
      }))
    )
  end
  return result
end

---@param node dbtree.Item|NuiTree.Node
---@param catalog dbtree.Catalog
---@return dbtree.Item[]
function M.children(node, catalog)
  local name = node.extra.catalog
  local result = catalog.schemas and schemas(node, catalog) or schema.object_folders(node, catalog, name)
  return vim.list_extend(result, grant.folder(node, grant.rows(grant.database_target(name), catalog.grants)))
end

return M
