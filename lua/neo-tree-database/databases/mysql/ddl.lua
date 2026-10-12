--- Writes the CREATE statements of a mysql relation and its columns.

local quote = require("neo-tree-database.shared.quote")

local M = {}

--- Returns `column` as it reads in a CREATE TABLE or after ADD COLUMN.
---@param column dbtree.Column
---@return string
function M.column_definition(column)
  local parts = { quote.identifier(column.name, quote.MYSQL), column.type or "" }
  -- mariadb reads COLLATE only as part of the type.
  if column.collation then
    table.insert(parts, "COLLATE " .. column.collation)
  end
  if column.generated then
    table.insert(parts, "GENERATED ALWAYS AS (" .. (column.default or "") .. ") " .. column.generated)
  end
  if not column.nullable then
    table.insert(parts, "NOT NULL")
  end
  if column.default and not column.generated then
    table.insert(parts, "DEFAULT " .. column.default)
  end
  vim.list_extend(parts, column.options or {})
  return table.concat(parts, " ")
end

--- Returns `constraint` as it reads in a CREATE TABLE. mysql names every
--- primary key PRIMARY, so a primary key is written without a name.
---@param constraint dbtree.Constraint
---@return string
function M.constraint_clause(constraint)
  if constraint.type == "PRIMARY KEY" then
    return constraint.definition
  end
  return "CONSTRAINT " .. quote.identifier(constraint.name, quote.MYSQL) .. " " .. constraint.definition
end

--- Returns the statements that create `relation`. A view comes back as its
--- stored definition. A table is rebuilt from its columns, constraints and
--- indexes, because information_schema keeps no CREATE TABLE text.
---@param relation dbtree.Relation
---@param schema string
---@return string[]
function M.ddl(relation, schema)
  if relation.definition then
    return vim.split(relation.definition, "\n", { plain = true })
  end

  local table_elements = {}
  for _, column in ipairs(relation.columns or {}) do
    table.insert(table_elements, M.column_definition(column))
  end
  for _, constraint in ipairs(relation.constraints or {}) do
    if constraint.definition then
      table.insert(table_elements, M.constraint_clause(constraint))
    end
  end

  local lines = { "CREATE TABLE " .. quote.qualified(schema, relation.name, quote.MYSQL) .. " (" }
  for position, element in ipairs(table_elements) do
    table.insert(lines, "    " .. element .. (position < #table_elements and "," or ""))
  end
  table.insert(lines, ");")

  for _, index in ipairs(relation.indexes or {}) do
    -- mysql creates the index behind each key and foreign key of the table.
    if index.definition and not index.owned_by_constraint then
      table.insert(lines, "")
      table.insert(lines, index.definition .. ";")
    end
  end

  return lines
end

return M
