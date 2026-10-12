--- Builds a mysql table's indexes and constraints from the rows that describe
--- them.

local quote = require("neo-tree-database.shared.quote")
local rows = require("neo-tree-database.databases.mysql.rows")

local M = {}

---@class dbtree.MysqlKeyRows The rows that describe one table's indexes and constraints.
---@field server dbtree.MysqlServer
---@field catalog string
---@field table_name string
---@field index_parts table<string, table[]> Each index's parts, in `seq_in_index` order.
---@field constraints table[]
---@field key_columns table<string, table[]> Each constraint's key columns, in order.
---@field references table<string, table[]> Each foreign key's update and delete rules.
---@field checks table<string, table[]> Each check's clause.

---@param name string
---@return string
local function identifier(name)
  return quote.identifier(name, quote.MYSQL)
end

---@param keys dbtree.MysqlKeyRows
---@return string
local function table_name(keys)
  return quote.qualified(keys.catalog, keys.table_name, quote.MYSQL)
end

--- Returns the parenthesized parts of an index as a CREATE INDEX lists them,
--- with each prefix length and descending order.
---@param keys dbtree.MysqlKeyRows
---@param parts table[]
---@return string
local function parts_sql(keys, parts)
  return "(" .. table.concat(vim.tbl_map(function(part)
    local text = part.column and identifier(part.column)
      or ("(" .. rows.expression(keys.server, part.expression or "") .. ")")
    if part.sub_part then
      text = text .. "(" .. part.sub_part .. ")"
    end
    if rows.is_true(part.descending) then
      text = text .. " DESC"
    end
    return text
  end, parts), ", ") .. ")"
end

---@param names string[]
---@return string
local function column_list(names)
  return "(" .. table.concat(vim.tbl_map(identifier, names), ", ") .. ")"
end

---@param rule string|nil
---@param action string
---@return string
local function rule_clause(rule, action)
  if not rule or rule == "RESTRICT" or rule == "NO ACTION" then
    return ""
  end
  return " ON " .. action .. " " .. rule
end

--- Returns a constraint's definition. A primary key or a unique key is read
--- from the index behind it, which keeps prefix lengths and expressions that
--- key_column_usage leaves out. mysql names the index behind a primary key
--- PRIMARY.
---@param keys dbtree.MysqlKeyRows
---@param row table
---@return string|nil
local function constraint_definition(keys, row)
  if row.type == "PRIMARY KEY" or row.type == "UNIQUE" then
    local parts = keys.index_parts[row.type == "PRIMARY KEY" and "PRIMARY" or row.name]
    return parts and (row.type .. " " .. parts_sql(keys, parts)) or nil
  end
  if row.type == "FOREIGN KEY" then
    local key_columns = keys.key_columns[row.name] or {}
    local first = key_columns[1]
    if not first then
      return nil
    end
    local reference = (keys.references[row.name] or {})[1] or {}
    return "FOREIGN KEY "
      .. column_list(vim.tbl_map(function(key)
        return key.column
      end, key_columns))
      .. " REFERENCES "
      .. quote.qualified(first.referenced_schema, first.referenced_table, quote.MYSQL)
      .. " "
      .. column_list(vim.tbl_map(function(key)
        return key.referenced_column
      end, key_columns))
      .. rule_clause(reference.delete_rule, "DELETE")
      .. rule_clause(reference.update_rule, "UPDATE")
  end
  local check = (keys.checks[row.name] or {})[1]
  if row.type == "CHECK" and check then
    return "CHECK (" .. rows.expression(keys.server, check.clause) .. ")"
  end
  return nil
end

---@param keys dbtree.MysqlKeyRows
---@return dbtree.Constraint[]
function M.constraints(keys)
  return vim.tbl_map(function(row)
    return { name = row.name, type = row.type, definition = constraint_definition(keys, row) }
  end, keys.constraints)
end

--- Returns the table's indexes, sorted by name. mysql creates the index behind
--- every key and foreign key itself, so those count as owned by their
--- constraint.
---@param keys dbtree.MysqlKeyRows
---@return dbtree.Index[]
function M.indexes(keys)
  local constraint_names = {}
  for _, constraint in ipairs(keys.constraints) do
    if constraint.type ~= "CHECK" then
      constraint_names[constraint.name] = true
    end
  end

  local result = {}
  for name, parts in pairs(keys.index_parts) do
    local first = parts[1]
    local unique = tonumber(first.non_unique) == 0
    local definition
    if name == "PRIMARY" then
      definition = "ALTER TABLE " .. table_name(keys) .. " ADD PRIMARY KEY " .. parts_sql(keys, parts)
    else
      local special = (first.type == "FULLTEXT" or first.type == "SPATIAL") and (first.type .. " ")
      definition = "CREATE "
        .. (special or (unique and "UNIQUE " or ""))
        .. "INDEX "
        .. identifier(name)
        .. " ON "
        .. table_name(keys)
        .. " "
        .. parts_sql(keys, parts)
    end
    table.insert(result, {
      name = name,
      unique = unique,
      columns = vim.tbl_map(function(part)
        return part.column or rows.expression(keys.server, part.expression or "")
      end, parts),
      definition = definition,
      owned_by_constraint = name == "PRIMARY" or constraint_names[name] == true,
    })
  end
  table.sort(result, rows.by_name)
  return result
end

return M
