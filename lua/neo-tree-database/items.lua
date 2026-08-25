--[[
Turning a fetched catalog into tree items.

One query hands back a whole catalog, so everything under a catalog is built
from a document already in hand. The building is still done a level at a time,
because a catalog holding ten thousand tables would otherwise become a hundred
thousand nodes the moment it was opened, all of them collapsed and none of them
looked at.

Every container is built with a single child saying it has not loaded yet. That
child is what draws the expander arrow, and neo-tree replaces it wholesale when
the real children arrive.
]]

local M = {}

---@class dbtree.Column
---@field name string
---@field type string
---@field nullable boolean
---@field default string|nil
---@field position integer
---@field identity string|nil postgres `attidentity`, `a` or `d`.
---@field generated string|nil postgres `attgenerated`, `s` for stored.

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

---@class dbtree.Schema
---@field name string
---@field relations dbtree.Relation[]

--- A name as one segment of a node id. The three characters that separate or
--- introduce a segment are encoded, so a schema named `a` holding a table `b`
--- cannot produce the id of a schema named `a/b`.
---@param name string
---@return string
local function segment(name)
  return (name:gsub("[%%/@]", function(char)
    return string.format("%%%02X", string.byte(char))
  end))
end

---@param id string
---@param name string
---@param node_type string
---@param extra table
---@return table
local function container(id, name, node_type, extra)
  return {
    id = id,
    name = name,
    type = node_type,
    loaded = false,
    extra = extra,
    children = {
      {
        id = id .. "/@loading",
        name = "..loading",
        type = "loading",
        extra = { kind = "loading" },
      },
    },
  }
end

---@param id string
---@param name string
---@param node_type string
---@param extra table
---@return table
local function leaf(id, name, node_type, extra)
  return { id = id, name = name, type = node_type, extra = extra }
end

--- What a node shows in place of children it could not fetch. Rendering this
--- does not mean the node is loaded, and the caller says so.
---@param parent_id string
---@param text string
---@return table[]
function M.message(parent_id, text)
  return { leaf(parent_id .. "/@message", text, "message", { kind = "message" }) }
end

--- The id every other id is built from. Node ids are built here and nowhere
--- else, so the separator stays one module's business.
M.ROOT = "db:"

--- The single node everything hangs under.
---
--- A root exists rather than the connections standing at the top level because
--- neo-tree hides a tree's root by marking the first item it is given, and with
--- no root that mark would fall on the first connection and hide it.
---@param children table[]
---@return table[]
function M.root(children)
  return {
    {
      id = M.ROOT,
      name = "Databases",
      type = "root",
      loaded = true,
      extra = { kind = "root" },
      children = children,
      _is_expanded = true,
    },
  }
end

---@param connections dbtree.Connection[]
---@return table[]
function M.connections(connections)
  local items = {}
  for _, connection in ipairs(connections) do
    local id = M.ROOT .. "/" .. segment(connection.name)
    table.insert(
      items,
      container(id, connection.name, "connection", {
        kind = "connection",
        connection = connection,
        url = connection.url,
      })
    )
  end
  return items
end

---@param node NuiTree.Node
---@param names string[]
---@param catalog_url fun(connection: string, catalog: string): string
---@return table[]
function M.catalogs(node, names, catalog_url)
  local parent = node.extra
  local items = {}
  for _, name in ipairs(names) do
    local id = node:get_id() .. "/" .. segment(name)
    table.insert(
      items,
      container(id, name, "catalog", {
        kind = "catalog",
        connection = parent.connection,
        catalog = name,
        url = catalog_url(parent.url, name),
      })
    )
  end
  return items
end

---@param node NuiTree.Node
---@param document { schemas: dbtree.Schema[] }
---@return table[]
function M.schemas(node, document)
  local parent = node.extra
  local items = {}
  for _, schema in ipairs(document.schemas or {}) do
    local id = node:get_id() .. "/" .. segment(schema.name)
    table.insert(
      items,
      container(id, schema.name, "schema", {
        kind = "schema",
        connection = parent.connection,
        catalog = parent.catalog,
        url = parent.url,
        schema = schema.name,
        record = schema,
      })
    )
  end
  return items
end

--- A folder appears only when it would hold something, so a table without
--- indexes offers nothing to open onto an empty list.
local RELATION_GROUPS = {
  { folder = "tables", label = "Tables", kind = "table" },
  { folder = "views", label = "Views", kind = "view" },
  { folder = "materialized_views", label = "Materialized Views", kind = "materialized_view" },
}

---@param node NuiTree.Node
---@return table[]
function M.schema_groups(node)
  local parent = node.extra
  local relations = parent.record.relations or {}

  local items = {}
  for _, group in ipairs(RELATION_GROUPS) do
    local matching = {}
    for _, relation in ipairs(relations) do
      if relation.kind == group.kind then
        table.insert(matching, relation)
      end
    end
    if #matching > 0 then
      local id = node:get_id() .. "/@" .. group.folder
      table.insert(
        items,
        container(id, group.label, "folder", {
          kind = "folder",
          folder = group.folder,
          connection = parent.connection,
          catalog = parent.catalog,
          url = parent.url,
          schema = parent.schema,
          record = matching,
        })
      )
    end
  end
  return items
end

---@param node NuiTree.Node
---@return table[]
function M.relations(node)
  local parent = node.extra
  local items = {}
  for _, relation in ipairs(parent.record) do
    local id = node:get_id() .. "/" .. segment(relation.name)
    table.insert(
      items,
      container(id, relation.name, relation.kind, {
        kind = relation.kind,
        connection = parent.connection,
        catalog = parent.catalog,
        url = parent.url,
        schema = parent.schema,
        relation = relation.name,
        record = relation,
      })
    )
  end
  return items
end

--- Each part of a relation, named by the field holding it, the label its folder
--- shows, and the node type its leaves take, which is also the key their
--- renderer is configured under.
local RELATION_PARTS = {
  { folder = "columns", label = "Columns", leaf = "column" },
  { folder = "indexes", label = "Indexes", leaf = "index" },
  { folder = "constraints", label = "Constraints", leaf = "constraint" },
}

---@param node NuiTree.Node
---@return table[]
function M.relation_groups(node)
  local parent = node.extra
  local items = {}
  for _, part in ipairs(RELATION_PARTS) do
    local held = parent.record[part.folder] or {}
    if #held > 0 then
      local id = node:get_id() .. "/@" .. part.folder
      table.insert(
        items,
        container(id, part.label, "folder", {
          kind = "folder",
          folder = part.folder,
          leaf = part.leaf,
          connection = parent.connection,
          catalog = parent.catalog,
          url = parent.url,
          schema = parent.schema,
          relation = parent.relation,
          record = held,
        })
      )
    end
  end
  return items
end

---@param node NuiTree.Node
---@return table[]
function M.relation_parts(node)
  local parent = node.extra
  local items = {}
  for _, record in ipairs(parent.record) do
    local id = node:get_id() .. "/" .. segment(record.name)
    table.insert(
      items,
      leaf(id, record.name, parent.leaf, {
        kind = parent.leaf,
        connection = parent.connection,
        catalog = parent.catalog,
        url = parent.url,
        schema = parent.schema,
        relation = parent.relation,
        record = record,
      })
    )
  end
  return items
end

return M
