--- Shows the children of a node, querying the database first for any result
--- they are built from that is neither cached nor saved.

local base = require("neo-tree-database.nodes.base")
local client = require("neo-tree-database.databases.client")
local connection = require("neo-tree-database.nodes.connection")
local database = require("neo-tree-database.nodes.database")
local databases = require("neo-tree-database.databases")
local fetching = require("neo-tree-database.state.fetching")
local grant = require("neo-tree-database.nodes.grant")
local results = require("neo-tree-database.nodes.results")
local role = require("neo-tree-database.nodes.role")
local routine = require("neo-tree-database.nodes.function")
local schema = require("neo-tree-database.nodes.schema")
local sequence = require("neo-tree-database.nodes.sequence")
local relation = require("neo-tree-database.nodes.table")
local catalogs = require("neo-tree-database.state.catalogs")

local log = require("neo-tree.log")
local renderer = require("neo-tree.ui.renderer")

local M = {}

---@param message string
---@return string
local function first_line(message)
  return (vim.split(vim.trim(message), "\n", { plain = true })[1] or message)
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

---@type table<string, fun(node: dbtree.Item|NuiTree.Node): dbtree.Item[]>
local CHILDREN_BY_TYPE = {
  connection = function(node)
    local scheme = assert(databases.of(node.extra.url), "a connection was read with no scheme to read it")
    local server = results.of(node)
    local children = connection.catalogs(node, server.catalogs, scheme.catalog_url)
    return vim.list_extend(children, role.folder(node, server, scheme.catalog_url))
  end,
  catalog = function(node)
    return database.children(node, results.of(node))
  end,
  grant_catalog = function(node)
    return grant.held_items(node, results.of(node))
  end,
  schema = schema.folders,
  table = relation.folders,
  view = relation.folders,
  materialized_view = relation.folders,
  index = relation.index_parts,
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

--- Returns the children of `node`, or a message saying it is empty when there
--- are none. neo-tree draws a loaded node that has no children without an
--- expander.
---@param node dbtree.Item|NuiTree.Node
---@return dbtree.Item[]
local function children_of(node)
  local children = CHILDREN_BY_TYPE[node.type](node)
  if #children == 0 then
    return base.message(node.id, "empty")
  end
  return children
end

--- Returns `items` with the children of each one that is open in the tree
--- built again from the cache, so showing them keeps the tree as it was.
---@param state neotree.State
---@param items dbtree.Item[]
---@return dbtree.Item[]
local function keep_open(state, items)
  for _, item in ipairs(items) do
    local shown = state.tree and state.tree:get_node(item.id)
    if
      shown
      and shown:is_expanded()
      and item.children
      and CHILDREN_BY_TYPE[item.type]
      and #results.uncached(item) == 0
    then
      item.children = keep_open(state, children_of(item))
      item.loaded = true
      item._is_expanded = true
    end
  end
  return items
end

--- Shows the children of `node`, keeping open the ones that were open.
---@param state neotree.State
---@param node NuiTree.Node
local function show_children(state, node)
  renderer.show_nodes(keep_open(state, children_of(node)), state, node:get_id())
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

---@class dbtree.Answered
---@field read dbtree.ResultRead
---@field result table|nil
---@field err string|nil

--- Queries every one of `reads` for `node`, and calls `on_done` with each answer
--- once the last one arrives. Returns false without querying when there is
--- nothing to read, when `node` is already querying, or when no database
--- module handles its connection.
---@param state neotree.State
---@param node NuiTree.Node
---@param reads dbtree.ResultRead[]
---@param on_done fun(answers: dbtree.Answered[])
---@return boolean
local function query(state, node, reads, on_done)
  local connection_record = node.extra.connection
  local scheme = databases.of(connection_record.url)
  if not scheme then
    show_failure(
      state,
      node,
      ("cannot browse %s, only %s"):format(connection_record.url, table.concat(databases.supported_schemes(), ", "))
    )
    return false
  end

  local id = node:get_id()
  if #reads == 0 or fetching.has(id) then
    return false
  end
  fetching.add(id, state)

  local answers = {}
  for _, read in ipairs(reads) do
    client.run(results.request(scheme, connection_record, read), function(result, err)
      table.insert(answers, { read = read, result = result, err = err })
      if #answers < #reads then
        return
      end
      fetching.remove(id)
      on_done(answers)
    end)
  end
  return true
end

--- Queries `reads` and stores the results. When the last one arrives, it shows
--- the children of whatever node then has `node`'s id, which is a new node if
--- the tree was rebuilt in the meantime. It shows an error only when that node
--- has none of its results cached.
---@param state neotree.State
---@param node NuiTree.Node
---@param reads dbtree.ResultRead[]
local function fetch_and_show(state, node, reads)
  local id = node:get_id()
  local started = query(state, node, reads, function(answers)
    local first_error
    for _, answer in ipairs(answers) do
      if answer.result then
        results.store(node.extra.connection, answer.read, answer.result)
      else
        first_error = first_error or answer.err
      end
    end

    local current_node = state.tree and state.tree:get_node(id)
    if not current_node then
      return
    end
    if #results.uncached(current_node) == #results.read_by(current_node) then
      if not first_error then
        -- Another node dropped these results while the queries ran, as a
        -- role's Grants folder does when a saved result is unreadable.
        return M.expand(state, current_node)
      end
      return show_failure(state, current_node, first_error)
    end
    if first_error then
      log.warn("neo-tree database: " .. first_error)
    end
    show_children(state, current_node)
  end)

  -- Expanding now shows the loading placeholder while the queries run.
  if started and node:has_children() and not node:is_expanded() then
    node:expand()
    renderer.redraw(state)
  end
end

--- Queries `reads` again while the results already held stay shown. Each
--- result that changed replaces the old one, and the children of `node` are
--- shown again. A failure leaves the old result in place.
---@param state neotree.State
---@param node NuiTree.Node
---@param reads dbtree.ResultRead[]
local function read_again(state, node, reads)
  local id = node:get_id()
  query(state, node, reads, function(answers)
    local changed = false
    for _, answer in ipairs(answers) do
      if not answer.result then
        log.warn("neo-tree database: could not refresh " .. node.name .. ": " .. first_line(answer.err or ""))
      elseif results.changed(answer.read, answer.result) then
        results.store(node.extra.connection, answer.read, answer.result)
        changed = true
      end
    end

    local current_node = state.tree and state.tree:get_node(id)
    if not (changed and current_node) then
      return
    end
    if current_node:is_expanded() then
      show_children(state, current_node)
    else
      -- Its children were built from the old result, so expanding it again
      -- builds them anew.
      current_node.loaded = false
    end
  end)
end

--- Returns whether `node` can expand. A sequence, function or return node with
--- nothing to show is built as a leaf, so its type alone does not decide this.
---@param node NuiTree.Node
---@return boolean
function M.is_container(node)
  return CHILDREN_BY_TYPE[node.type] ~= nil and node:has_children()
end

--- Shows the children of `node`, building them from the results in memory or
--- on disk, and querying the database for any result in neither. With
--- `auto_refresh` set, results shown from disk are queried again in the
--- background.
---@param state neotree.State
---@param node NuiTree.Node
function M.expand(state, node)
  if not CHILDREN_BY_TYPE[node.type] then
    return
  end

  local loaded = results.load_saved(node)
  local missing = results.uncached(node)
  local refreshed = state.auto_refresh and loaded or {}
  if #missing > 0 then
    -- One query at a time can run for a node, so it reads the saved results
    -- again along with the missing ones.
    return fetch_and_show(state, node, vim.list_extend(missing, refreshed))
  end

  local built, children = pcall(children_of, node)
  if not built then
    if #loaded == 0 then
      error(children, 0)
    end
    -- A result saved by another version of the tree can lack what the
    -- builders read, so it is read again from the database.
    results.forget(node)
    return fetch_and_show(state, node, results.read_by(node))
  end
  renderer.show_nodes(keep_open(state, children), state, node:get_id())
  if #refreshed > 0 then
    read_again(state, node, refreshed)
  end
end

--- Finds the nearest node at or above `node` that is built from results, and
--- queries those results again. The old results stay until the new ones
--- arrive, and stay when the query fails. Returns false when no such node
--- exists.
---@param state neotree.StateWithTree
---@param node NuiTree.Node|nil
---@return boolean
function M.refresh(state, node)
  while node and not (node.extra and node.extra.connection and #results.read_by(node) > 0) do
    local parent_id = node:get_parent_id()
    node = parent_id and state.tree:get_node(parent_id) or nil
  end
  if not node then
    return false
  end

  if fetching.has(node:get_id()) then
    vim.notify("neo-tree database: " .. node.name .. " is already loading")
    return true
  end

  results.load_saved(node)
  if #results.uncached(node) == #results.read_by(node) then
    node.loaded = false
    M.expand(state, node)
    return true
  end
  read_again(state, node, results.reread_by(node))
  return true
end

return M
