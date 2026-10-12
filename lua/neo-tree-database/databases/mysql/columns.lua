--- Builds a mysql column from the row information_schema.columns gives it.

local quote = require("neo-tree-database.shared.quote")
local rows = require("neo-tree-database.databases.mysql.rows")

local M = {}

--- Returns the text after `ON UPDATE` in a column's `extra`, such as
--- `CURRENT_TIMESTAMP`, or nil when it has none.
---@param extra string
---@return string|nil
local function on_update(extra)
  local start = extra:lower():find("on update ", 1, true)
  return start and extra:sub(start + #"on update ") or nil
end

---@param extra string
---@return string|nil
local function generated(extra)
  local upper = extra:upper()
  if upper:find("VIRTUAL GENERATED", 1, true) then
    return "VIRTUAL"
  end
  if upper:find("STORED GENERATED", 1, true) or upper:find("PERSISTENT GENERATED", 1, true) then
    return "STORED"
  end
  return nil
end

--- Returns whether `default` reads as a value in a DEFAULT clause without
--- parentheses: a string, a number, a bit or hex literal, or a function call.
---@param default string
---@return boolean
local function is_plain_value(default)
  return default:match("^'") ~= nil
    or tonumber(default) ~= nil
    or default:match("^[bBxX]'") ~= nil
    or default:match("^[%w_]+%(.*%)$") ~= nil
    or default:upper():match("^CURRENT_TIMESTAMP") ~= nil
end

--- Returns a column's default as sql. mariadb writes it as sql already, and the
--- text NULL for no default. mysql writes a string's value unquoted, and marks an
--- expression with DEFAULT_GENERATED in `extra`.
---@param server dbtree.MysqlServer
---@param row table
---@return string|nil
local function default_sql(server, row)
  local default = row.default
  if default == nil or (server == "mariadb" and default == "NULL") then
    return nil
  end
  local is_expression = server == "mariadb" or (row.extra or ""):upper():find("DEFAULT_GENERATED", 1, true)
  if not is_expression then
    if (row.type or ""):match("^bit") and default:match("^b'") then
      return default
    end
    return quote.literal(default, quote.MYSQL)
  end
  default = rows.expression(server, default)
  if is_plain_value(default) then
    return default
  end
  return "(" .. default .. ")"
end

---@class dbtree.MysqlColumnSpec
---@field server dbtree.MysqlServer
---@field row table
---@field grants dbtree.Grant[]
---@field table_collation string|nil

---@param spec dbtree.MysqlColumnSpec
---@return dbtree.Column
function M.column(spec)
  local row = spec.row
  local extra = row.extra or ""
  local generation = generated(extra)
  local options = {}
  if extra:lower():find("auto_increment", 1, true) then
    table.insert(options, "AUTO_INCREMENT")
  end
  local update = on_update(extra)
  if update then
    table.insert(options, "ON UPDATE " .. update)
  end
  if extra:upper():find("INVISIBLE", 1, true) then
    table.insert(options, "INVISIBLE")
  end
  if row.comment and row.comment ~= "" then
    table.insert(options, "COMMENT " .. quote.literal(row.comment, quote.MYSQL))
  end
  return {
    name = row.name,
    type = row.type,
    collation = row.collation ~= spec.table_collation and row.collation or nil,
    nullable = row.nullable == "YES",
    default = generation and rows.expression(spec.server, row.generation) or default_sql(spec.server, row),
    generated = generation,
    options = #options > 0 and options or nil,
    position = row.position,
    grants = spec.grants,
  }
end

return M
