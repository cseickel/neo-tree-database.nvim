--- Builds the connection nodes and the database nodes under each connection.

local base = require("neo-tree-database.nodes.base")

local M = {}

---@param connections dbtree.Connection[]
---@return dbtree.Item[]
function M.connections(connections)
  local connection_items = {}
  for _, connection in ipairs(connections) do
    local id = base.connection_id(connection)
    table.insert(
      connection_items,
      base.container(id, connection.name, "connection", {
        kind = "connection",
        connection = connection,
        url = connection.url,
      })
    )
  end
  return connection_items
end

---@param node dbtree.Item|NuiTree.Node
---@param catalogs dbtree.ListedCatalog[]
---@param catalog_url fun(connection: string, catalog: string): string
---@return dbtree.Item[]
function M.catalogs(node, catalogs, catalog_url)
  local parent = node.extra
  local result = {}
  for _, catalog in ipairs(catalogs) do
    local name = catalog.name
    table.insert(
      result,
      base.container(base.catalog_id(parent.connection, name), name, "catalog", {
        kind = "catalog",
        connection = parent.connection,
        catalog = name,
        url = catalog_url(parent.url, name),
        record = catalog,
      })
    )
  end
  return result
end

return M
