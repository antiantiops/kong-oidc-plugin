local M = {}

local function shouldIgnoreRequest(patterns)
  if patterns then
    local uri = kong.request.get_path()
    for _, pattern in ipairs(patterns) do
      if string.find(uri, pattern) then
        return true
      end
    end
  end
  return false
end

function M.shouldProcessRequest(config)
  return not shouldIgnoreRequest(config.filters)
end

return M
