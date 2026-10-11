--- Builds the tree items for what a catalog holds.

local grants = require("neo-tree-database.grants")
local items = require("neo-tree-database.items")

local M = {}

---@class dbtree.Column
---@field name string
---@field type string
---@field nullable boolean
---@field default string|nil
---@field position integer
---@field identity string|nil postgres `attidentity`, `a` or `d`.
---@field generated string|nil postgres `attgenerated`, `s` for stored.
---@field grants dbtree.Grant[]|nil

---@class dbtree.Index
---@field name string
---@field unique boolean
---@field size integer|nil Bytes on disk.
---@field size_estimated boolean|nil
---@field columns string[]
---@field definition string|nil
---@field owned_by_constraint boolean|nil

---@class dbtree.Constraint
---@field name string
---@field type string
---@field definition string

---@class dbtree.Relation
---@field name string
---@field kind "table"|"view"|"materialized_view"
---@field rows integer|nil
---@field size integer|nil Bytes on disk, including its indexes.
---@field size_estimated boolean|nil
---@field definition string|nil
---@field columns dbtree.Column[]
---@field indexes dbtree.Index[]
---@field constraints dbtree.Constraint[]
---@field grants dbtree.Grant[]|nil

---@class dbtree.Sequence
---@field name string
---@field size integer|nil Bytes on disk.
---@field size_estimated boolean|nil
---@field definition string
---@field grants dbtree.Grant[]|nil

---@class dbtree.Schema
---@field name string
---@field size integer|nil Bytes on disk of everything it holds.
---@field size_estimated boolean|nil
---@field relations dbtree.Relation[]
---@field sequences dbtree.Sequence[]
---@field functions dbtree.Routine[]
---@field grants dbtree.Grant[]|nil

---@class dbtree.Catalog
---@field schemas dbtree.Schema[]
---@field grants dbtree.Grant[]|nil

---@param node dbtree.Item|NuiTree.Node
---@param catalogs dbtree.ListedCatalog[]
---@param catalog_url fun(connection: string, catalog: string): string
---@return dbtree.Item[]
function M.catalogs(node, catalogs, catalog_url)
  local parent = node.extra
  local result = {}
  for _, catalog in ipairs(catalogs) do
    local name = catalog.name
    local url = catalog_url(parent.url, name)
    table.insert(
      result,
      items.container(items.catalog_id(parent.connection, name), name, "catalog", {
        kind = "catalog",
        connection = parent.connection,
        catalog = name,
        url = url,
        record = catalog,
        documents = { items.catalog_document(parent.connection, name, url) },
      })
    )
  end
  return result
end

---@param node dbtree.Item|NuiTree.Node
---@param document dbtree.Catalog
---@return dbtree.Item[]
function M.schemas(node, document)
  local parent = node.extra
  local result = {}
  for _, schema in ipairs(document.schemas or {}) do
    local id = node.id .. "/" .. items.segment(schema.name)
    table.insert(
      result,
      items.container(id, schema.name, "schema", items.inherit(parent, {
        kind = "schema",
        schema = schema.name,
        record = schema,
      }))
    )
  end
  return vim.list_extend(result, grants.folder(node, grants.rows(grants.database_target(parent.catalog), document.grants)))
end

local SCHEMA_FOLDERS = {
  { folder = "tables", label = "Tables", field = "relations", kind = "table" },
  { folder = "views", label = "Views", field = "relations", kind = "view" },
  { folder = "materialized_views", label = "Materialized Views", field = "relations", kind = "materialized_view" },
  { folder = "sequences", label = "Sequences", field = "sequences" },
  { folder = "functions", label = "Functions", field = "functions", kind = "function" },
  { folder = "procedures", label = "Procedures", field = "functions", kind = "procedure" },
  { folder = "aggregates", label = "Aggregates", field = "functions", kind = "aggregate" },
  { folder = "macros", label = "Macros", field = "functions", kind = "macro" },
  { folder = "table_macros", label = "Table Macros", field = "functions", kind = "table_macro" },
}

---@param records table[]
---@param kind string|nil
---@return table[]
local function of_kind(records, kind)
  if not kind then
    return records
  end
  return vim.tbl_filter(function(record)
    return record.kind == kind
  end, records)
end

---@param node dbtree.Item|NuiTree.Node
---@return dbtree.Item[]
function M.schema_folders(node)
  local parent = node.extra
  local schema = parent.record

  local result = {}
  for _, folder_spec in ipairs(SCHEMA_FOLDERS) do
    local records = of_kind(schema[folder_spec.field] or {}, folder_spec.kind)
    if #records > 0 then
      table.insert(
        result,
        items.container(node.id .. "/@" .. folder_spec.folder, folder_spec.label, "folder", items.inherit(parent, {
          kind = "folder",
          folder = folder_spec.folder,
          record = records,
        }))
      )
    end
  end
  return vim.list_extend(result, grants.folder(node, grants.rows(grants.schema_target(parent.schema), schema.grants)))
end

---@param node dbtree.Item|NuiTree.Node
---@return dbtree.Item[]
function M.relations(node)
  local parent = node.extra
  local result = {}
  for _, relation in ipairs(parent.record) do
    local id = node.id .. "/" .. items.segment(relation.name)
    table.insert(
      result,
      items.container(id, relation.name, relation.kind, items.inherit(parent, {
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
function M.relation_folders(node)
  local parent = node.extra
  local result = {}
  for _, part in ipairs(RELATION_PARTS) do
    local records = parent.record[part.folder] or {}
    if #records > 0 then
      table.insert(
        result,
        items.container(node.id .. "/@" .. part.folder, part.label, "folder", items.inherit(parent, {
          kind = "folder",
          folder = part.folder,
          leaf = part.leaf,
          record = records,
        }))
      )
    end
  end
  return vim.list_extend(result, grants.folder(node, grants.relation_rows(parent.schema, parent.record)))
end

---@param node dbtree.Item|NuiTree.Node
---@return dbtree.Item[]
function M.relation_parts(node)
  local parent = node.extra
  local result = {}
  for _, record in ipairs(parent.record) do
    table.insert(
      result,
      items.leaf(node.id .. "/" .. items.segment(record.name), record.name, parent.leaf, items.inherit(parent, {
        kind = parent.leaf,
        record = record,
      }))
    )
  end
  return result
end

--- Returns the sequences in a Sequences folder. A sequence with no grants is a
--- leaf, because its Grants folder is its only child.
---@param node dbtree.Item|NuiTree.Node
---@return dbtree.Item[]
function M.sequences(node)
  local result = {}
  for _, sequence in ipairs(node.extra.record) do
    local id = node.id .. "/" .. items.segment(sequence.name)
    local extra = items.inherit(node.extra, {
      kind = "sequence",
      record = sequence,
      target = grants.sequence_target(node.extra.schema, sequence),
    })
    local make_item = #(sequence.grants or {}) > 0 and items.container or items.leaf
    table.insert(result, make_item(id, sequence.name, "sequence", extra))
  end
  return result
end

---@param node dbtree.Item|NuiTree.Node
---@return dbtree.Item[]
function M.sequence_grants(node)
  return grants.folder(node, grants.rows(node.extra.target, node.extra.record.grants))
end

return M
