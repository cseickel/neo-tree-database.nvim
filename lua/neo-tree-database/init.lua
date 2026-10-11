--- Defines the neo-tree source that browses databases.

local cache = require("neo-tree-database.cache")
local client = require("neo-tree-database.client")
local connections = require("neo-tree-database.connections")
local grants = require("neo-tree-database.grants")
local items = require("neo-tree-database.items")
local objects = require("neo-tree-database.objects")
local roles = require("neo-tree-database.roles")
local routines = require("neo-tree-database.routines")
local schemes = require("neo-tree-database.schemes")

local log = require("neo-tree.log")
local renderer = require("neo-tree.ui.renderer")

---@class neotree.sources.Database : neotree.Source
local M = {
  name = "database",
  display_name = " 󰆼 Database ",
}

M.config = {}

---@type table<string, boolean>
local fetching_ids = {}

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
    children = items.message(id, "empty")
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
  renderer.show_nodes(items.message(id, first_line(message)), state, id)

  local rendered = state.tree and state.tree:get_node(id)
  if rendered then
    rendered.loaded = false
  end
end

---@type table<string, fun(node: dbtree.Item|NuiTree.Node): dbtree.Item[]>
local CHILDREN_BY_FOLDER = {
  tables = objects.relations,
  views = objects.relations,
  materialized_views = objects.relations,
  sequences = objects.sequences,
  functions = routines.folder_routines,
  procedures = routines.folder_routines,
  aggregates = routines.folder_routines,
  macros = routines.folder_routines,
  table_macros = routines.folder_routines,
  arguments = routines.argument_items,
  columns = objects.relation_parts,
  indexes = objects.relation_parts,
  constraints = objects.relation_parts,
  grants = grants.grantee_items,
  roles = roles.folder_roles,
  member_of = roles.membership_roles,
  members = roles.membership_roles,
  role_grants = function(node)
    return roles.grant_catalogs(node, cache.get)
  end,
}

--- Returns the cached answer for the first document of `node`.
---@param node dbtree.Item|NuiTree.Node
---@return table
local function document_of(node)
  return assert(cache.get(node.extra.documents[1].id), "built before its document was read")
end

---@type table<string, fun(node: dbtree.Item|NuiTree.Node): dbtree.Item[]>
local CHILDREN_BY_TYPE = {
  connection = function(node)
    local scheme = assert(schemes.of(node.extra.url), "a connection was read with no scheme to read it")
    local server = document_of(node)
    local children = objects.catalogs(node, server.catalogs, scheme.catalog_url)
    return vim.list_extend(children, roles.folder(node, server, scheme.catalog_url))
  end,
  catalog = function(node)
    return objects.schemas(node, document_of(node))
  end,
  grant_catalog = function(node)
    return grants.held_items(node, document_of(node))
  end,
  schema = objects.schema_folders,
  table = objects.relation_folders,
  view = objects.relation_folders,
  materialized_view = objects.relation_folders,
  sequence = objects.sequence_grants,
  overloaded_routine = routines.overload_items,
  routine = routines.routine_children,
  ["return"] = routines.return_columns,
  role = roles.role_children,
  public = roles.role_children,
  folder = function(node)
    return CHILDREN_BY_FOLDER[node.extra.folder](node)
  end,
}

---@param node NuiTree.Node
---@return dbtree.Document[]
local function unread_documents(node)
  local result = {}
  for _, document in ipairs(node.extra.documents or {}) do
    if not cache.get(document.id) then
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
  local scheme = schemes.of(node.extra.url)
  if not scheme then
    return show_failure(
      state,
      node,
      ("cannot browse %s, only %s"):format(node.extra.url, table.concat(schemes.supported_schemes(), ", "))
    )
  end

  local id = node:get_id()
  if fetching_ids[id] then
    return
  end
  fetching_ids[id] = true

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
        cache.put(document.id, answer)
      end
      pending_count = pending_count - 1
      if pending_count > 0 then
        return
      end

      fetching_ids[id] = nil
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
function M.refresh_node(state, node)
  if fetching_ids[node:get_id()] then
    return vim.notify("neo-tree database: " .. node.name .. " is already loading")
  end

  for _, document in ipairs(node.extra.documents) do
    cache.drop(document.id)
  end
  node.loaded = false
  M.expand(state, node)
end

--- Returns `node` and everything under it as items that neo-tree can build a
--- tree from.
---@param tree NuiTree
---@param node NuiTree.Node
---@return dbtree.Item
local function to_item(tree, node)
  ---@type dbtree.Item
  local item = { id = node.id, name = node.name, type = node.type, extra = node.extra, loaded = node.loaded }
  if node:has_children() then
    item.children = {}
    for _, child in ipairs(tree:get_nodes(node.id)) do
      table.insert(item.children, to_item(tree, child))
    end
  end
  return item
end

--- Copies each connection's loaded state and children from `tree` into
--- `connection_items`, except for a connection whose url changed. neo-tree
--- reopens nodes after a rebuild only by id, and only the ones in the new items.
---@param tree NuiTree
---@param connection_items dbtree.Item[]
local function restore_loaded(tree, connection_items)
  for _, item in ipairs(connection_items) do
    local previous = tree:get_node(item.id)
    if previous and previous.extra.url == item.extra.url then
      item.loaded = previous.loaded
      item.children = to_item(tree, previous).children
    end
  end
end

--- Rebuilds the tree from the connection list.
---@param state neotree.State
---@param path string?
---@param path_to_reveal string?
---@param callback function?
M.navigate = function(state, path, path_to_reveal, callback)
  -- neo-tree rebuilds a dirty tree on every open and focus.
  state.dirty = false
  state.path = items.ROOT

  local connection_list, err = connections.list(M.config.connections)
  local children
  if err then
    children = items.message(items.ROOT, err)
  elseif #connection_list == 0 then
    children = items.message(items.ROOT, "no connections")
  else
    children = items.connections(connection_list)
    if state.tree then
      restore_loaded(state.tree, children)
    end
  end

  renderer.show_nodes(items.root(children), state)

  if type(callback) == "function" then
    vim.schedule(callback)
  end
end

M.default_config = require("neo-tree-database.config")

---@param config neotree.Config.Database
---@param global_config neotree.Config.Base
M.setup = function(config, global_config)
  M.config = config
  require("neo-tree-database.focus").follow_cursor(M.name)
  require("neo-tree-database.highlights").setup()
end

return M
