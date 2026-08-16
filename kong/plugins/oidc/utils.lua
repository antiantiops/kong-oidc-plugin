local cjson = require("cjson")

local M = {}

local function parseFilters(csvFilters)
  local filters = {}
  if csvFilters then
    for pattern in string.gmatch(csvFilters, "[^,]+") do
      table.insert(filters, pattern)
    end
  end
  return filters
end

function M.get_redirect_uri_path(ngx)
  local function drop_query()
    local uri = ngx.var.request_uri
    local x = uri:find("?")
    if x then
      return uri:sub(1, x - 1)
    else
      return uri
    end
  end

  local function tackle_slash(path)
    local args = kong.request.get_query()
    if args and args.code then
      return path
    elseif path == "/" then
      return "/cb"
    elseif path:sub(-1) == "/" then
      return path:sub(1, -2)
    else
      return path .. "/"
    end
  end

  return tackle_slash(drop_query())
end

function M.get_options(config, ngx)
  return {
    client_id = config.client_id,
    client_secret = config.client_secret,
    discovery = config.discovery,
    introspection_endpoint = config.introspection_endpoint,
    timeout = config.timeout,
    introspection_endpoint_auth_method = config.introspection_endpoint_auth_method,
    bearer_only = config.bearer_only,
    realm = config.realm,
    redirect_uri_path = config.redirect_uri_path or M.get_redirect_uri_path(ngx),
    scope = config.scope,
    response_type = config.response_type,
    ssl_verify = config.ssl_verify,
    token_endpoint_auth_method = config.token_endpoint_auth_method,
    recovery_page_path = config.recovery_page_path,
    filters = parseFilters(config.filters),
    logout_path = config.logout_path,
    redirect_after_logout_uri = config.redirect_after_logout_uri,
    email_whitelist = config.email_whitelist,
  }
end

function M.exit(httpStatusCode, message)
  kong.response.exit(httpStatusCode, message)
end

function M.injectAccessToken(accessToken)
  kong.service.request.set_header("X-Access-Token", accessToken)
end

function M.injectIDToken(idToken)
  local tokenStr = cjson.encode(idToken)
  kong.service.request.set_header("X-ID-Token", ngx.encode_base64(tokenStr))
end

function M.injectUser(user)
  local tmp_user = user
  tmp_user.id = user.sub
  tmp_user.username = user.preferred_username
  ngx.ctx.authenticated_credential = tmp_user
  local userinfo = cjson.encode(user)
  kong.service.request.set_header("X-Userinfo", ngx.encode_base64(userinfo))
end

function M.has_bearer_access_token()
  local header = kong.request.get_header("Authorization")
  if header and header:find(" ") then
    local divider = header:find(" ")
    if string.lower(header:sub(1, divider - 1)) == "bearer" then
      return true
    end
  end
  return false
end

function M.is_email_allowed(email, whitelist)
  if not whitelist or #whitelist == 0 then
    return true
  end
  if not email or email == "" then
    return false
  end
  local lower_email = string.lower(email)
  for _, item in ipairs(whitelist) do
    if string.lower(item) == lower_email then
      return true
    end
  end
  return false
end

return M
