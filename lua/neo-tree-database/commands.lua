--- Defines the commands that this source's keys run.

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
local function node_under_cursor(state)
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

--- Opens `spec` with the user's `open_scratch` function when one is configured,
--- and in this plugin's scratch buffer otherwise.
---@param spec dbtree.Scratch
local function open_in_scratch(spec)
  local configured = source.config.open_scratch
  if type(configured) == "function" then
    return configured(spec)
  end
  return scratch.open(spec)
end

--- Expands or collapses the node under the cursor, loading its children the
--- first time it expands.
---@param state neotree.StateWithTree
M.open = function(state)
  local node = node_under_cursor(state)
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

-- neo-tree's shared toggle_node expands a node without loading its children.
M.toggle_node = M.open

--- Rebuilds the tree from the connection list and keeps the cached answers.
---@param state neotree.StateWithTree
M.refresh = function(state)
  source.navigate(state)
end

--- Queries the database again for the nearest node at or above the cursor that
--- holds `documents`.
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
  overloaded_routine = function(extra, quoting)
    return quote.qualified(extra.schema, extra.record[1].name, quoting)
  end,
  role = function(extra, quoting)
    return quote.identifier(extra.record.name, quoting)
  end,
}

---@param node NuiTree.Node
---@return string|nil
local function sql_name(node)
  local name_of = SQL_NAMES[node.type]
  if not name_of then
    return nil
  end
  return name_of(node.extra, quoting_for(node))
end

---@param state neotree.StateWithTree
M.yank_name = function(state)
  local node = node_under_cursor(state)
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

local DESCRIBABLE_TYPES = { table = true, view = true, materialized_view = true, column = true }

-- db-query's describe reports these errors as codes and every other error as a
-- sentence.
---@type table<string, fun(node: NuiTree.Node): string>
local DESCRIBE_ERROR_MESSAGES = {
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

---@param state neotree.StateWithTree
M.describe = function(state)
  local node = node_under_cursor(state)
  if not node or not DESCRIBABLE_TYPES[node.type] then
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
    local message_for = DESCRIBE_ERROR_MESSAGES[err]
    return vim.notify("neo-tree database: " .. (message_for and message_for(node) or err), vim.log.levels.WARN)
  end

  local title = node.type == "column" and (extra.relation .. "." .. extra.record.name)
    or (extra.schema .. "." .. extra.relation)
  popup.show({ title = title, lines = lines, language = "markdown" })
end

--- Shows the statement that `build` returns for the node under the cursor in a
--- popup, which can open it in a scratch buffer.
---@param state neotree.StateWithTree
---@param build fun(node: NuiTree.Node): dbtree.Statement|nil, string|nil
local function show_statement(state, build)
  local node = node_under_cursor(state)
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
      open_in_scratch({
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

--- Opens a scratch buffer holding a select from the relation that the cursor is
--- on or inside.
---@param state neotree.StateWithTree
M.open_scratch = function(state)
  local node = node_under_cursor(state)
  if not node or not node.extra.relation then
    return vim.notify("neo-tree database: not inside a table or view", vim.log.levels.WARN)
  end

  local name = quote.qualified(node.extra.schema, node.extra.relation, quoting_for(node))
  open_in_scratch({
    state = state,
    url = node.extra.url,
    title = node.extra.schema .. "." .. node.extra.relation,
    lines = { "select *", "from " .. name, "limit 100;" },
  })
end

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
