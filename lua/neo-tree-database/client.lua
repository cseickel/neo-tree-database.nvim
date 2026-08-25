--[[
Running a database client.

Every query this plugin sends returns one row holding one json document, and
every client is asked to print that value raw: no header, no alignment, no
quoting. So stdout is the document, and a client's table layout never has to be
parsed back apart.
]]

local M = {}

local TIMEOUT_SECONDS = 30
local TIMEOUT_MS = TIMEOUT_SECONDS * 1000

---@class dbtree.Request
---@field argv string[]

--- Runs `request` and hands back the decoded document, or a message naming what
--- went wrong.
---
--- `on_done` always runs, always on a later tick, and always on the main loop,
--- so a caller may set up whatever the callback will change after calling this
--- and know the callback has not run yet.
---
--- Nulls in an object are dropped rather than decoded, so a column with no
--- default has no `default` key at all. Decoding them would produce `vim.NIL`,
--- which is not nil and passes every `if value then` reading these documents.
--- Nulls in an array are left alone, because dropping those renumbers the array
--- and loses elements rather than keys.
---@param request dbtree.Request
---@param on_done fun(document: table|nil, err: string|nil)
function M.run(request, on_done)
  local started, outcome = pcall(vim.system, request.argv, {
    text = true,
    timeout = TIMEOUT_MS,
  }, vim.schedule_wrap(function(result)
    if result.code ~= 0 then
      local message = vim.trim(result.stderr or "")
      if message == "" then
        -- A timeout kills the client with a signal and says nothing, so the
        -- only sign of one is a client that failed having written no reason.
        message = (result.signal or 0) ~= 0
            and ("%s did not answer within %ds"):format(request.argv[1], TIMEOUT_SECONDS)
          or ("%s exited %d"):format(request.argv[1], result.code)
      end
      return on_done(nil, message)
    end

    local text = vim.trim(result.stdout or "")
    if text == "" then
      return on_done(nil, request.argv[1] .. " returned nothing")
    end

    local decoded, document = pcall(vim.json.decode, text, { luanil = { object = true } })
    if not decoded or type(document) ~= "table" then
      return on_done(nil, request.argv[1] .. " returned output that is not a json object")
    end

    on_done(document, nil)
  end))

  -- vim.system throws rather than returning an error when the client is not
  -- installed, which is the first thing a new connection hits.
  if not started then
    local message = tostring(outcome)
    vim.schedule(function()
      on_done(nil, message)
    end)
  end
end

return M
