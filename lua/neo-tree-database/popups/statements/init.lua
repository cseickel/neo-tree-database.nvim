--- Builds the sql that creates, drops, or changes the object a node stands for.

local databases = require("neo-tree-database.databases")

local M = {}

---@class dbtree.Statement
---@field title string
---@field lines string[]

---@alias dbtree.StatementBuilder fun(node: NuiTree.Node, scheme: dbtree.Scheme): dbtree.Statement|nil, string|nil

---@class dbtree.Statements
---@field info table<string, dbtree.StatementBuilder>
---@field drop table<string, dbtree.StatementBuilder>
---@field change table<string, dbtree.StatementBuilder>

---@type dbtree.Statements
local BUILDERS = { info = {}, drop = {}, change = {} }
for _, name in ipairs({ "relations", "functions", "roles", "grants" }) do
  local statements_module = require("neo-tree-database.popups.statements." .. name)
  for action, builders_by_type in pairs(statements_module) do
    for node_type, build in pairs(builders_by_type) do
      BUILDERS[action][node_type] = build
    end
  end
end

-- A key part of an index carries the index as its record, and shows the
-- index's statements.
local STATEMENT_TYPE = { index_column = "index" }

--- Builds the statement with the database's own builder for `node` when it has
--- one, and with the shared builder otherwise.
---@param action "info"|"drop"|"change"
---@param node NuiTree.Node
---@return dbtree.Statement|nil statement
---@return string|nil err
local function build_statement(action, node)
  local node_type = STATEMENT_TYPE[node.type] or node.type
  local scheme = databases.of(node.extra.url)
  local own_builders = scheme and scheme.statements and scheme.statements[action] or {}
  local build = own_builders[node_type] or BUILDERS[action][node_type]
  if not build then
    return nil, "nothing to write for " .. node.type
  end

  if not scheme then
    return nil, "no statement can be written for " .. node.extra.url
  end

  return build(node, scheme)
end

---@param node NuiTree.Node
---@return dbtree.Statement|nil, string|nil
function M.info(node)
  return build_statement("info", node)
end

---@param node NuiTree.Node
---@return dbtree.Statement|nil, string|nil
function M.drop(node)
  return build_statement("drop", node)
end

---@param node NuiTree.Node
---@return dbtree.Statement|nil, string|nil
function M.change(node)
  return build_statement("change", node)
end

return M
