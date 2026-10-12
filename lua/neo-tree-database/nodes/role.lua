--- Builds the Roles folder under a connection, each role, and what a role opens
--- onto.

local base = require("neo-tree-database.nodes.base")
local grant = require("neo-tree-database.nodes.grant")

local M = {}

---@class dbtree.Roles The role lookup that every node under Roles carries.
---@field by_name table<string, dbtree.Role>
---@field catalogs dbtree.ListedCatalog[]
---@field catalog_url fun(connection: string, catalog: string): string

--- Returns the Roles folder under the connection `node`, or an empty list when
--- `server` has no roles.
---@param node dbtree.Item|NuiTree.Node
---@param server dbtree.Server
---@param catalog_url fun(connection: string, catalog: string): string
---@return dbtree.Item[]
function M.folder(node, server, catalog_url)
  if not server.roles then
    return {}
  end

  ---@type dbtree.Roles
  local roles = { by_name = {}, catalogs = server.catalogs, catalog_url = catalog_url }
  for _, role in ipairs(server.roles) do
    roles.by_name[role.name] = role
  end

  return {
    base.container(node.id .. "/@roles", "Roles", "folder", {
      kind = "folder",
      folder = "roles",
      connection = node.extra.connection,
      url = node.extra.url,
      roles = roles,
      record = server.roles,
    }),
  }
end

---@param node dbtree.Item|NuiTree.Node
---@param role dbtree.Role
---@return dbtree.Item
local function role_item(node, role)
  return base.container(node.id .. "/" .. base.segment(role.name), role.name, "role", {
    kind = "role",
    connection = node.extra.connection,
    url = node.extra.url,
    roles = node.extra.roles,
    grantee = role.name,
    record = role,
  })
end

--- Returns the roles in the Roles folder `node`, followed by PUBLIC.
---@param node dbtree.Item|NuiTree.Node
---@return dbtree.Item[]
function M.folder_roles(node)
  local result = {}
  for _, role in ipairs(node.extra.record) do
    -- postgres predefines the roles named `pg_*`.
    if not vim.startswith(role.name, "pg_") then
      table.insert(result, role_item(node, role))
    end
  end
  table.insert(
    result,
    base.container(node.id .. "/@public", "PUBLIC", "public", {
      kind = "public",
      connection = node.extra.connection,
      url = node.extra.url,
      roles = node.extra.roles,
    })
  )
  return result
end

---@param node dbtree.Item|NuiTree.Node
---@return dbtree.Item[]
function M.membership_roles(node)
  local result = {}
  for _, name in ipairs(node.extra.record) do
    table.insert(result, role_item(node, node.extra.roles.by_name[name]))
  end
  return result
end

---@param node dbtree.Item|NuiTree.Node
---@param folder string
---@param label string
---@param fields table
---@return dbtree.Item
local function folder_item(node, folder, label, fields)
  return base.container(node.id .. "/@" .. folder, label, "folder", vim.tbl_extend("force", {
    kind = "folder",
    folder = folder,
    connection = node.extra.connection,
    url = node.extra.url,
    roles = node.extra.roles,
    grantee = node.extra.grantee,
  }, fields))
end

--- Returns the folders that a role or PUBLIC expands to: Member of, Members, and
--- Grants.
---@param node dbtree.Item|NuiTree.Node
---@return dbtree.Item[]
function M.role_children(node)
  local role = node.extra.record
  local roles = node.extra.roles
  local result = {}
  if role and #role.member_of > 0 then
    table.insert(result, folder_item(node, "member_of", "Member of", { record = role.member_of }))
  end
  if role and #role.members > 0 then
    table.insert(result, folder_item(node, "members", "Members", { record = role.members }))
  end
  if #roles.catalogs > 0 and node.extra.connection.features.read_grants then
    table.insert(result, folder_item(node, "role_grants", "Grants", {}))
  end
  return result
end

--- Returns the databases in a role's Grants folder where the role holds
--- something. A database whose result could not be read is listed too, so
--- expanding it queries the database again and shows the error.
---@param node dbtree.Item|NuiTree.Node
---@param cached_result fun(id: string): dbtree.Catalog|nil
---@return dbtree.Item[]
function M.grant_catalogs(node, cached_result)
  local extra = node.extra
  local result = {}
  for _, listed in ipairs(extra.roles.catalogs) do
    local name = listed.name
    local catalog = cached_result(base.catalog_id(extra.connection, name))
    if not catalog or #grant.held_rows(name, catalog, extra.grantee) > 0 then
      table.insert(
        result,
        base.container(node.id .. "/" .. base.segment(name), name, "grant_catalog", {
          kind = "grant_catalog",
          connection = extra.connection,
          catalog = name,
          url = extra.roles.catalog_url(extra.url, name),
          grantee = extra.grantee,
        })
      )
    end
  end
  if #result == 0 then
    return base.message(node.id, "no grants")
  end
  return result
end

return M
