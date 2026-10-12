--- Shows the children of a node, querying the database first for any document
--- they are built from that is not cached yet.

local base = require("neo-tree-database.nodes.base")
local catalogs = require("neo-tree-database.state.catalogs")
local client = require("neo-tree-database.databases.client")
local connection = require("neo-tree-database.nodes.connection")
local database = require("neo-tree-database.nodes.database")
local databases = require("neo-tree-database.databases")
local fetching = require("neo-tree-database.state.fetching")
local grant = require("neo-tree-database.nodes.grant")
local role = require("neo-tree-database.nodes.role")
local routine = require("neo-tree-database.nodes.function")
local schema = require("neo-tree-database.nodes.schema")
local sequence = require("neo-tree-database.nodes.sequence")
local relation = require("neo-tree-database.nodes.table")

local log = require("neo-tree.log")
local renderer = require("neo-tree.ui.renderer")

local M = {}

---@param message string
---@return string
local function first_line(message)
  return (vim.split(vim.trim(message), "\n", { plain = true })[1] or message)
end

--- Shows `children` under `node`, or a message saying it is empty when there are
--- none. neo-tree draws a loaded node that has no children without an expander.
---@param state neotree.State
---@param node NuiTree.Node
---@param children dbtree.Item[]
local function show_children(state, node, children)
  local id = node:get_id()
  if #children == 0 then
    children = base.message(id, "empty")
  end
  renderer.show_nodes(children, state, id)
end

--- Shows `message` under `node` and marks the node unloaded, so expanding it
--- again queries the database again. neo-tree marks a node loaded whenever it
--- shows children under it.
---@param state neotree.State
---@param node NuiTree.Node
---@param message string
local function show_failure(state, node, message)
  log.error("neo-tree database: " .. message)

  local id = node:get_id()
  renderer.show_nodes(base.message(id, first_line(message)), state, id)

  local rendered = state.tree and state.tree:get_node(id)
  if rendered then
    rendered.loaded = false
  end
end

---@type table<string, fun(node: dbtree.Item|NuiTree.Node): dbtree.Item[]>
local CHILDREN_BY_FOLDER = {
  tables = relation.relations,
  views = relation.relations,
  materialized_views = relation.relations,
  sequences = sequence.sequences,
  functions = routine.folder_routines,
  procedures = routine.folder_routines,
  aggregates = routine.folder_routines,
  macros = routine.folder_routines,
  table_macros = routine.folder_routines,
  arguments = routine.argument_items,
  columns = relation.parts,
  indexes = relation.parts,
  constraints = relation.parts,
  grants = grant.grantee_items,
  roles = role.folder_roles,
  member_of = role.membership_roles,
  members = role.membership_roles,
  role_grants = function(node)
    return role.grant_catalogs(node, catalogs.get)
  end,
}

--- Returns the cached answer for the first document of `node`.
---@param node dbtree.Item|NuiTree.Node
---@return table
local function document_of(node)
  return assert(catalogs.get(node.extra.documents[1].id), "built before its document was read")
end

---@type table<string, fun(node: dbtree.Item|NuiTree.Node): dbtree.Item[]>
local CHILDREN_BY_TYPE = {
  connection = function(node)
    local scheme = assert(databases.of(node.extra.url), "a connection was read with no scheme to read it")
    local server = document_of(node)
    local children = connection.catalogs(node, server.catalogs, scheme.catalog_url)
    return vim.list_extend(children, role.folder(node, server, scheme.catalog_url))
  end,
  catalog = function(node)
    return database.schemas(node, document_of(node))
  end,
  grant_catalog = function(node)
    return grant.held_items(node, document_of(node))
  end,
  schema = schema.folders,
  table = relation.folders,
  view = relation.folders,
  materialized_view = relation.folders,
  sequence = sequence.grants,
  overloaded_routine = routine.overload_items,
  routine = routine.routine_children,
  ["return"] = routine.return_columns,
  role = role.role_children,
  public = role.role_children,
  folder = function(node)
    return CHILDREN_BY_FOLDER[node.extra.folder](node)
  end,
}

---@param node NuiTree.Node
---@return dbtree.Document[]
local function unread_documents(node)
  local result = {}
  for _, document in ipairs(node.extra.documents or {}) do
    if not catalogs.get(document.id) then
      table.insert(result, document)
    end
  end
  return result
end

--- Queries every one of `documents` and caches the answers. When the last answer
--- arrives, it shows the children of whatever node then has `node`'s id, which
--- is a new node if the tree was rebuilt in the meantime. It shows an error only
--- when that node has none of its documents cached.
---@param state neotree.State
---@param node NuiTree.Node
---@param documents dbtree.Document[]
local function fetch_and_show(state, node, documents)
  local scheme = databases.of(node.extra.url)
  if not scheme then
    return show_failure(
      state,
      node,
      ("cannot browse %s, only %s"):format(node.extra.url, table.concat(databases.supported_schemes(), ", "))
    )
  end

  local id = node:get_id()
  if fetching.has(id) then
    return
  end
  fetching.add(id)

  -- Expanding now shows the loading placeholder while the queries run.
  if node:has_children() and not node:is_expanded() then
    node:expand()
    renderer.redraw(state)
  end

  local pending_count = #documents
  local errors = {}
  for _, document in ipairs(documents) do
    local request = document.catalog and scheme.introspect(document.url, document.catalog)
      or scheme.catalogs(document.url)
    client.run(request, function(answer, err)
      if err then
        table.insert(errors, err)
      else
        catalogs.put(document.id, answer)
      end
      pending_count = pending_count - 1
      if pending_count > 0 then
        return
      end

      fetching.remove(id)
      local current_node = state.tree and state.tree:get_node(id)
      if not current_node then
        return
      end
      if #unread_documents(current_node) == #current_node.extra.documents then
        if #errors == 0 then
          -- A refresh dropped these answers from the cache while the queries ran.
          return M.expand(state, current_node)
        end
        return show_failure(state, current_node, errors[1])
      end
      show_children(state, current_node, CHILDREN_BY_TYPE[current_node.type](current_node))
    end)
  end
end

--- Returns whether `node` can expand. A sequence, function or return node with
--- nothing to show is built as a leaf, so its type alone does not decide this.
---@param node NuiTree.Node
---@return boolean
function M.is_container(node)
  return CHILDREN_BY_TYPE[node.type] ~= nil and node:has_children()
end

--- Shows the children of `node`, building them from the cache when every
--- document they need is cached and querying the database otherwise.
---@param state neotree.State
---@param node NuiTree.Node
function M.expand(state, node)
  local build_children = CHILDREN_BY_TYPE[node.type]
  if not build_children then
    return
  end

  local documents = unread_documents(node)
  if #documents > 0 then
    return fetch_and_show(state, node, documents)
  end
  show_children(state, node, build_children(node))
end

--- Drops the cached documents of `node`, and everything cached under them, then
--- expands `node` again.
---@param state neotree.State
---@param node NuiTree.Node
function M.refresh(state, node)
  if fetching.has(node:get_id()) then
    return vim.notify("neo-tree database: " .. node.name .. " is already loading")
  end

  for _, document in ipairs(node.extra.documents) do
    catalogs.drop(document.id)
  end
  node.loaded = false
  M.expand(state, node)
end

return M
