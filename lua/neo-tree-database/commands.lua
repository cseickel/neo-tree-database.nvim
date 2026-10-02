--[[
What the keys do.

Only the commands named here exist for this source. The shared commands that
create, rename, delete and move files are deliberately not among them, because
every one of them reads a path that a database node does not have.

Opening is owned here rather than taken from the shared `open`, because that one
hands a node back to its source only when the node's type is `directory`, and
these nodes carry what they are as their type.
]]

local cc = require("neo-tree.sources.common.commands")
local renderer = require("neo-tree.ui.renderer")

local ddl = require("neo-tree-database.ddl")
local focus = require("neo-tree-database.focus")
local popup = require("neo-tree-database.popup")
local quote = require("neo-tree-database.quote")
local scratch = require("neo-tree-database.scratch")
local schemes = require("neo-tree-database.schemes")
local source = require("neo-tree-database")

local M = {}

--- The node types that answer by asking the database. Refreshing anything below
--- one of these would rebuild it from the same held document and show the same
--- thing again, so a refresh walks up to here first.
local FETCHES = { connection = true, catalog = true }

---@param state neotree.StateWithTree
---@return NuiTree.Node|nil
local function current(state)
  local node = state.tree:get_node()
  if node and node.extra then
    return node
  end
  return nil
end

---@param node NuiTree.Node
---@return dbtree.Quoting
local function quoting_for(node)
  local scheme = schemes.of(node.extra.url)
  return scheme and scheme.quoting or quote.ANSI
end

---@param spec dbtree.Scratch
local function hand_off(spec)
  local configured = source.config.open_scratch
  if type(configured) == "function" then
    return configured(spec)
  end
  return scratch.open(spec)
end

---Expands or collapses the node under the cursor.
---
---Collapsing is tried before loading, so a node showing why it could not load
---still closes. Opening it again is what asks the database a second time.
---@param state neotree.StateWithTree
M.open = function(state)
  local node = current(state)
  if not node then
    return
  end

  if node:is_expanded() then
    node:collapse()
    return renderer.redraw(state)
  end

  if not node.loaded and source.is_container(node) then
    return source.expand(state, node)
  end

  if node:has_children() then
    node:expand()
    renderer.redraw(state)
  end
end

-- Neo-tree binds `<space>` to `toggle_node` for every source, and its shared
-- implementation expands a node without loading it, which here would reveal the
-- placeholder child instead of the children.
M.toggle_node = M.open

---Rebuilds the tree from the connection list, keeping what the databases have
---already answered.
---@param state neotree.StateWithTree
M.refresh = function(state)
  source.navigate(state)
end

---Asks the database again for whatever holds the node under the cursor.
---@param state neotree.StateWithTree
M.refresh_node = function(state)
  local node = state.tree:get_node()
  while node and not FETCHES[node.type] do
    local parent_id = node:get_parent_id()
    node = parent_id and state.tree:get_node(parent_id) or nil
  end

  if not node then
    return vim.notify("neo-tree database: nothing here to refresh", vim.log.levels.WARN)
  end
  source.refresh_node(state, node)
end

local UNQUALIFIED = { column = true, index = true, constraint = true }

--- The node types that name something in the database. The root, a heading, a
--- placeholder and an error message name nothing, and copying their label would
--- put the word `Databases` or the text of an error in the clipboard.
local NAMED = {
  catalog = true,
  schema = true,
  table = true,
  view = true,
  materialized_view = true,
  column = true,
  index = true,
  constraint = true,
}

--- What the node under the cursor is called in sql. A column, an index and a
--- constraint are named on their own, because that is the form they are typed
--- in. Everything larger is qualified by what holds it.
---@param node NuiTree.Node
---@return string|nil
local function sql_name(node)
  if not NAMED[node.type] then
    return nil
  end

  local extra = node.extra
  local quoting = quoting_for(node)

  if UNQUALIFIED[node.type] then
    return extra.record.name
  end
  if extra.relation then
    return quote.qualified(extra.schema, extra.relation, quoting)
  end
  if extra.schema then
    return quote.identifier(extra.schema, quoting)
  end
  return quote.identifier(extra.catalog, quoting)
end

---@param state neotree.StateWithTree
M.yank_name = function(state)
  local node = current(state)
  if not node then
    return
  end

  local name = sql_name(node)
  if not name then
    return vim.notify("neo-tree database: nothing here to name", vim.log.levels.WARN)
  end
  vim.fn.setreg('"', name, "c")
  vim.fn.setreg("+", name, "c")
  vim.fn.setreg("*", name, "c")
  vim.notify("neo-tree database: copied " .. name)
end

local DESCRIBED = { table = true, view = true, materialized_view = true, column = true }

--- What to tell the user for each reason db-query's describe gives as a code.
--- Its other reasons are already sentences.
---@type table<string, fun(node: NuiTree.Node): string>
local UNDESCRIBED = {
  ["reading"] = function(node)
    return ("db-query is still reading the catalog of %s. Try again in a moment."):format(focus.db_name(node))
  end,
  ["no catalog"] = function(node)
    return ("db-query could not read the catalog of %s. Run :DBRefreshCatalog to try again."):format(
      focus.db_name(node)
    )
  end,
  ["not found"] = function(node)
    return ("db-query's catalog of %s has no %s. If it was created after the catalog was read, run :DBRefreshCatalog."):format(
      focus.db_name(node),
      node.name
    )
  end,
}

--- Shows db-query's hover for the relation or column under the cursor.
---
--- db-query reads a database's catalog the first time it is asked about it, so
--- the first describe of a database finds nothing and starts that read.
---@param state neotree.StateWithTree
M.describe = function(state)
  local node = current(state)
  if not node or not DESCRIBED[node.type] then
    return vim.notify("neo-tree database: nothing here to describe", vim.log.levels.WARN)
  end

  local scheme = schemes.of(node.extra.url)
  if not scheme then
    return vim.notify("neo-tree database: cannot describe " .. node.extra.url, vim.log.levels.WARN)
  end

  local extra = node.extra
  local lines, err = require("db-query").describe({
    url = extra.url,
    relation = scheme.catalog_name(extra.catalog, extra.schema, extra.relation),
    column = node.type == "column" and extra.record.name or nil,
  })
  if not lines then
    local explain = UNDESCRIBED[err]
    return vim.notify("neo-tree database: " .. (explain and explain(node) or err), vim.log.levels.WARN)
  end
  vim.lsp.util.open_floating_preview(lines, "markdown", { focus_id = "neo-tree-database-describe" })
end

--- Shows what `build` writes for the node under the cursor, and opens it in a
--- buffer if the user asks for it there. Nothing is run either way.
---@param state neotree.StateWithTree
---@param build fun(node: NuiTree.Node): dbtree.Statement|nil, string|nil
local function show_statement(state, build)
  local node = current(state)
  if not node then
    return
  end

  local statement, err = build(node)
  if not statement then
    return vim.notify("neo-tree database: " .. err, vim.log.levels.WARN)
  end

  popup.show(statement, function(lines)
    hand_off({
      state = state,
      url = node.extra.url,
      lines = lines,
      title = statement.title,
    })
  end)
end

---@param state neotree.StateWithTree
M.object_info = function(state)
  show_statement(state, ddl.info)
end

---@param state neotree.StateWithTree
M.object_drop = function(state)
  show_statement(state, ddl.drop)
end

---@param state neotree.StateWithTree
M.object_change = function(state)
  show_statement(state, ddl.change)
end

---Opens a select against whatever relation the cursor is on or inside.
---@param state neotree.StateWithTree
M.open_scratch = function(state)
  local node = current(state)
  if not node or not node.extra.relation then
    return vim.notify("neo-tree database: not inside a table or view", vim.log.levels.WARN)
  end

  local name = quote.qualified(node.extra.schema, node.extra.relation, quoting_for(node))
  hand_off({
    state = state,
    url = node.extra.url,
    title = node.extra.schema .. "." .. node.extra.relation,
    lines = { "select *", "from " .. name, "limit 100;" },
  })
end

-- The shared commands that move around the tree and its window behave the same
-- here as anywhere. The ones that write to a filesystem are left out.
for _, name in ipairs({
  "cancel",
  "close_all_nodes",
  "close_all_subnodes",
  "close_node",
  "close_window",
  "next_source",
  "prev_source",
  "show_help",
  "toggle_auto_expand_width",
}) do
  M[name] = cc[name]
end

return M
