local utils = require("kong.plugins.oidc.utils")
local filter = require("kong.plugins.oidc.filter")
local session = require("kong.plugins.oidc.session")

local OidcHandler = {
  PRIORITY = 1000,
  VERSION = "1.2.0",
}

local function introspect(oidcConfig)
  if utils.has_bearer_access_token() or oidcConfig.bearer_only == "yes" then
    local res, err = require("resty.openidc").introspect(oidcConfig)
    if err then
      if oidcConfig.bearer_only == "yes" then
        kong.response.set_header("WWW-Authenticate", 'Bearer realm="' .. oidcConfig.realm .. '",error="' .. err .. '"')
        return utils.exit(401, { message = err })
      end
      return nil
    end
    kong.log.debug("OidcHandler introspect succeeded, requested path: ", ngx.var.request_uri)
    return res
  end
  return nil
end

local function make_oidc(oidcConfig)
  kong.log.debug("OidcHandler calling authenticate, requested path: ", ngx.var.request_uri)
  local res, err = require("resty.openidc").authenticate(oidcConfig)
  if err then
    if oidcConfig.recovery_page_path then
      kong.log.debug("Entering recovery page: ", oidcConfig.recovery_page_path)
      return kong.response.exit(302, nil, { ["Location"] = oidcConfig.recovery_page_path })
    end
    return utils.exit(500, { message = err })
  end
  return res
end

local function handle(oidcConfig)
  local response
  if oidcConfig.introspection_endpoint then
    response = introspect(oidcConfig)
    if response then
      utils.injectUser(response)
    end
  end

  if response == nil then
    response = make_oidc(oidcConfig)
    if response then
      if response.user then
        utils.injectUser(response.user)
      end
      if response.access_token then
        utils.injectAccessToken(response.access_token)
      end
      if response.id_token then
        utils.injectIDToken(response.id_token)
      end
    end
  end
end

function OidcHandler:access(config)
  local oidcConfig = utils.get_options(config, ngx)

  if filter.shouldProcessRequest(oidcConfig) then
    session.configure(config)
    handle(oidcConfig)
  else
    kong.log.debug("OidcHandler ignoring request, path: ", ngx.var.request_uri)
  end

  kong.log.debug("OidcHandler done")
end

return OidcHandler
