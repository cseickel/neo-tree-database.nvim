--- Runs a request's statement through db-query and decodes what it prints.

local M = {}

---@class dbtree.Request
---@field url string
---@field statement string
---@field decode fun(output: string): table Builds the result from what the statement printed, and throws when the output is not what it prints.
---@field fallback dbtree.Fallback|nil

---@class dbtree.Fallback
---@field error string When the failed request's error message contains this text, `request` runs in its place.
---@field request dbtree.Request

---@param output string
---@return table
function M.json_object(output)
  local text = vim.trim(output)
  if text == "" then
    error("the query printed nothing", 0)
  end
  -- Without luanil, a json null in an object decodes to vim.NIL, which is truthy.
  local decoded, result = pcall(vim.json.decode, text, { luanil = { object = true } })
  if not decoded or type(result) ~= "table" then
    error("the query printed something other than a json object", 0)
  end
  return result
end

--- Returns the json objects in `output`, which holds one per line.
---@param output string
---@return table[]
function M.json_rows(output)
  local rows = {}
  for line in output:gmatch("[^\n]+") do
    local decoded, row = pcall(vim.json.decode, line, { luanil = { object = true } })
    if not decoded or type(row) ~= "table" then
      error("the query printed a line that is not a json object: " .. line, 0)
    end
    table.insert(rows, row)
  end
  return rows
end

--- Runs `request` and calls `on_done`, on a later tick of the main loop, with its
--- result or an error message. When the error message contains the fallback's
--- `error` text, it runs the fallback request and passes on that result instead.
---@param request dbtree.Request
---@param on_done fun(result: table|nil, err: string|nil)
function M.run(request, on_done)
  local loaded, db_query = pcall(require, "db-query")
  if not loaded then
    return vim.schedule(function()
      on_done(nil, "the tree runs its queries through db-query.nvim, which is not installed")
    end)
  end
  db_query.read({ url = request.url, statement = request.statement }, function(output, err)
    if not output then
      local message = err or "the query failed"
      local fallback = request.fallback
      if fallback and message:find(fallback.error, 1, true) then
        return M.run(fallback.request, on_done)
      end
      return on_done(nil, message)
    end

    local decoded, result = pcall(request.decode, output)
    if not decoded then
      return on_done(nil, tostring(result))
    end
    on_done(result, nil)
  end)
end

return M
