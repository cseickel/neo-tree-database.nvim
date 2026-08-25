--[[
The statement for an object.

Three questions get asked of whatever the cursor is on: what made it, what
would drop it, and what would change it. All three are answered as sql text and
none of them is run, so `d` on a table produces a DROP statement to read rather
than a dropped table.

A change is a skeleton to edit rather than a finished statement, because what
an ALTER should say is the thing the user is about to decide.
]]

local quote = require("neo-tree-database.quote")
local schemes = require("neo-tree-database.schemes")

local M = {}

---@class dbtree.Statement
---@field title string
---@field lines string[]

local DROP_KEYWORD = {
  table = "TABLE",
  view = "VIEW",
  materialized_view = "MATERIALIZED VIEW",
}

--- The `schema`.`name` of the relation `node` sits on or inside.
---@param node NuiTree.Node
---@param quoting dbtree.Quoting
---@return string
local function relation_name(node, quoting)
  return quote.qualified(node.extra.schema, node.extra.relation, quoting)
end

---@param node NuiTree.Node
---@return dbtree.Scheme|nil scheme
---@return string|nil err
local function scheme_of(node)
  local scheme = schemes.of(node.extra.url)
  if not scheme then
    return nil, "no statement can be written for " .. node.extra.url
  end
  return scheme, nil
end

---@type table<string, fun(node: NuiTree.Node, scheme: dbtree.Scheme): dbtree.Statement>
local INFO = {}

INFO.schema = function(node, scheme)
  return {
    title = "Schema " .. node.extra.schema,
    lines = { "CREATE SCHEMA " .. quote.identifier(node.extra.schema, scheme.quoting) .. ";" },
  }
end

INFO.column = function(node, scheme)
  local column = node.extra.record
  return {
    title = node.extra.relation .. "." .. column.name,
    lines = {
      "ALTER TABLE "
        .. relation_name(node, scheme.quoting)
        .. " ADD COLUMN "
        .. scheme.column_definition(column)
        .. ";",
    },
  }
end

INFO.index = function(node, scheme)
  local index = node.extra.record
  local definition = index.definition
  if not definition then
    return { title = index.name, lines = { "-- " .. index.name .. " has no definition" } }
  end
  return { title = index.name, lines = vim.split(definition, "\n", { plain = true }) }
end

INFO.constraint = function(node, scheme)
  local constraint = node.extra.record
  if not constraint.definition then
    return { title = constraint.name, lines = { "-- " .. constraint.name .. " has no definition" } }
  end
  return {
    title = constraint.name,
    lines = {
      "ALTER TABLE "
        .. relation_name(node, scheme.quoting)
        .. " ADD CONSTRAINT "
        .. quote.identifier(constraint.name, scheme.quoting)
        .. " "
        .. constraint.definition
        .. ";",
    },
  }
end

local function relation_info(node, scheme)
  return {
    title = node.extra.schema .. "." .. node.extra.relation,
    lines = scheme.ddl(node.extra.record, node.extra.schema),
  }
end

INFO.table = relation_info
INFO.view = relation_info
INFO.materialized_view = relation_info

---@type table<string, fun(node: NuiTree.Node, scheme: dbtree.Scheme): dbtree.Statement>
local DROP = {}

DROP.schema = function(node, scheme)
  return {
    title = "Drop schema " .. node.extra.schema,
    lines = { "DROP SCHEMA " .. quote.identifier(node.extra.schema, scheme.quoting) .. ";" },
  }
end

DROP.column = function(node, scheme)
  return {
    title = "Drop " .. node.extra.relation .. "." .. node.extra.record.name,
    lines = {
      "ALTER TABLE "
        .. relation_name(node, scheme.quoting)
        .. " DROP COLUMN "
        .. quote.identifier(node.extra.record.name, scheme.quoting)
        .. ";",
    },
  }
end

DROP.index = function(node, scheme)
  return {
    title = "Drop " .. node.extra.record.name,
    lines = {
      "DROP INDEX "
        .. quote.qualified(node.extra.schema, node.extra.record.name, scheme.quoting)
        .. ";",
    },
  }
end

DROP.constraint = function(node, scheme)
  return {
    title = "Drop " .. node.extra.record.name,
    lines = {
      "ALTER TABLE "
        .. relation_name(node, scheme.quoting)
        .. " DROP CONSTRAINT "
        .. quote.identifier(node.extra.record.name, scheme.quoting)
        .. ";",
    },
  }
end

local function relation_drop(node, scheme)
  return {
    title = "Drop " .. node.extra.schema .. "." .. node.extra.relation,
    lines = {
      "DROP "
        .. DROP_KEYWORD[node.type]
        .. " "
        .. relation_name(node, scheme.quoting)
        .. ";",
    },
  }
end

DROP.table = relation_drop
DROP.view = relation_drop
DROP.materialized_view = relation_drop

---@type table<string, fun(node: NuiTree.Node, scheme: dbtree.Scheme): dbtree.Statement>
local CHANGE = {}

CHANGE.schema = function(node, scheme)
  return {
    title = "Alter schema " .. node.extra.schema,
    lines = {
      "ALTER SCHEMA "
        .. quote.identifier(node.extra.schema, scheme.quoting)
        .. " RENAME TO "
        .. quote.identifier(node.extra.schema, scheme.quoting)
        .. ";",
    },
  }
end

CHANGE.column = function(node, scheme)
  local column = node.extra.record
  local table_name = relation_name(node, scheme.quoting)
  local column_name = quote.identifier(column.name, scheme.quoting)
  return {
    title = "Alter " .. node.extra.relation .. "." .. column.name,
    lines = {
      "ALTER TABLE "
        .. table_name
        .. " ALTER COLUMN "
        .. column_name
        .. " TYPE "
        .. (column.type or "")
        .. ";",
      "ALTER TABLE " .. table_name .. " ALTER COLUMN " .. column_name .. " SET NOT NULL;",
      "ALTER TABLE " .. table_name .. " ALTER COLUMN " .. column_name .. " DROP NOT NULL;",
      "ALTER TABLE " .. table_name .. " RENAME COLUMN " .. column_name .. " TO " .. column_name .. ";",
    },
  }
end

CHANGE.index = function(node, scheme)
  local name = quote.qualified(node.extra.schema, node.extra.record.name, scheme.quoting)
  return {
    title = "Alter " .. node.extra.record.name,
    lines = { "ALTER INDEX " .. name .. " RENAME TO " .. name .. ";" },
  }
end

--- A constraint is not altered in place anywhere this plugin speaks to, so the
--- change is the pair of statements that replaces it.
CHANGE.constraint = function(node, scheme)
  local constraint = node.extra.record
  local table_name = relation_name(node, scheme.quoting)
  local constraint_name = quote.identifier(constraint.name, scheme.quoting)

  local lines = { "ALTER TABLE " .. table_name .. " DROP CONSTRAINT " .. constraint_name .. ";" }
  if constraint.definition then
    table.insert(
      lines,
      "ALTER TABLE "
        .. table_name
        .. " ADD CONSTRAINT "
        .. constraint_name
        .. " "
        .. constraint.definition
        .. ";"
    )
  end

  return { title = "Replace " .. constraint.name, lines = lines }
end

local function relation_change(node, scheme)
  local name = relation_name(node, scheme.quoting)
  local keyword = DROP_KEYWORD[node.type]
  return {
    title = "Alter " .. node.extra.schema .. "." .. node.extra.relation,
    lines = {
      "ALTER " .. keyword .. " " .. name .. " RENAME TO " .. name .. ";",
      "ALTER " .. keyword .. " " .. name .. " SET SCHEMA " .. node.extra.schema .. ";",
    },
  }
end

CHANGE.table = relation_change
CHANGE.view = relation_change
CHANGE.materialized_view = relation_change

---@param table_of table<string, fun(node: NuiTree.Node, scheme: dbtree.Scheme): dbtree.Statement>
---@param node NuiTree.Node
---@return dbtree.Statement|nil statement
---@return string|nil err
local function statement(table_of, node)
  local build = table_of[node.type]
  if not build then
    return nil, "nothing to write for " .. node.type
  end

  local scheme, err = scheme_of(node)
  if not scheme then
    return nil, err
  end

  return build(node, scheme), nil
end

---@param node NuiTree.Node
---@return dbtree.Statement|nil, string|nil
function M.info(node)
  return statement(INFO, node)
end

---@param node NuiTree.Node
---@return dbtree.Statement|nil, string|nil
function M.drop(node)
  return statement(DROP, node)
end

---@param node NuiTree.Node
---@return dbtree.Statement|nil, string|nil
function M.change(node)
  return statement(CHANGE, node)
end

return M
