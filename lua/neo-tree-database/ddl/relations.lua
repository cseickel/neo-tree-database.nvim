--- Builds the statements for a schema, a relation, and a relation's columns,
--- indexes and constraints.

local quote = require("neo-tree-database.quote")

---@type dbtree.Statements
local M = { info = {}, drop = {}, change = {} }

local RELATION_KEYWORD = {
  table = "TABLE",
  view = "VIEW",
  materialized_view = "MATERIALIZED VIEW",
}

---@param node NuiTree.Node
---@param quoting dbtree.Quoting
---@return string
local function relation_name(node, quoting)
  return quote.qualified(node.extra.schema, node.extra.relation, quoting)
end

M.info.schema = function(node, scheme)
  return {
    title = "Schema " .. node.extra.schema,
    lines = { "CREATE SCHEMA " .. quote.identifier(node.extra.schema, scheme.quoting) .. ";" },
  }
end

M.info.column = function(node, scheme)
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

M.info.index = function(node)
  local index = node.extra.record
  local definition = index.definition
  if not definition then
    return { title = index.name, lines = { "-- " .. index.name .. " has no definition" } }
  end
  return { title = index.name, lines = vim.split(definition, "\n", { plain = true }) }
end

M.info.constraint = function(node, scheme)
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

M.info.table = relation_info
M.info.view = relation_info
M.info.materialized_view = relation_info

M.drop.schema = function(node, scheme)
  return {
    title = "Drop schema " .. node.extra.schema,
    lines = { "DROP SCHEMA " .. quote.identifier(node.extra.schema, scheme.quoting) .. ";" },
  }
end

M.drop.column = function(node, scheme)
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

M.drop.index = function(node, scheme)
  return {
    title = "Drop " .. node.extra.record.name,
    lines = {
      "DROP INDEX "
        .. quote.qualified(node.extra.schema, node.extra.record.name, scheme.quoting)
        .. ";",
    },
  }
end

M.drop.constraint = function(node, scheme)
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
        .. RELATION_KEYWORD[node.type]
        .. " "
        .. relation_name(node, scheme.quoting)
        .. ";",
    },
  }
end

M.drop.table = relation_drop
M.drop.view = relation_drop
M.drop.materialized_view = relation_drop

M.change.schema = function(node, scheme)
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

M.change.column = function(node, scheme)
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

M.change.index = function(node, scheme)
  local index_name = node.extra.record.name
  return {
    title = "Alter " .. index_name,
    lines = {
      "ALTER INDEX "
        .. quote.qualified(node.extra.schema, index_name, scheme.quoting)
        .. " RENAME TO "
        .. quote.identifier(index_name, scheme.quoting)
        .. ";",
    },
  }
end

M.change.constraint = function(node, scheme)
  local constraint = node.extra.record
  local table_name = relation_name(node, scheme.quoting)
  local constraint_name = quote.identifier(constraint.name, scheme.quoting)

  -- Neither postgres nor duckdb can change a constraint's definition in place.
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
  local qualified_name = relation_name(node, scheme.quoting)
  local keyword = RELATION_KEYWORD[node.type]
  return {
    title = "Alter " .. node.extra.schema .. "." .. node.extra.relation,
    lines = {
      -- postgres rejects a schema-qualified name after RENAME TO.
      "ALTER "
        .. keyword
        .. " "
        .. qualified_name
        .. " RENAME TO "
        .. quote.identifier(node.extra.relation, scheme.quoting)
        .. ";",
      "ALTER "
        .. keyword
        .. " "
        .. qualified_name
        .. " SET SCHEMA "
        .. quote.identifier(node.extra.schema, scheme.quoting)
        .. ";",
    },
  }
end

M.change.table = relation_change
M.change.view = relation_change
M.change.materialized_view = relation_change

return M
