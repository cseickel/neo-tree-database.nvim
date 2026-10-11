--- Builds the sql that creates, drops, or changes the object a node stands for.

local schemes = require("neo-tree-database.schemes")

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
for _, name in ipairs({ "relations", "routines", "access" }) do
  local ddl_module = require("neo-tree-database.ddl." .. name)
  for action, builders_by_type in pairs(ddl_module) do
    for node_type, build in pairs(builders_by_type) do
      BUILDERS[action][node_type] = build
    end
  end
end

---@param action "info"|"drop"|"change"
---@param node NuiTree.Node
---@return dbtree.Statement|nil statement
---@return string|nil err
local function build_statement(action, node)
  local build = BUILDERS[action][node.type]
  if not build then
    return nil, "nothing to write for " .. node.type
  end

  local scheme = schemes.of(node.extra.url)
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
