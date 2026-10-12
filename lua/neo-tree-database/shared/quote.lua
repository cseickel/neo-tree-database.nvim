--- Quotes names and text so that they can go into sql.

local M = {}

---@class dbtree.Quoting
---@field identifier string The character an identifier is wrapped in.
---@field backslash_escapes boolean Whether a backslash in a string literal escapes the character after it.

---@type dbtree.Quoting
M.ANSI = { identifier = '"', backslash_escapes = false }

---@type dbtree.Quoting
M.MYSQL = { identifier = "`", backslash_escapes = true }

---@param text string
---@param quoting dbtree.Quoting
---@return string
function M.literal(text, quoting)
  if quoting.backslash_escapes then
    text = text:gsub("\\", "\\\\")
  end
  return "'" .. text:gsub("'", "''") .. "'"
end

---@param name string
---@param quoting dbtree.Quoting
---@return string
function M.identifier(name, quoting)
  local quote_char = quoting.identifier
  return quote_char .. name:gsub(quote_char, quote_char .. quote_char) .. quote_char
end

---@param schema string
---@param relation string
---@param quoting dbtree.Quoting
---@return string
function M.qualified(schema, relation, quoting)
  return M.identifier(schema, quoting) .. "." .. M.identifier(relation, quoting)
end

--- Returns `name(arguments)`, or `name` alone when `arguments` is nil.
---@param name string
---@param arguments string|nil
---@return string
function M.signature(name, arguments)
  if arguments then
    return name .. "(" .. arguments .. ")"
  end
  return name
end

--- Returns `template` with each `@name` replaced by `values[name]`.
---@param template string
---@param values table<string, string>
---@return string
function M.render(template, values)
  -- A function replacement keeps gsub from reading `%` in a value as a capture
  -- reference.
  return (template:gsub("@(%w+)", function(key)
    local value = values[key]
    if value == nil then
      error("no value for @" .. key .. " in sql template")
    end
    return value
  end))
end

return M
