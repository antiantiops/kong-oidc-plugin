local M = {}

function M.configure(config)
  if not config.session_secret then
    return nil
  end

  local secret = ngx.decode_base64(config.session_secret)
  if not secret then
    kong.log.err("Invalid plugin configuration, session secret could not be decoded")
    return kong.response.exit(500, { message = "invalid OIDC plugin configuration, session secret could not be decoded" })
  end

  return { secret = secret }
end

return M
