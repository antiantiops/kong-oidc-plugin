local utils = require("kong.plugins.oidc.utils")
local filter = require("kong.plugins.oidc.filter")
local session = require("kong.plugins.oidc.session")

local OidcHandler = {
  PRIORITY = 1000,
  VERSION = "1.3.2",
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

local function make_oidc(oidcConfig, sessionOpts)
  kong.log.debug("OidcHandler calling authenticate, requested path: ", ngx.var.request_uri)
  local res, err = require("resty.openidc").authenticate(oidcConfig, nil, nil, sessionOpts)
  if err then
    if oidcConfig.recovery_page_path then
      kong.log.debug("Entering recovery page: ", oidcConfig.recovery_page_path)
      return kong.response.exit(302, nil, { ["Location"] = oidcConfig.recovery_page_path })
    end
    return utils.exit(500, { message = err })
  end
  return res
end

local function verify_email_whitelist(oidcConfig, user)
  if not oidcConfig.email_whitelist or #oidcConfig.email_whitelist == 0 then
    return true
  end
  local email = user and (user.email or user.preferred_username)
  if not utils.is_email_allowed(email, oidcConfig.email_whitelist) then
    kong.log.warn("OidcHandler: Forbidden email: ", email or "nil")
    return utils.exit(403, { message = "Forbidden: email is not allowed" })
  end
  return true
end

local function handle(oidcConfig, sessionOpts)
  local response
  if oidcConfig.introspection_endpoint then
    response = introspect(oidcConfig)
    if response then
      verify_email_whitelist(oidcConfig, response)
      utils.injectUser(response)
    end
  end

  if response == nil then
    response = make_oidc(oidcConfig, sessionOpts)
    if response then
      if response.user then
        verify_email_whitelist(oidcConfig, response.user)
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
    local sessionOpts = session.configure(config)
    handle(oidcConfig, sessionOpts)
  else
    kong.log.debug("OidcHandler ignoring request, path: ", ngx.var.request_uri)
  end

  kong.log.debug("OidcHandler done")
end

return OidcHandler
