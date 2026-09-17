--[[
The database source.

Connections come from a file, a catalog list comes from one query per
connection, and everything below a catalog comes from one query per catalog. So
the two nodes that reach the network are the connection and the catalog, and
every level under them is built from a document already held.

Expanding is owned here rather than by neo-tree's shared `open`, because that
one hands a node to its source only when the node's type is `directory`, and
these nodes carry what they are as their type instead.
]]

local cache = require("neo-tree-database.cache")
local client = require("neo-tree-database.client")
local connections = require("neo-tree-database.connections")
local items = require("neo-tree-database.items")
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

--- Runs `request` and hands the document to `on_document` along with the node
--- as it stands when the answer arrives, which is not the node that asked if
--- the tree was rebuilt in the meantime.
---@param state neotree.State
---@param node NuiTree.Node
---@param request dbtree.Request
---@param on_document fun(document: table, node: NuiTree.Node)
local function fetch(state, node, request, on_document)
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

  client.run(request, function(document, err)
    inflight[id] = nil

    local live = state.tree and state.tree:get_node(id)
    if not live then
      return
    end
    if err then
      return show_failure(state, live, err)
    end
    on_document(document, live)
  end)
end

--- What each container holds, built from answers already fetched, or nil when
--- its database has not been asked. Everything below a catalog is built from
--- the document the catalog answered, so only a connection and a catalog can
--- answer nil.
---@type table<string, fun(node: dbtree.Item|NuiTree.Node): dbtree.Item[]|nil>
local HELD = {
  connection = function(node)
    local scheme = schemes.of(node.extra.url)
    local names = cache.get(node.id)
    if scheme and names then
      return items.catalogs(node, names, scheme.catalog_url)
    end
    return nil
  end,
  catalog = function(node)
    local document = cache.get(node.id)
    if document then
      return items.schemas(node, document)
    end
    return nil
  end,
  schema = items.schema_groups,
  folder = function(node)
    -- A folder holding part of a relation says which node type its leaves take.
    -- A folder holding relations does not, because each relation says its own.
    if node.extra.leaf then
      return items.relation_parts(node)
    end
    return items.relations(node)
  end,
  table = items.relation_groups,
}
HELD.view = HELD.table
HELD.materialized_view = HELD.table

---@param state neotree.State
---@param node NuiTree.Node
local function fetch_catalogs(state, node)
  local scheme = schemes.of(node.extra.url)
  if not scheme then
    return show_failure(
      state,
      node,
      ("cannot browse %s, only %s"):format(node.extra.url, table.concat(schemes.supported(), ", "))
    )
  end

  fetch(state, node, scheme.catalogs(node.extra.url), function(document, live)
    local names = document.catalogs or {}
    cache.put(live:get_id(), names)
    show(state, live, items.catalogs(live, names, scheme.catalog_url))
  end)
end

---@param state neotree.State
---@param node NuiTree.Node
local function fetch_catalog(state, node)
  local scheme = schemes.of(node.extra.url)
  if not scheme then
    return show_failure(state, node, "cannot browse " .. node.extra.url)
  end

  -- A catalog node already carries the url that reaches it, which for postgres
  -- is not the url the connection was written with.
  fetch(state, node, scheme.introspect(node.extra.url, node.extra.catalog), function(document, live)
    cache.put(live:get_id(), document)
    show(state, live, items.schemas(live, document))
  end)
end

---@type table<string, fun(state: neotree.State, node: NuiTree.Node)>
local FETCHERS = {
  connection = fetch_catalogs,
  catalog = fetch_catalog,
}

--- Whether `node` holds anything to open onto.
---@param node NuiTree.Node
---@return boolean
function M.is_container(node)
  return HELD[node.type] ~= nil
end

--- Fills `node` with its children, from what is already held when it can and
--- from the database when it cannot.
---@param state neotree.State
---@param node NuiTree.Node
function M.expand(state, node)
  local held = HELD[node.type]
  if not held then
    return
  end

  local children = held(node)
  if children then
    return show(state, node, children)
  end
  FETCHERS[node.type](state, node)
end

--- Forgets what `node` answered and asks again. Everything under it is dropped
--- too, so a schema that has been renamed does not keep its old tables.
---
--- A node already waiting on an answer is left alone. Dropping the cache under
--- it would not stop the running query, which would then fill the node with the
--- answer the refresh was meant to replace.
---@param state neotree.State
---@param node NuiTree.Node
function M.refresh_node(state, node)
  local id = node:get_id()
  if inflight[id] then
    return vim.notify("neo-tree database: " .. node.name .. " is already loading")
  end

  cache.drop(id)
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

---@class (exact) neotree.Config.Database : neotree.Config.Source
---@field connections dbtree.Connection[]|fun(): dbtree.Connection[]|nil
---@field open_scratch fun(spec: dbtree.Scratch)|nil

--- Every node type this source emits needs its own renderer, because a type
--- with none renders as `type: name` with the type spelled out.
local function line(...)
  local components = { { "indent", with_expanders = true }, { "icon" }, { "name" } }
  for _, extra in ipairs({ ... }) do
    table.insert(components, extra)
  end
  return components
end

--- Keys neo-tree binds for every source that mean nothing here. A database node
--- has no path, so the commands behind these keys either do nothing or reach
--- for a field that is not there. They are turned off rather than left to
--- resolve to a warning and a key that silently does nothing.
local DISABLED = {
  "a",
  "A",
  "T",
  "u",
  "U",
  "r",
  "x",
  "p",
  "m",
  "S",
  "t",
  "w",
  "P",
  "<C-r>",
  "<C-f>",
  "<C-b>",
  "<C-s>",
  "<Tab>",
  "<C-S-i>",
  "<C-;>",
}

local mappings = {
  ["<cr>"] = "open",
  ["<space>"] = "toggle_node",
  ["l"] = "open",
  ["R"] = "refresh_node",
  ["y"] = "yank_name",
  ["i"] = "object_info",
  ["d"] = "object_drop",
  ["c"] = "object_change",
  ["s"] = "open_scratch",
}
for _, key in ipairs(DISABLED) do
  mappings[key] = "noop"
end

M.default_config = {
  connections = nil,
  open_scratch = nil,
  renderers = {
    root = { { "indent" }, { "icon" }, { "name" } },
    connection = line({ "detail" }),
    catalog = line(),
    schema = line({ "detail" }),
    folder = line(),
    table = line({ "detail" }),
    view = line({ "detail" }),
    materialized_view = line({ "detail" }),
    column = { { "indent" }, { "icon" }, { "name" }, { "detail" } },
    index = { { "indent" }, { "icon" }, { "name" }, { "detail" } },
    constraint = { { "indent" }, { "icon" }, { "name" }, { "detail" } },
    loading = { { "indent" }, { "name" } },
    message = { { "indent", with_markers = false }, { "name" } },
  },
  window = {
    mappings = mappings,
  },
}

---@param config neotree.Config.Database
---@param global_config neotree.Config.Base
M.setup = function(config, global_config)
  M.config = config
end

return M
