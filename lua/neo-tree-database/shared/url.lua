--- Reads connection urls, and builds the url of another database on the same
--- server.

local M = {}

--- Returns the scheme of `url` in lowercase, or an empty string when it has none.
---@param url string
---@return string
function M.scheme(url)
  return (url:match("^(%a[%w+.%-]*):") or ""):lower()
end

--- Returns the parts of a `scheme://authority/database?query#fragment` url, or
--- nil for a url that names a file.
---@param url string
---@return { scheme: string, authority: string, database: string, suffix: string }|nil
local function split_server_url(url)
  local scheme, authority, after_authority = url:match("^(%a[%w+.%-]*)://([^/]*)(.*)$")
  if not scheme then
    return nil
  end

  local database, suffix = after_authority:match("^/([^?#]*)(.*)$")
  if not database then
    database, suffix = "", after_authority
  end

  return {
    scheme = scheme:lower(),
    authority = authority,
    database = database,
    suffix = suffix,
  }
end

--- Returns `url` without the password in its credentials or in a `password`
--- query parameter. A password may hold `@`, so the credentials end at the
--- authority's last `@`.
---@param url string
---@return string
function M.without_password(url)
  local scheme, authority, rest = url:match("^(%a[%w+.%-]*://)([^/?#]*)(.*)$")
  if scheme then
    local credentials, host = authority:match("^(.*)@([^@]*)$")
    if credentials then
      url = scheme .. credentials:gsub(":.*$", "") .. "@" .. host .. rest
    end
  end
  return (url:gsub("([?&;])password=[^&;#]*", "%1"))
end

--- Returns `url` with its database replaced by `name`. A url that names a file
--- comes back unchanged.
---@param url string
---@param name string
---@return string
function M.with_database(url, name)
  local parts = split_server_url(url)
  if not parts then
    return url
  end
  return string.format("%s://%s/%s%s", parts.scheme, parts.authority, name, parts.suffix)
end

return M
