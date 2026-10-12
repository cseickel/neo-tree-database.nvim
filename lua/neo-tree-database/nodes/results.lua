--- Finds the query results a node is built from, and keeps them in memory and on
--- disk.

local base = require("neo-tree-database.nodes.base")
local catalogs = require("neo-tree-database.state.catalogs")
local saved = require("neo-tree-database.state.saved")

local M = {}

---@class dbtree.ResultRead A result that a node is built from.
---@field key string The key it is cached under in memory.
---@field catalog string|nil The catalog it describes, nil for the connection's database list.

--- Returns the key that the result for `catalog` is cached under, or the key of
--- the connection's database list when `catalog` is nil.
---@param connection dbtree.Connection
---@param catalog string|nil
---@return string
local function key_of(connection, catalog)
  if catalog then
    return base.catalog_id(connection, catalog)
  end
  return base.connection_id(connection)
end

--- Returns the catalogs whose results `node` is built from. A node not listed
--- here is built from the connection's database list, or from the record its
--- parent passed down.
---@param node dbtree.Item|NuiTree.Node
---@return string[]
local function catalogs_read_by(node)
  local extra = node.extra
  if node.type == "catalog" or node.type == "grant_catalog" then
    return { extra.catalog }
  end
  if node.type == "folder" and extra.folder == "role_grants" then
    return vim.tbl_map(function(listed)
      return listed.name
    end, extra.roles.catalogs)
  end
  return {}
end

--- Returns the results `node` is built from, which is none for a node built
--- from its parent's record.
---@param node dbtree.Item|NuiTree.Node
---@return dbtree.ResultRead[]
function M.read_by(node)
  local connection = node.extra.connection
  if node.type == "connection" then
    return { { key = key_of(connection, nil) } }
  end
  return vim.tbl_map(function(catalog)
    return { key = key_of(connection, catalog), catalog = catalog }
  end, catalogs_read_by(node))
end

--- Returns the result a connection, database or role database node is built
--- from, which has to be cached.
---@param node dbtree.Item|NuiTree.Node
---@return table
function M.of(node)
  local extra = node.extra
  return assert(catalogs.get(key_of(extra.connection, extra.catalog)), "built before its result was read")
end

--- Returns the results that refreshing `node` reads again: its own, and for a
--- connection also each database result it has cached.
---@param node dbtree.Item|NuiTree.Node
---@return dbtree.ResultRead[]
function M.reread_by(node)
  local reads = M.read_by(node)
  if node.type ~= "connection" then
    return reads
  end
  local connection = node.extra.connection
  local server = catalogs.get(reads[1].key)
  for _, listed in ipairs(server and server.catalogs or {}) do
    local key = key_of(connection, listed.name)
    if catalogs.get(key) then
      table.insert(reads, { key = key, catalog = listed.name })
    end
  end
  return reads
end

---@param node dbtree.Item|NuiTree.Node
---@return dbtree.ResultRead[]
function M.uncached(node)
  return vim.tbl_filter(function(read)
    return not catalogs.get(read.key)
  end, M.read_by(node))
end

--- Caches each result of `node` that is not cached yet and is saved on disk.
--- Returns the ones it loaded.
---@param node dbtree.Item|NuiTree.Node
---@return dbtree.ResultRead[]
function M.load_saved(node)
  local connection = node.extra.connection
  local loaded = {}
  for _, read in ipairs(M.uncached(node)) do
    local result = saved.load(connection, read.catalog)
    if result then
      catalogs.put(read.key, result)
      table.insert(loaded, read)
    end
  end
  return loaded
end

---@param scheme dbtree.Scheme
---@param connection dbtree.Connection
---@param read dbtree.ResultRead
---@return dbtree.Request
function M.request(scheme, connection, read)
  local features = connection.features
  if read.catalog then
    return scheme.introspect(scheme.catalog_url(connection.url, read.catalog), read.catalog, features)
  end
  return scheme.catalogs(connection.url, features)
end

---@param server dbtree.Server
---@param catalog string
---@return boolean
local function lists(server, catalog)
  return vim.iter(server.catalogs or {}):any(function(listed)
    return listed.name == catalog
  end)
end

--- Drops the result of each database that `old_server` lists and `new_server`
--- does not, from memory and disk.
---@param connection dbtree.Connection
---@param old_server dbtree.Server
---@param new_server dbtree.Server
local function drop_unlisted(connection, old_server, new_server)
  for _, catalog in ipairs(old_server.catalogs or {}) do
    if not lists(new_server, catalog.name) then
      catalogs.drop(key_of(connection, catalog.name))
      saved.forget(connection, catalog.name)
    end
  end
end

--- Caches `result` and saves it to disk. A new database list also drops the
--- results of the databases it no longer lists, and a result for a database the
--- current list leaves out is not kept, whichever of the two arrives first.
---@param connection dbtree.Connection
---@param read dbtree.ResultRead
---@param result table
function M.store(connection, read, result)
  local server = catalogs.get(key_of(connection, nil))
  if read.catalog and server and not lists(server, read.catalog) then
    return
  end
  if not read.catalog and server then
    drop_unlisted(connection, server, result)
  end
  catalogs.put(read.key, result)
  saved.save(connection, read.catalog, result)
end

--- Returns whether `result` differs from the one cached for `read`.
---@param read dbtree.ResultRead
---@param result table
---@return boolean
function M.changed(read, result)
  return not vim.deep_equal(catalogs.get(read.key), result)
end

--- Drops the results of `node` from memory and disk. Dropping a connection's
--- database list drops every result of the connection.
---@param node dbtree.Item|NuiTree.Node
function M.forget(node)
  local connection = node.extra.connection
  for _, read in ipairs(M.read_by(node)) do
    catalogs.drop(read.key)
    saved.forget(connection, read.catalog)
  end
end

return M
