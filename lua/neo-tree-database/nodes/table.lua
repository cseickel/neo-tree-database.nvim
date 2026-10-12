--- Builds the table and view nodes, their Columns, Indexes, Constraints and
--- Grants folders, and each index's key parts.

local base = require("neo-tree-database.nodes.base")
local grant = require("neo-tree-database.nodes.grant")

local M = {}

--- Returns the tables or views in a Tables, Views or Materialized Views folder.
---@param node dbtree.Item|NuiTree.Node
---@return dbtree.Item[]
function M.relations(node)
  local parent = node.extra
  local result = {}
  for _, relation in ipairs(parent.record) do
    local id = node.id .. "/" .. base.segment(relation.name)
    table.insert(
      result,
      base.container(id, relation.name, relation.kind, base.inherit(parent, {
        kind = relation.kind,
        relation = relation.name,
        record = relation,
      }))
    )
  end
  return result
end

local RELATION_PARTS = {
  { folder = "columns", label = "Columns", leaf = "column" },
  { folder = "indexes", label = "Indexes", leaf = "index" },
  { folder = "constraints", label = "Constraints", leaf = "constraint" },
}

---@param node dbtree.Item|NuiTree.Node
---@return dbtree.Item[]
function M.folders(node)
  local parent = node.extra
  local result = {}
  for _, part in ipairs(RELATION_PARTS) do
    local records = parent.record[part.folder] or {}
    if #records > 0 then
      table.insert(
        result,
        base.container(node.id .. "/@" .. part.folder, part.label, "folder", base.inherit(parent, {
          kind = "folder",
          folder = part.folder,
          leaf = part.leaf,
          record = records,
        }))
      )
    end
  end
  return vim.list_extend(result, grant.folder(node, grant.relation_rows(parent.schema, parent.record)))
end

--- Returns the columns, indexes or constraints in one of a relation's folders.
--- An index with key parts expands to them.
---@param node dbtree.Item|NuiTree.Node
---@return dbtree.Item[]
function M.parts(node)
  local parent = node.extra
  local result = {}
  for _, record in ipairs(parent.record) do
    local has_parts = parent.leaf == "index" and #(record.columns or {}) > 0
    local make_item = has_parts and base.container or base.leaf
    table.insert(
      result,
      make_item(node.id .. "/" .. base.segment(record.name), record.name, parent.leaf, base.inherit(parent, {
        kind = parent.leaf,
        record = record,
      }))
    )
  end
  if parent.leaf == "column" then
    base.align_names(result)
  end
  return result
end

--- Returns the key parts of an index, in key order, each named as the database
--- writes it, such as `lower(email)`.
---@param node dbtree.Item|NuiTree.Node
---@return dbtree.Item[]
function M.index_parts(node)
  local parent = node.extra
  local result = {}
  for position, part in ipairs(parent.record.columns) do
    table.insert(
      result,
      base.leaf(node.id .. "/" .. position, part, "index_column", base.inherit(parent, {
        kind = "index_column",
        record = parent.record,
      }))
    )
  end
  return result
end

return M
