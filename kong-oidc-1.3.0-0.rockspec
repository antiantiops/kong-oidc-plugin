package = "kong-oidc"
version = "1.3.0-0"
source = {
    url = "git://github.com/antiantiops/kong-oidc",
    tag = "v1.3.0",
    dir = "kong-oidc"
}
description = {
    summary = "A Kong plugin for implementing the OpenID Connect Relying Party (RP) functionality",
    detailed = [[
        kong-oidc is a Kong plugin for implementing the OpenID Connect Relying Party.
    ]],
    homepage = "https://github.com/antiantiops/kong-oidc",
    license = "Apache 2.0"
}
dependencies = {
    "lua-resty-openidc >= 1.7.6"
}
build = {
    type = "builtin",
    modules = {
        ["kong.plugins.oidc.filter"] = "kong/plugins/oidc/filter.lua",
        ["kong.plugins.oidc.handler"] = "kong/plugins/oidc/handler.lua",
        ["kong.plugins.oidc.schema"] = "kong/plugins/oidc/schema.lua",
        ["kong.plugins.oidc.session"] = "kong/plugins/oidc/session.lua",
        ["kong.plugins.oidc.utils"] = "kong/plugins/oidc/utils.lua"
    }
}
