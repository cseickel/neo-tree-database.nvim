--[[
Putting a name into sql.

Schema and relation names come from the database, go into the tree, and come
back out into the text of the next query, so this module is the one place where
a name can carry something the parser will act on. Every name reaching sql goes
through here.

The rules differ by database, and a scheme module states its own rather than
this module knowing their names.
]]

local M = {}

---@class dbtree.Quoting
---@field identifier string The character an identifier is wrapped in.

---@type dbtree.Quoting
M.ANSI = { identifier = '"' }

--- `text` as a string literal.
---
--- A backslash is a plain character to both databases here. MySQL reads one as
--- an escape unless the server is in NO_BACKSLASH_ESCAPES mode, so a scheme
--- module for it has to say so and this has to grow a rule for it.
---@param text string
---@return string
function M.literal(text)
  return "'" .. text:gsub("'", "''") .. "'"
end

--- `name` as an identifier.
---@param name string
---@param quoting dbtree.Quoting
---@return string
function M.identifier(name, quoting)
  local char = quoting.identifier
  return char .. name:gsub(char, char .. char) .. char
end

--- `schema`.`relation`, quoted for `quoting`.
---@param schema string
---@param relation string
---@param quoting dbtree.Quoting
---@return string
function M.qualified(schema, relation, quoting)
  return M.identifier(schema, quoting) .. "." .. M.identifier(relation, quoting)
end

--- `template` with each `@name` replaced by `values[name]`.
---
--- A replacement is produced by a function rather than passed to gsub as a
--- string, because gsub reads `%` in a replacement string as a capture
--- reference and a quoted database name is free to contain one.
---@param template string
---@param values table<string, string>
---@return string
function M.render(template, values)
  return (template:gsub("@(%w+)", function(key)
    local value = values[key]
    if value == nil then
      error("no value for @" .. key .. " in sql template")
    end
    return value
  end))
end

return M
