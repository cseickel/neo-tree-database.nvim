--- Writes the CREATE statements of a duckdb relation and its columns.

local quote = require("neo-tree-database.shared.quote")

local M = {}

--- Returns `column` as it reads in a CREATE TABLE or after ADD COLUMN.
---@param column dbtree.Column
---@return string
function M.column_definition(column)
  local definition = quote.identifier(column.name, quote.ANSI) .. " " .. (column.type or "")
  if column.default then
    definition = definition .. " DEFAULT " .. column.default
  end
  if not column.nullable then
    definition = definition .. " NOT NULL"
  end
  return definition
end

--- Returns the statements that created `relation` and its indexes, as duckdb
--- keeps them.
---@param relation dbtree.Relation
---@param schema string
---@return string[]
function M.ddl(relation, schema)
  local lines = {}
  if relation.definition then
    vim.list_extend(lines, vim.split(relation.definition, "\n", { plain = true }))
  end
  for _, index in ipairs(relation.indexes or {}) do
    if index.definition then
      table.insert(lines, "")
      vim.list_extend(lines, vim.split(index.definition, "\n", { plain = true }))
    end
  end
  return lines
end

return M
