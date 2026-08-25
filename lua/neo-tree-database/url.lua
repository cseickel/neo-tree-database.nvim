--[[
Connection urls.

A url written for vim-dadbod names a server and a database at once, and this
tree browses every database on a server, so the job this module exists for is
producing the url of a sibling database from the url the user wrote down.

That job is done by substring surgery rather than by parsing into parts and
formatting them back, because everything the user wrote past the database name,
their query parameters and their encoding of them, has to survive untouched.
For the same reason this stays three functions and never becomes a url parser.
Anything needing a host, a port or a password should call vim-dadbod's
`db#url#parse`, which has no such round trip to preserve.
]]

local M = {}

--- The in-memory database, which several schemes spell this way and which is a
--- name rather than a path.
M.MEMORY = ":memory:"

--- The scheme of `url`, lowercased, empty when it has none.
---@param url string
---@return string
function M.scheme(url)
  return (url:match("^(%a[%w+.%-]*):") or ""):lower()
end

--- The file a `scheme:path` url names, empty when it names no file and so means
--- the in-memory database.
---
--- `vim.fs.normalize` resolves `~` and environment variables and nothing else.
--- `vim.fn.expand` would additionally read `*`, `[`, `{`, `%` and `#` as
--- wildcards, and a path holding one of those would come back empty, which
--- reads here as a request for an in-memory database rather than as the error
--- it is.
---@param url string
---@return string
function M.file(url)
  local path = url:gsub("^%a[%w+.%-]*:", ""):gsub("^//", "")
  if path == "" or path == M.MEMORY then
    return ""
  end
  return vim.fs.normalize(path)
end

--- The parts of a `scheme://authority/database?query#fragment` url. Nil for a
--- url that names a file rather than a server, which has no authority to split
--- on and no database to replace.
---@param url string
---@return { scheme: string, authority: string, database: string, suffix: string }|nil
local function hierarchical(url)
  local scheme, authority, tail = url:match("^(%a[%w+.%-]*)://([^/]*)(.*)$")
  if not scheme then
    return nil
  end

  local database, suffix = tail:match("^/([^?#]*)(.*)$")
  if not database then
    database, suffix = "", tail
  end

  return {
    scheme = scheme:lower(),
    authority = authority,
    database = database,
    suffix = suffix,
  }
end

--- `url` with its database replaced by `name`, so one connection reaches every
--- database on its server. Unchanged for a url that names a file, where the
--- file is the database.
---@param url string
---@param name string
---@return string
function M.with_database(url, name)
  local parts = hierarchical(url)
  if not parts then
    return url
  end
  return string.format("%s://%s/%s%s", parts.scheme, parts.authority, name, parts.suffix)
end

return M
