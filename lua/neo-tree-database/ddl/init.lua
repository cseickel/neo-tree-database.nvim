--[[
The statement for an object.

Three questions get asked of whatever the cursor is on: what made it, what
would drop it, and what would change it. All three are answered as sql text and
none of them is run, so `d` on a table produces a DROP statement to read rather
than a dropped table.

A change is a skeleton to edit rather than a finished statement, because what
an ALTER should say is the thing the user is about to decide.

Each module here answers for some node types, keyed by the type.
]]

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
  local module = require("neo-tree-database.ddl." .. name)
  for question, builders in pairs(module) do
    for node_type, build in pairs(builders) do
      BUILDERS[question][node_type] = build
    end
  end
end

---@param question "info"|"drop"|"change"
---@param node NuiTree.Node
---@return dbtree.Statement|nil statement
---@return string|nil err
local function statement(question, node)
  local build = BUILDERS[question][node.type]
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
  return statement("info", node)
end

---@param node NuiTree.Node
---@return dbtree.Statement|nil, string|nil
function M.drop(node)
  return statement("drop", node)
end

---@param node NuiTree.Node
---@return dbtree.Statement|nil, string|nil
function M.change(node)
  return statement("change", node)
end

return M
