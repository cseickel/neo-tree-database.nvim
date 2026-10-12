--- Runs a database client and decodes the one json document it prints.

local M = {}

local TIMEOUT_SECONDS = 30
local TIMEOUT_MS = TIMEOUT_SECONDS * 1000

---@class dbtree.Request
---@field argv string[]
---@field fallback dbtree.Fallback|nil

---@class dbtree.Fallback
---@field error string When the failed request's error message contains this text, `request` runs in its place.
---@field request dbtree.Request

--- Runs `request` and calls `on_done` with the decoded document or an error
--- message. When the error message contains the fallback's `error` text, it runs
--- the fallback request and passes on that answer instead. `on_done` always runs
--- on a later tick of the main loop.
---@param request dbtree.Request
---@param on_done fun(document: table|nil, err: string|nil)
function M.run(request, on_done)
  local started, spawn_error = pcall(vim.system, request.argv, {
    text = true,
    timeout = TIMEOUT_MS,
  }, vim.schedule_wrap(function(result)
    if result.code ~= 0 then
      local message = vim.trim(result.stderr or "")
      if message == "" then
        -- vim.system kills a client that times out with a signal, and the client
        -- writes nothing to stderr.
        message = (result.signal or 0) ~= 0
            and ("%s did not answer within %ds"):format(request.argv[1], TIMEOUT_SECONDS)
          or ("%s exited %d"):format(request.argv[1], result.code)
      end
      local fallback = request.fallback
      if fallback and message:find(fallback.error, 1, true) then
        return M.run(fallback.request, on_done)
      end
      return on_done(nil, message)
    end

    local stdout = vim.trim(result.stdout or "")
    if stdout == "" then
      return on_done(nil, request.argv[1] .. " returned nothing")
    end

    -- Without luanil, a json null in an object decodes to vim.NIL, which is truthy.
    local decoded, document = pcall(vim.json.decode, stdout, { luanil = { object = true } })
    if not decoded or type(document) ~= "table" then
      return on_done(nil, request.argv[1] .. " returned output that is not a json object")
    end

    on_done(document, nil)
  end))

  -- vim.system throws when the client is not installed.
  if not started then
    local message = tostring(spawn_error)
    vim.schedule(function()
      on_done(nil, message)
    end)
  end
end

return M
