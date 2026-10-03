--[[
What a catalog holds, as tree items.

One query hands back a whole catalog, so everything here is built from a
document already in hand. A folder appears only when it would hold something,
so a table without indexes offers nothing to open onto an empty list.
]]

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
---@field definition string|nil
---@field columns dbtree.Column[]
---@field indexes dbtree.Index[]
---@field constraints dbtree.Constraint[]
---@field grants dbtree.Grant[]|nil

---@class dbtree.Sequence
---@field name string
---@field definition string
---@field grants dbtree.Grant[]|nil

---@class dbtree.Routine
---@field name string
---@field kind "function"|"procedure"|"aggregate"|"macro"|"table_macro"
---@field arguments string|nil postgres's argument types, which tell overloads apart.
---@field definition string|nil
---@field grants dbtree.Grant[]|nil

---@class dbtree.Schema
---@field name string
---@field relations dbtree.Relation[]
---@field sequences dbtree.Sequence[]
---@field functions dbtree.Routine[]
---@field grants dbtree.Grant[]|nil

---@class dbtree.Catalog
---@field schemas dbtree.Schema[]
---@field grants dbtree.Grant[]|nil

---@param node dbtree.Item|NuiTree.Node
---@param names string[]
---@param catalog_url fun(connection: string, catalog: string): string
---@return dbtree.Item[]
function M.catalogs(node, names, catalog_url)
  local parent = node.extra
  local result = {}
  for _, name in ipairs(names) do
    local url = catalog_url(parent.url, name)
    table.insert(
      result,
      items.container(items.catalog_id(parent.connection, name), name, "catalog", {
        kind = "catalog",
        connection = parent.connection,
        catalog = name,
        url = url,
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

--- The folders a schema shows. A relation folder holds the relations of one
--- kind, and the others hold the schema field they are named after.
local SCHEMA_FOLDERS = {
  { folder = "tables", label = "Tables", kind = "table" },
  { folder = "views", label = "Views", kind = "view" },
  { folder = "materialized_views", label = "Materialized Views", kind = "materialized_view" },
  { folder = "sequences", label = "Sequences" },
  { folder = "functions", label = "Functions" },
}

---@param relations dbtree.Relation[]
---@param kind string
---@return dbtree.Relation[]
local function of_kind(relations, kind)
  local matching = {}
  for _, relation in ipairs(relations) do
    if relation.kind == kind then
      table.insert(matching, relation)
    end
  end
  return matching
end

---@param node dbtree.Item|NuiTree.Node
---@return dbtree.Item[]
function M.schema_folders(node)
  local parent = node.extra
  local schema = parent.record

  local result = {}
  for _, group in ipairs(SCHEMA_FOLDERS) do
    local held = group.kind and of_kind(schema.relations or {}, group.kind) or (schema[group.folder] or {})
    if #held > 0 then
      table.insert(
        result,
        items.container(node.id .. "/@" .. group.folder, group.label, "folder", items.inherit(parent, {
          kind = "folder",
          folder = group.folder,
          record = held,
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

--- Each part of a relation, named by the field holding it, the label its folder
--- shows, and the node type its leaves take, which is also the key their
--- renderer is configured under.
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
    local held = parent.record[part.folder] or {}
    if #held > 0 then
      table.insert(
        result,
        items.container(node.id .. "/@" .. part.folder, part.label, "folder", items.inherit(parent, {
          kind = "folder",
          folder = part.folder,
          leaf = part.leaf,
          record = held,
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

--- A sequence or a function, whose only child is its Grants folder. It is a
--- leaf where it has no grants, as everywhere in duckdb, which keeps none.
---@param node dbtree.Item|NuiTree.Node
---@param name string
---@param node_type string
---@param record dbtree.Sequence|dbtree.Routine
---@param target dbtree.GrantTarget
---@return dbtree.Item
local function granted(node, name, node_type, record, target)
  local id = node.id .. "/" .. items.segment(name)
  local extra = items.inherit(node.extra, { kind = node_type, record = record, target = target })
  if #(record.grants or {}) > 0 then
    return items.container(id, name, node_type, extra)
  end
  return items.leaf(id, name, node_type, extra)
end

---@param node dbtree.Item|NuiTree.Node
---@return dbtree.Item[]
function M.sequences(node)
  local schema = node.extra.schema
  local result = {}
  for _, sequence in ipairs(node.extra.record) do
    table.insert(result, granted(node, sequence.name, "sequence", sequence, grants.sequence_target(schema, sequence)))
  end
  return result
end

---@param node dbtree.Item|NuiTree.Node
---@return dbtree.Item[]
function M.routines(node)
  local schema = node.extra.schema
  local result = {}
  for _, routine in ipairs(node.extra.record) do
    local name = items.signature(routine.name, routine.arguments)
    table.insert(result, granted(node, name, "routine", routine, grants.routine_target(schema, routine)))
  end
  return result
end

--- The Grants folder of a sequence or a function.
---@param node dbtree.Item|NuiTree.Node
---@return dbtree.Item[]
function M.grant_folder(node)
  return grants.folder(node, grants.rows(node.extra.target, node.extra.record.grants))
end

return M
