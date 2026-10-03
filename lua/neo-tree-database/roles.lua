--[[
The roles on a server, as tree items.

A role belongs to the whole server, so the Roles folder sits under the
connection beside the catalogs, and is built from the same answer that lists
them. A role opens onto the roles it is a member of, the roles that are members
of it, and its grants in each database it holds any in. A role under Member of or Members opens
the same way, so a chain of memberships is read in place. Postgres refuses a
circular membership, so the nesting always ends.

The roles postgres predefines, named `pg_*`, are left out of the list and still
shown where a role is a member of one. PUBLIC is not a role, but every role
holds what is granted to it, so it is listed with its grants alone.
]]

local grants = require("neo-tree-database.grants")
local items = require("neo-tree-database.items")

local M = {}

---@class dbtree.Role
---@field name string
---@field attributes string[] Each as CREATE ROLE spells it, such as `LOGIN`.
---@field member_of string[]
---@field members string[]

---@class dbtree.Server
---@field catalogs string[]
---@field roles dbtree.Role[]|nil Nil where the database has no roles.

---@class dbtree.Roles What every node under Roles carries.
---@field by_name table<string, dbtree.Role>
---@field catalogs string[]
---@field catalog_url fun(connection: string, catalog: string): string

--- The Roles folder under the connection `node`, or nothing where `server`
--- has no roles.
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

--- The roles in the Roles folder `node`, then PUBLIC.
---@param node dbtree.Item|NuiTree.Node
---@return dbtree.Item[]
function M.listed(node)
  local result = {}
  for _, role in ipairs(node.extra.record) do
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

--- The roles named in a Member of or Members folder.
---@param node dbtree.Item|NuiTree.Node
---@return dbtree.Item[]
function M.named(node)
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

--- What a role or PUBLIC opens onto. PUBLIC has no memberships.
---
--- The Grants folder is built from every database's document, because which
--- databases the role holds anything in is known only once each has been read.
---@param node dbtree.Item|NuiTree.Node
---@return dbtree.Item[]
function M.parts(node)
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
        items.catalog_document(node.extra.connection, catalog, roles.catalog_url(node.extra.url, catalog))
      )
    end
    table.insert(result, folder_item(node, "role_grants", "Grants", { documents = documents }))
  end
  return result
end

--- The databases in a role's Grants folder that the role holds something in.
---
--- A database whose document could not be read is listed too, because whether
--- the role holds anything there is not known. Opening it asks again, and shows
--- why it failed.
---@param node dbtree.Item|NuiTree.Node
---@param read fun(id: string): dbtree.Catalog|nil
---@return dbtree.Item[]
function M.catalogs(node, read)
  local extra = node.extra
  local result = {}
  for _, document in ipairs(extra.documents) do
    local held = read(document.id)
    if not held or #grants.held_rows(document.catalog, held, extra.grantee) > 0 then
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
