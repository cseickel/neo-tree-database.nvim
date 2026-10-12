--- Groups and reads the json rows that the mysql queries print.

local M = {}

---@param rows table[]
---@return table<string, table[]>
function M.by_tag(rows)
  local tagged = {}
  for _, row in ipairs(rows) do
    tagged[row.t] = tagged[row.t] or {}
    table.insert(tagged[row.t], row)
  end
  return tagged
end

--- Returns `rows` grouped by the value each holds under `key`, in the order of
--- the rows.
---@param rows table[]|nil
---@param key string
---@return table<string, table[]>
function M.group_by(rows, key)
  local groups = {}
  for _, row in ipairs(rows or {}) do
    local value = row[key]
    groups[value] = groups[value] or {}
    table.insert(groups[value], row)
  end
  return groups
end

--- Returns `rows` grouped by their `table`, and each table's rows grouped by
--- `key`.
---@param rows table[]|nil
---@param key string
---@return table<string, table<string, table[]>>
function M.group_by_table(rows, key)
  local result = {}
  for table_name, table_rows in pairs(M.group_by(rows, "table")) do
    result[table_name] = M.group_by(table_rows, key)
  end
  return result
end

--- Returns whether `value` is true as mysql writes a comparison into json,
--- which is the number 1.
---@param value any
---@return boolean
function M.is_true(value)
  return value == true or value == 1
end

---@param a { name: string }
---@param b { name: string }
---@return boolean
function M.by_name(a, b)
  return a.name < b.name
end

--- Returns an expression that information_schema holds, as sql. mysql escapes
--- the quotes and backslashes inside a stored expression, as in
--- `_utf8mb4\'x\'`, and mariadb stores it as written.
---@param server dbtree.MysqlServer
---@param text string
---@return string
function M.expression(server, text)
  if server == "mariadb" then
    return text
  end
  return (text:gsub("\\(['\"\\])", "%1"))
end

return M
