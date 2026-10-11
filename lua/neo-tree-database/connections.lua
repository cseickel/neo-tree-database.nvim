--- Lists the connections that the tree starts from.

local M = {}

---@class dbtree.Connection
---@field name string
---@field url string

--- Returns the path of the connections file that vim-dadbod-ui reads.
---@return string
local function connections_path()
  local save_location = vim.g.db_ui_save_location or "~/.local/share/db_ui"
  return vim.fn.expand(save_location) .. "/connections.json"
end

--- Appends to `into` each entry of `entries` that has a string `name` and a
--- string `url`.
---@param into dbtree.Connection[]
---@param entries table
local function append_valid(into, entries)
  for _, entry in ipairs(entries) do
    if type(entry) == "table" and type(entry.name) == "string" and type(entry.url) == "string" then
      table.insert(into, { name = entry.name, url = entry.url })
    end
  end
end

---@return dbtree.Connection[] connections
---@return string|nil err
local function from_connections_file()
  local path = connections_path()
  if vim.fn.filereadable(path) == 0 then
    return {}, nil
  end

  local was_read, lines = pcall(vim.fn.readfile, path)
  if not was_read then
    return {}, "could not read " .. path
  end

  local decoded, entries = pcall(vim.json.decode, table.concat(lines, "\n"))
  if not decoded or type(entries) ~= "table" then
    return {}, path .. " does not hold a json list of connections"
  end

  local connections = {}
  append_valid(connections, entries)
  return connections, nil
end

--- Returns the connections in `g:dbs`, which vim-dadbod accepts either as a list
--- of `{ name, url }` entries or as a table of name to url.
---@return dbtree.Connection[]
local function from_g_dbs()
  local dbs = vim.g.dbs
  if type(dbs) ~= "table" then
    return {}
  end

  local connections = {}
  if dbs[1] ~= nil then
    append_valid(connections, dbs)
  else
    for name, url in pairs(dbs) do
      if type(name) == "string" and type(url) == "string" then
        table.insert(connections, { name = name, url = url })
      end
    end
    table.sort(connections, function(left, right)
      return left.name < right.name
    end)
  end
  return connections
end

--- Returns the connections in `configured` when it is set, as a list or as a
--- function that returns one. Otherwise returns the connections file's entries,
--- followed by each `g:dbs` entry whose name the file does not already use.
---@param configured dbtree.Connection[]|fun(): dbtree.Connection[]|nil
---@return dbtree.Connection[] connections
---@return string|nil err
function M.list(configured)
  if configured ~= nil then
    if type(configured) == "function" then
      local succeeded, returned = pcall(configured)
      if not succeeded then
        return {}, "connections function failed: " .. tostring(returned)
      end
      configured = returned
    end

    if type(configured) ~= "table" then
      return {}, "connections is a " .. type(configured) .. ", not a list of connections"
    end

    local connections = {}
    append_valid(connections, configured)
    if #connections == 0 then
      return {}, "connections held no entry with both a name and a url"
    end
    return connections, nil
  end

  local connections, err = from_connections_file()
  if err then
    return {}, err
  end

  local used_names = {}
  for _, connection in ipairs(connections) do
    used_names[connection.name] = true
  end
  for _, connection in ipairs(from_g_dbs()) do
    if not used_names[connection.name] then
      used_names[connection.name] = true
      table.insert(connections, connection)
    end
  end

  return connections, nil
end

return M
