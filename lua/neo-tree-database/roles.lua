--- Builds the tree items for the roles on a server and the grants each role holds.

local grants = require("neo-tree-database.grants")
local items = require("neo-tree-database.items")

local M = {}

---@class dbtree.Role
---@field name string
---@field attributes string[] Each as CREATE ROLE spells it, such as `LOGIN`.
---@field member_of string[]
---@field members string[]

---@class dbtree.ListedCatalog
---@field name string
---@field size integer|nil Bytes on disk, nil when the database cannot report it.

---@class dbtree.Server
---@field catalogs dbtree.ListedCatalog[]
---@field roles dbtree.Role[]|nil Nil when the database has no roles.

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
    items.container(node.id .. "/@roles", "Roles", "folder", {
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
  return items.container(node.id .. "/" .. items.segment(role.name), role.name, "role", {
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
    items.container(node.id .. "/@public", "PUBLIC", "public", {
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
  return items.container(node.id .. "/@" .. folder, label, "folder", vim.tbl_extend("force", {
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
  if #roles.catalogs > 0 then
    local documents = {}
    for _, catalog in ipairs(roles.catalogs) do
      table.insert(
        documents,
        items.catalog_document(node.extra.connection, catalog.name, roles.catalog_url(node.extra.url, catalog.name))
      )
    end
    table.insert(result, folder_item(node, "role_grants", "Grants", { documents = documents }))
  end
  return result
end

--- Returns the databases in a role's Grants folder where the role holds
--- something. A database whose document could not be read is listed too, so
--- expanding it queries the database again and shows the error.
---@param node dbtree.Item|NuiTree.Node
---@param cached_document fun(id: string): dbtree.Catalog|nil
---@return dbtree.Item[]
function M.grant_catalogs(node, cached_document)
  local extra = node.extra
  local result = {}
  for _, document in ipairs(extra.documents) do
    local catalog = cached_document(document.id)
    if not catalog or #grants.held_rows(document.catalog, catalog, extra.grantee) > 0 then
      table.insert(
        result,
        items.container(node.id .. "/" .. items.segment(document.catalog), document.catalog, "grant_catalog", {
          kind = "grant_catalog",
          connection = extra.connection,
          catalog = document.catalog,
          url = document.url,
          grantee = extra.grantee,
          documents = { document },
        })
      )
    end
  end
  if #result == 0 then
    return items.message(node.id, "no grants")
  end
  return result
end

return M
