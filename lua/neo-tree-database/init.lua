--[[
The database source.

Connections come from a file, a catalog list and the roles come from one query
per connection, and everything below a catalog comes from one query per catalog.
A node that needs one of those answers names it in its `documents`, and opening
it asks for whichever of them is not held yet. Every other node is built from a
document already held.

Expanding is owned here rather than by neo-tree's shared `open`, because that
one hands a node to its source only when the node's type is `directory`, and
these nodes carry what they are as their type instead.
]]

local cache = require("neo-tree-database.cache")
local client = require("neo-tree-database.client")
local connections = require("neo-tree-database.connections")
local grants = require("neo-tree-database.grants")
local items = require("neo-tree-database.items")
local objects = require("neo-tree-database.objects")
local roles = require("neo-tree-database.roles")
local schemes = require("neo-tree-database.schemes")

local log = require("neo-tree.log")
local renderer = require("neo-tree.ui.renderer")

---@class neotree.sources.Database : neotree.Source
local M = {
  name = "database",
  display_name = " 󰆼 Database ",
}

M.config = {}

--- Node ids with a fetch already running, so holding down the expand key asks
--- the database once rather than once per keypress.
---@type table<string, boolean>
local inflight = {}

---@param message string
---@return string
local function first_line(message)
  return (vim.split(vim.trim(message), "\n", { plain = true })[1] or message)
end

--- Puts `children` under `node`.
---
--- An empty list is shown as a line saying so rather than as no lines at all,
--- because rendering children is what marks a node loaded, and a loaded node
--- with no children has no expander arrow and nothing to say. It would sit
--- there looking like a key that stopped working.
---@param state neotree.State
---@param node NuiTree.Node
---@param children dbtree.Item[]
local function show(state, node, children)
  local id = node:get_id()
  if #children == 0 then
    children = items.message(id, "empty")
  end
  renderer.show_nodes(children, state, id)
end

--- Shows why a node has no children, and leaves the node unloaded so opening it
--- again tries the database again. Rendering children is what marks a node
--- loaded, and a node that failed has not loaded.
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

--- Each folder's children, by the `folder` its extra names.
---@type table<string, fun(node: dbtree.Item|NuiTree.Node): dbtree.Item[]>
local FOLDERS = {
  tables = objects.relations,
  views = objects.relations,
  materialized_views = objects.relations,
  sequences = objects.sequences,
  functions = objects.routines,
  columns = objects.relation_parts,
  indexes = objects.relation_parts,
  constraints = objects.relation_parts,
  grants = grants.grantees,
  roles = roles.listed,
  member_of = roles.named,
  members = roles.named,
  role_grants = function(node)
    return roles.catalogs(node, cache.get)
  end,
}

--- The answer a node with a single document is built from. It is held,
--- because such a node is built only once its document has been read.
---@param node dbtree.Item|NuiTree.Node
---@return table
local function document_of(node)
  return assert(cache.get(node.extra.documents[1].id), "built before its document was read")
end

--- What each container holds, built from answers already fetched.
---@type table<string, fun(node: dbtree.Item|NuiTree.Node): dbtree.Item[]>
local HELD = {
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
    return grants.held(node, document_of(node))
  end,
  schema = objects.schema_folders,
  table = objects.relation_folders,
  view = objects.relation_folders,
  materialized_view = objects.relation_folders,
  sequence = objects.grant_folder,
  routine = objects.grant_folder,
  role = roles.parts,
  public = roles.parts,
  folder = function(node)
    return FOLDERS[node.extra.folder](node)
  end,
}

--- The documents `node` names that are not held yet.
---@param node NuiTree.Node
---@return dbtree.Document[]
local function unread(node)
  local result = {}
  for _, document in ipairs(node.extra.documents or {}) do
    if not cache.get(document.id) then
      table.insert(result, document)
    end
  end
  return result
end

--- Reads `documents` all at once, keeps each answer, and fills the node as it
--- stands when the last answer arrives, which is not the node that asked if
--- the tree was rebuilt in the meantime.
---
--- The node fails only when it holds none of its documents afterwards. When it
--- holds some, it is built from those, and decides itself what an unread
--- document means.
---@param state neotree.State
---@param node NuiTree.Node
---@param documents dbtree.Document[]
local function fetch(state, node, documents)
  local scheme = schemes.of(node.extra.url)
  if not scheme then
    return show_failure(
      state,
      node,
      ("cannot browse %s, only %s"):format(node.extra.url, table.concat(schemes.supported(), ", "))
    )
  end

  local id = node:get_id()
  if inflight[id] then
    return
  end
  inflight[id] = true

  -- Opening the node now is what puts its placeholder child on screen, so a
  -- connection that takes a second to answer looks like it is working rather
  -- than like a key that did nothing.
  if node:has_children() and not node:is_expanded() then
    node:expand()
    renderer.redraw(state)
  end

  local waiting = #documents
  local errors = {}
  for _, document in ipairs(documents) do
    -- A catalog's document is read through the url that reaches the catalog,
    -- which for postgres is not the url the connection was written with.
    local request = document.catalog and scheme.introspect(document.url, document.catalog)
      or scheme.catalogs(document.url)
    client.run(request, function(answer, err)
      if err then
        table.insert(errors, err)
      else
        cache.put(document.id, answer)
      end
      waiting = waiting - 1
      if waiting > 0 then
        return
      end

      inflight[id] = nil
      local live = state.tree and state.tree:get_node(id)
      if not live then
        return
      end
      if #unread(live) == #live.extra.documents then
        if #errors == 0 then
          -- A refresh elsewhere dropped everything it read while it waited.
          return M.expand(state, live)
        end
        return show_failure(state, live, errors[1])
      end
      show(state, live, HELD[live.type](live))
    end)
  end
end

--- Whether `node` opens onto anything. A sequence or a function is a leaf
--- where it has no grants to show, so the type alone does not answer this.
---@param node NuiTree.Node
---@return boolean
function M.is_container(node)
  return HELD[node.type] ~= nil and node:has_children()
end

--- Fills `node` with its children, from what is already held when it can and
--- from the database when it cannot.
---@param state neotree.State
---@param node NuiTree.Node
function M.expand(state, node)
  local build = HELD[node.type]
  if not build then
    return
  end

  local documents = unread(node)
  if #documents > 0 then
    return fetch(state, node, documents)
  end
  show(state, node, build(node))
end

--- Forgets the documents `node` was built from and asks again. Everything
--- cached under them is dropped too, so a schema that has been renamed does not
--- keep its old tables.
---
--- A node already waiting on an answer is left alone. Dropping the cache under
--- it would not stop the running query, which would then fill the node with the
--- answer the refresh was meant to replace.
---@param state neotree.State
---@param node NuiTree.Node
function M.refresh_node(state, node)
  if inflight[node:get_id()] then
    return vim.notify("neo-tree database: " .. node.name .. " is already loading")
  end

  for _, document in ipairs(node.extra.documents) do
    cache.drop(document.id)
  end
  node.loaded = false
  M.expand(state, node)
end

--- `node` and everything under it, as items neo-tree can build a tree from.
---@param tree NuiTree
---@param node NuiTree.Node
---@return dbtree.Item
local function copy(tree, node)
  ---@type dbtree.Item
  local item = { id = node.id, name = node.name, type = node.type, extra = node.extra, loaded = node.loaded }
  if node:has_children() then
    item.children = {}
    for _, child in ipairs(tree:get_nodes(node.id)) do
      table.insert(item.children, copy(tree, child))
    end
  end
  return item
end

--- Gives each connection in `list` what it showed in `tree`: its catalogs,
--- what was loaded under them, and any error. A connection whose url has
--- changed starts over, so it cannot show another server's catalogs.
---
--- neo-tree reopens nodes after a rebuild only by id, and only the ones present
--- in the new items, so without this every connection comes back closed over
--- its placeholder.
---@param tree NuiTree
---@param list dbtree.Item[]
local function restore(tree, list)
  for _, item in ipairs(list) do
    local previous = tree:get_node(item.id)
    if previous and previous.extra.url == item.extra.url then
      item.loaded = previous.loaded
      item.children = copy(tree, previous).children
    end
  end
end

---Navigate to the given path.
---@param state neotree.State
---@param path string?
---@param path_to_reveal string?
---@param callback function?
M.navigate = function(state, path, path_to_reveal, callback)
  -- Every source clears this first. Left set, neo-tree treats the tree as
  -- needing a rebuild on every open and focus.
  state.dirty = false
  state.path = items.ROOT

  local list, err = connections.list(M.config.connections)
  local children
  if err then
    children = items.message(items.ROOT, err)
  elseif #list == 0 then
    children = items.message(items.ROOT, "no connections")
  else
    children = items.connections(list)
    -- neo-tree rebuilds the tree whenever the window is reopened and whenever
    -- any other source refreshes, and the tree being replaced is still here.
    if state.tree then
      restore(state.tree, children)
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
  require("neo-tree-database.focus").track(M.name)
  require("neo-tree-database.highlights").setup()
end

return M
