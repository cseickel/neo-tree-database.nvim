--[[
The pieces every tree item is built from, and the levels above a catalog.

The building is done a level at a time, because a catalog holding ten thousand
tables would otherwise become a hundred thousand nodes the moment it was
opened, all of them collapsed and none of them looked at. `objects.lua` builds
what a catalog holds, and `roles.lua` and `grants.lua` build who can reach it.

Every container is built with a single child saying it has not loaded yet. That
child is what draws the expander arrow, and neo-tree replaces it wholesale when
the real children arrive.
]]

local M = {}

---@class dbtree.Item
---@field id string
---@field name string
---@field type string
---@field extra table
---@field loaded boolean|nil
---@field children dbtree.Item[]|nil
---@field _is_expanded boolean|nil

---@class dbtree.Document An answer a node is built from, and how to ask for it.
---@field id string What the answer is cached under.
---@field url string
---@field catalog string|nil The catalog the answer describes, nil for a connection's catalog list.

--- A name as one segment of a node id. The three characters that separate or
--- introduce a segment are encoded, so a schema named `a` holding a table `b`
--- cannot produce the id of a schema named `a/b`, and a name can never produce
--- a segment starting with `@`, which marks a heading or a placeholder.
---@param name string
---@return string
function M.segment(name)
  return (name:gsub("[%%/@]", function(char)
    return string.format("%%%02X", string.byte(char))
  end))
end

---@param id string
---@param name string
---@param node_type string
---@param extra table
---@return dbtree.Item
function M.container(id, name, node_type, extra)
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
---@return dbtree.Item
function M.leaf(id, name, node_type, extra)
  return { id = id, name = name, type = node_type, extra = extra }
end

--- The fields a node below a connection takes from its parent, so a command on
--- any of them can reach the database and name the object it sits in, with
--- `fields` added on top.
---@param parent table The parent node's `extra`.
---@param fields table
---@return table
function M.inherit(parent, fields)
  return vim.tbl_extend("force", {
    connection = parent.connection,
    catalog = parent.catalog,
    url = parent.url,
    schema = parent.schema,
    relation = parent.relation,
  }, fields)
end

--- `name(arguments)` for a function, which postgres tells apart from its
--- overloads by the argument types. Just `name` where the database keeps none.
---@param name string
---@param arguments string|nil
---@return string
function M.signature(name, arguments)
  if arguments then
    return name .. "(" .. arguments .. ")"
  end
  return name
end

--- What a node shows in place of children it could not fetch. Rendering this
--- does not mean the node is loaded, and the caller says so.
---@param parent_id string
---@param text string
---@return dbtree.Item[]
function M.message(parent_id, text)
  return { M.leaf(parent_id .. "/@message", text, "message", { kind = "message" }) }
end

--- The id every other id is built from.
M.ROOT = "db:"

--- The single node everything hangs under.
---
--- A root exists rather than the connections standing at the top level because
--- neo-tree hides a tree's root by marking the first item it is given, and with
--- no root that mark would fall on the first connection and hide it.
---@param children table[]
---@return dbtree.Item[]
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

---@param connection dbtree.Connection
---@return string
local function connection_id(connection)
  return M.ROOT .. "/" .. M.segment(connection.name)
end

--- The id of the node for `catalog` on `connection`. A catalog's document is
--- cached under this id, so it is also how a node elsewhere in the tree, such
--- as a role's grants in that catalog, finds the same document.
---@param connection dbtree.Connection
---@param catalog string
---@return string
function M.catalog_id(connection, catalog)
  return connection_id(connection) .. "/" .. M.segment(catalog)
end

--- The document describing `catalog` on `connection`, reached at `url`.
---@param connection dbtree.Connection
---@param catalog string
---@param url string
---@return dbtree.Document
function M.catalog_document(connection, catalog, url)
  return { id = M.catalog_id(connection, catalog), url = url, catalog = catalog }
end

---@param connections dbtree.Connection[]
---@return dbtree.Item[]
function M.connections(connections)
  local items = {}
  for _, connection in ipairs(connections) do
    local id = connection_id(connection)
    table.insert(
      items,
      M.container(id, connection.name, "connection", {
        kind = "connection",
        connection = connection,
        url = connection.url,
        documents = { { id = id, url = connection.url } },
      })
    )
  end
  return items
end

return M
