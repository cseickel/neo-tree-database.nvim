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
local items = require("neo-tree-database.items")
local popup = require("neo-tree-database.popup")
local quote = require("neo-tree-database.quote")
local scratch = require("neo-tree-database.scratch")
local schemes = require("neo-tree-database.schemes")
local source = require("neo-tree-database")

local M = {}

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
---
---Only a node with `documents` asks the database. Refreshing anything below
---one would rebuild it from the same held documents and show the same thing
---again, so a refresh walks up to one first.
---@param state neotree.StateWithTree
M.refresh_node = function(state)
  local node = state.tree:get_node()
  while node and not (node.extra and node.extra.documents) do
    local parent_id = node:get_parent_id()
    node = parent_id and state.tree:get_node(parent_id) or nil
  end

  if not node then
    return vim.notify("neo-tree database: nothing here to refresh", vim.log.levels.WARN)
  end
  source.refresh_node(state, node)
end

---@param extra table
---@return string
local function own_name(extra)
  return extra.record.name
end

---@param extra table
---@param quoting dbtree.Quoting
---@return string
local function relation_name(extra, quoting)
  return quote.qualified(extra.schema, extra.relation, quoting)
end

--- What each node type is called in sql. A column, an index and a constraint
--- are named on their own, because that is the form they are typed in.
--- Everything a schema holds is qualified by it, and a function also carries
--- its argument types, which tell it apart from its overloads.
---
--- The root, a heading, a placeholder, an error message and a grant name
--- nothing, and copying their label would put the word `Databases` or the text
--- of an error in the clipboard.
---@type table<string, fun(extra: table, quoting: dbtree.Quoting): string>
local SQL_NAMES = {
  catalog = function(extra, quoting)
    return quote.identifier(extra.catalog, quoting)
  end,
  schema = function(extra, quoting)
    return quote.identifier(extra.schema, quoting)
  end,
  table = relation_name,
  view = relation_name,
  materialized_view = relation_name,
  column = own_name,
  index = own_name,
  constraint = own_name,
  sequence = function(extra, quoting)
    return quote.qualified(extra.schema, extra.record.name, quoting)
  end,
  routine = function(extra, quoting)
    return items.signature(quote.qualified(extra.schema, extra.record.name, quoting), extra.record.arguments)
  end,
  role = function(extra, quoting)
    return quote.identifier(extra.record.name, quoting)
  end,
}

--- What the node under the cursor is called in sql.
---@param node NuiTree.Node
---@return string|nil
local function sql_name(node)
  local name = SQL_NAMES[node.type]
  if not name then
    return nil
  end
  return name(node.extra, quoting_for(node))
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

--- Shows db-query's description of the relation or column under the cursor.
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

  local title = node.type == "column" and (extra.relation .. "." .. extra.record.name)
    or (extra.schema .. "." .. extra.relation)
  popup.show({ title = title, lines = lines, language = "markdown" })
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

  popup.show({
    title = statement.title,
    lines = statement.lines,
    language = "sql",
    on_open = function(lines)
      hand_off({
        state = state,
        url = node.extra.url,
        lines = lines,
        title = statement.title,
      })
    end,
  })
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
