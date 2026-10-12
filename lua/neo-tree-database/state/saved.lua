--- Saves query results to disk, so a later session can show them without
--- reading the database first.

local url = require("neo-tree-database.shared.url")

local log = require("neo-tree.log")

local M = {}

-- The files list every table and column, so only the user may read them.
local DIRECTORY_MODE = tonumber("700", 8)
local FILE_MODE = tonumber("600", 8)

-- Raise this whenever a result's shape changes, so that results saved in the
-- old shape are never read.
local FORMAT = 1

--- Returns the directory that holds the results saved for `connection`. It is
--- named for the format, the connection's url without its password, and its
--- features, because they change what a result holds.
---@param connection dbtree.Connection
---@return string
local function directory_of(connection)
  local identity = { "format " .. FORMAT, url.without_password(connection.url) }
  local feature_names = vim.tbl_keys(connection.features)
  table.sort(feature_names)
  for _, name in ipairs(feature_names) do
    table.insert(identity, name .. "=" .. tostring(connection.features[name]))
  end
  return vim.fs.joinpath(vim.fn.stdpath("cache"), "neo-tree-database", vim.fn.sha256(table.concat(identity, "\n")))
end

--- Returns the file that holds the result for `catalog`, or for the
--- connection's database list when `catalog` is nil.
---@param connection dbtree.Connection
---@param catalog string|nil
---@return string
local function file_of(connection, catalog)
  return vim.fs.joinpath(directory_of(connection), vim.fn.sha256(catalog or "") .. ".json")
end

--- Returns the result saved for `catalog` on `connection`, or nil when none is
--- saved or the file cannot be read.
---@param connection dbtree.Connection
---@param catalog string|nil
---@return table|nil
function M.load(connection, catalog)
  local handle = io.open(file_of(connection, catalog), "r")
  if not handle then
    return nil
  end
  local text = handle:read("*a")
  handle:close()
  local decoded, result = pcall(vim.json.decode, text, { luanil = { object = true } })
  if not decoded or type(result) ~= "table" then
    return nil
  end
  return result
end

---@param connection dbtree.Connection
---@param catalog string|nil
---@param result table
function M.save(connection, catalog, result)
  local path = file_of(connection, catalog)
  vim.fn.mkdir(vim.fs.dirname(path), "p", DIRECTORY_MODE)
  local file, err = vim.uv.fs_open(path, "w", FILE_MODE)
  if not file then
    return log.warn("neo-tree database: could not save to " .. path .. ": " .. tostring(err))
  end
  vim.uv.fs_write(file, vim.json.encode(result))
  vim.uv.fs_close(file)
end

--- Deletes the result saved for `catalog` on `connection`, or every result
--- saved for `connection` when `catalog` is nil.
---@param connection dbtree.Connection
---@param catalog string|nil
function M.forget(connection, catalog)
  if catalog then
    os.remove(file_of(connection, catalog))
  else
    vim.fn.delete(directory_of(connection), "rf")
  end
end

return M
