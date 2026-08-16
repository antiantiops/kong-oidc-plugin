# Kong OIDC plugin

Maintained fork for Kong Gateway 3.x and 4.x. Uses `lua-resty-openidc 1.9.x` and Kong's bundled `lua-resty-session >= 4.0.3`.

# What is Kong OIDC plugin

[![Join the chat at https://gitter.im/nokia/kong-oidc](https://badges.gitter.im/nokia/kong-oidc.svg)](https://gitter.im/nokia/kong-oidc?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)

**Continuous Integration:** [![Build Status](https://travis-ci.org/nokia/kong-oidc.svg?branch=master)](https://travis-ci.org/nokia/kong-oidc) 
[![Coverage Status](https://coveralls.io/repos/github/nokia/kong-oidc/badge.svg?branch=master)](https://coveralls.io/github/nokia/kong-oidc?branch=master) <br/>

**kong-oidc** is a plugin for [Kong](https://github.com/Mashape/kong) implementing the
[OpenID Connect](http://openid.net/specs/openid-connect-core-1_0.html) Relying Party (RP) functionality.

It authenticates users against an OpenID Connect Provider using
[OpenID Connect Discovery](http://openid.net/specs/openid-connect-discovery-1_0.html)
and the Basic Client Profile (i.e. the Authorization Code flow).

It maintains sessions for authenticated users by leveraging `lua-resty-openidc` thus offering
a configurable choice between storing the session state in a client-side browser cookie or use
in of the server-side storage mechanisms `shared-memory|memcache|redis`.

It supports server-wide caching of resolved Discovery documents and validated Access Tokens.

It can be used as a reverse proxy terminating OAuth/OpenID Connect in front of an origin server so that
the origin server/services can be protected with the relevant standards without implementing those on
the server itself.

Introspection functionality add capability for already authenticated users and/or applications that
already posses acces token to go through kong. The actual token verification is then done by Resource Server.

## How does it work

The diagram below shows the message exchange between the involved parties.

![alt Kong OIDC flow](docs/kong_oidc_flow.png)

The `X-Userinfo` header contains the payload from the Userinfo Endpoint

```
X-Userinfo: {"preferred_username":"alice","id":"60f65308-3510-40ca-83f0-e9c0151cc680","sub":"60f65308-3510-40ca-83f0-e9c0151cc680"}
```

The plugin also sets the `ngx.ctx.authenticated_consumer` variable, which can be using in other Kong plugins:
```
ngx.ctx.authenticated_consumer = {
    id = "60f65308-3510-40ca-83f0-e9c0151cc680",   -- sub field from Userinfo
    username = "alice"                             -- preferred_username from Userinfo
}
```


## Dependencies

**kong-oidc** depends on the following package:

- [`lua-resty-openidc` 1.9.x](https://github.com/zmartzone/lua-resty-openidc/)
- Kong's bundled `lua-resty-session >= 4.0.3`


## Docker Compose installation

Use Kong Gateway image with bundled `lua-resty-session` v4. This complete database-backed example includes PostgreSQL, a one-time migration job, plugin init container, and Kong. The init container installs OpenIDC `1.9.0` and this plugin into a shared read-only volume before Kong starts.

```yaml
services:
  kong-database:
    image: postgres:15-alpine
    environment:
      POSTGRES_USER: kong
      POSTGRES_PASSWORD: change-me
      POSTGRES_DB: kong
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "kong"]
      interval: 10s
      timeout: 5s
      retries: 5
    volumes:
      - kong_data:/var/lib/postgresql/data

  kong-migrations:
    image: kong:3.8
    command: kong migrations bootstrap
    environment: &kong-env
      KONG_DATABASE: postgres
      KONG_PG_HOST: kong-database
      KONG_PG_USER: kong
      KONG_PG_PASSWORD: change-me
      KONG_PG_DATABASE: kong
    depends_on:
      kong-database:
        condition: service_healthy

  kong-plugin-init:
    image: kong:3.8
    user: root
    restart: "no"
    command:
      - sh
      - -c
      - |
        rm -rf /plugins-volume/*
        apt-get update -qq && apt-get install -y -qq curl git
        luarocks install --tree=/plugins-volume --deps-mode=none \
          https://luarocks.org/lua-resty-openidc-1.9.0-1.src.rock
        luarocks install --tree=/plugins-volume --deps-mode=none \
          --only-server=https://luarocks.org/manifests/mrnim94 kong-oidc-plugin
    volumes:
      - kong_plugins:/plugins-volume

  kong:
    image: kong:3.8
    environment:
      <<: *kong-env
      KONG_PLUGINS: bundled,oidc
      KONG_LUA_PACKAGE_PATH: /opt/plugins/share/lua/5.1/?.lua;/opt/plugins/share/lua/5.1/?/init.lua;;
      KONG_LUA_PACKAGE_CPATH: /opt/plugins/lib/lua/5.1/?.so;;
    depends_on:
      kong-migrations:
        condition: service_completed_successfully
      kong-plugin-init:
        condition: service_completed_successfully
    volumes:
      - kong_plugins:/opt/plugins:ro

volumes:
  kong_plugins:
  kong_data:
```

For a new PostgreSQL database, bootstrap Kong once:

```sh
docker compose up -d kong-database
docker compose run --rm kong-migrations
```

After bootstrap, remove `kong-migrations` from `kong.depends_on` (or change it to `kong migrations up` for upgrades). Then deploy or upgrade Kong/plugin:

```sh
docker compose up -d --force-recreate kong-plugin-init
docker compose up -d --force-recreate kong
```

Do not install `lua-resty-session` in `/plugins-volume`: OpenIDC `1.9.x` uses Kong's bundled session v4.

## Configure OIDC

Set `config.session_secret` to a stable base64-encoded random value. Changing it invalidates existing login cookies. For browser redirects, this plugin emits `SameSite=None; Secure`; use HTTPS.

## Usage

### Parameters

| Parameter | Default  | Required | description |
| --- | --- | --- | --- |
| `name` || true | plugin name, has to be `oidc` |
| `config.client_id` || true | OIDC Client ID |
| `config.client_secret` || true | OIDC Client secret |
| `config.discovery` | https://.well-known/openid-configuration | false | OIDC Discovery Endpoint (`/.well-known/openid-configuration`) |
| `config.scope` | openid | false| OAuth2 Token scope. To use OIDC it has to contains the `openid` scope |
| `config.ssl_verify` | false | false | Enable SSL verification to OIDC Provider |
| `config.session_secret` | | false | Additional parameter, which is used to encrypt the session cookie. Needs to be random |
| `config.introspection_endpoint` | | false | Token introspection endpoint |
| `config.timeout` | | false | OIDC endpoint calls timeout |
| `config.introspection_endpoint_auth_method` | client_secret_basic | false | Token introspection auth method. resty-openidc supports `client_secret_(basic|post)` |
| `config.bearer_only` | no | false | Only introspect tokens without redirecting |
| `config.realm` | kong | false | Realm used in WWW-Authenticate response header |
| `config.logout_path` | /logout | false | Absolute path used to logout from the OIDC RP |

### Enabling

To enable the plugin only for one API:

```
POST /apis/<api_id>/plugins/ HTTP/1.1
Host: localhost:8001
Content-Type: application/x-www-form-urlencoded
Cache-Control: no-cache

name=oidc&config.client_id=kong-oidc&config.client_secret=29d98bf7-168c-4874-b8e9-9ba5e7382fa0&config.discovery=https%3A%2F%2F<oidc_provider>%2F.well-known%2Fopenid-configuration
```

To enable the plugin globally:
```
POST /plugins HTTP/1.1
Host: localhost:8001
Content-Type: application/x-www-form-urlencoded
Cache-Control: no-cache

name=oidc&config.client_id=kong-oidc&config.client_secret=29d98bf7-168c-4874-b8e9-9ba5e7382fa0&config.discovery=https%3A%2F%2F<oidc_provider>%2F.well-known%2Fopenid-configuration
```

A successful response:
```
HTTP/1.1 201 Created
Date: Tue, 24 Oct 2017 19:37:38 GMT
Content-Type: application/json; charset=utf-8
Transfer-Encoding: chunked
Connection: keep-alive
Access-Control-Allow-Origin: *
Server: kong/0.11.0

{
    "created_at": 1508871239797,
    "config": {
        "response_type": "code",
        "client_id": "kong-oidc",
        "discovery": "https://<oidc_provider>/.well-known/openid-configuration",
        "scope": "openid",
        "ssl_verify": "no",
        "client_secret": "29d98bf7-168c-4874-b8e9-9ba5e7382fa0",
        "token_endpoint_auth_method": "client_secret_post"
    },
    "id": "58cc119b-e5d0-4908-8929-7d6ed73cb7de",
    "enabled": true,
    "name": "oidc",
    "api_id": "32625081-c712-4c46-b16a-5d6d9081f85f"
}
```

### Upstream API request

The plugin adds a additional `X-Userinfo`, `X-Access-Token` and `X-Id-Token` headers to the upstream request, which can be consumer by upstream server. All of them are base64 encoded:

```
GET / HTTP/1.1
Host: netcat:9000
Connection: keep-alive
X-Forwarded-For: 172.19.0.1
X-Forwarded-Proto: http
X-Forwarded-Host: localhost
X-Forwarded-Port: 8000
X-Real-IP: 172.19.0.1
Cache-Control: max-age=0
User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/61.0.3163.100 Safari/537.36
Upgrade-Insecure-Requests: 1
Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8
Accept-Encoding: gzip, deflate
Accept-Language: pl-PL,pl;q=0.8,en-US;q=0.6,en;q=0.4
Cookie: session=KOn1am4mhQLKazlCA.....
X-Userinfo: eyJnaXZlbl9uYW1lIjoixITEmMWaw5PFgcW7xbnEhiIsInN1YiI6ImM4NThiYzAxLTBiM2ItNDQzNy1hMGVlLWE1ZTY0ODkwMDE5ZCIsInByZWZlcnJlZF91c2VybmFtZSI6ImFkbWluIiwibmFtZSI6IsSExJjFmsOTxYHFu8W5xIYiLCJ1c2VybmFtZSI6ImFkbWluIiwiaWQiOiJjODU4YmMwMS0wYjNiLTQ0MzctYTBlZS1hNWU2NDg5MDAxOWQifQ==
X-Access-Token: eyJhbGciOiJSUzI1NiIsInR5cCIgOiAiSldUIiwia2lkIiA6ICJGenFSY0N1Ry13dzlrQUJBVng1ZG9sT2ZwTFhBNWZiRGFlVDRiemtnSzZRIn0.eyJqdGkiOiIxYjhmYzlkMC1jMjlmLTQwY2ItYWM4OC1kNzMyY2FkODcxY2IiLCJleHAiOjE1NDg1MTA4MjksIm5iZiI6MCwiaWF0IjoxNTQ4NTEwNzY5LCJpc3MiOiJodHRwOi8vMTkyLjE2OC4wLjk6ODA4MC9hdXRoL3JlYWxtcy9tYXN0ZXIiLCJhdWQiOlsibWFzdGVyLXJlYWxtIiwiYWNjb3VudCJdLCJzdWIiOiJhNmE3OGQ5MS01NDk0LTRjZTMtOTU1NS04NzhhMTg1Y2E0YjkiLCJ0eXAiOiJCZWFyZXIiLCJhenAiOiJrb25nIiwibm9uY2UiOiJmNGRkNDU2YzBjZTY4ZmFmYWJmNGY4ZDA3YjQ0YWE4NiIsImF1dGhfdGltZSI6…IiwibWFuYWdlLWFjY291bnQtbGlua3MiLCJ2aWV3LXByb2ZpbGUiXX19LCJzY29wZSI6Im9wZW5pZCBwcm9maWxlIGVtYWlsIiwiZW1haWxfdmVyaWZpZWQiOmZhbHNlLCJwcmVmZXJyZWRfdXNlcm5hbWUiOiJhZG1pbiJ9.GWuguFjSEDGxw_vbD04UMKxtai15BE2lwBO0YkSzp-NKZ2SxAzl0nyhZxpP0VTzk712nQ8f_If5-mQBf_rqEVnOraDmX5NOXP0B8AoaS1jsdq4EomrhZGqlWmuaV71Cnqrw66iaouBR_6Q0s8bgc1FpCPyACM4VWs57CBdTrAZ2iv8dau5ODkbEvSgIgoLgBbUvjRKz1H0KyeBcXlVSgHJ_2zB9q2HvidBsQEIwTP8sWc6er-5AltLbV8ceBg5OaZ4xHoramMoz2xW-ttjIujS382QQn3iekNByb62O2cssTP3UYC747ehXReCrNZmDA6ecdnv8vOfIem3xNEnEmQw
X-Id-Token: eyJuYmYiOjAsImF6cCI6ImtvbmciLCJpYXQiOjE1NDg1MTA3NjksImlzcyI6Imh0dHA6XC9cLzE5Mi4xNjguMC45OjgwODBcL2F1dGhcL3JlYWxtc1wvbWFzdGVyIiwiYXVkIjoia29uZyIsIm5vbmNlIjoiZjRkZDQ1NmMwY2U2OGZhZmFiZjRmOGQwN2I0NGFhODYiLCJwcmVmZXJyZWRfdXNlcm5hbWUiOiJhZG1pbiIsImF1dGhfdGltZSI6MTU0ODUxMDY5NywiYWNyIjoiMSIsInNlc3Npb25fc3RhdGUiOiJiNDZmODU2Ny0zODA3LTQ0YmMtYmU1Mi1iMTNiNWQzODI5MTQiLCJleHAiOjE1NDg1MTA4MjksImVtYWlsX3ZlcmlmaWVkIjpmYWxzZSwianRpIjoiMjI1ZDRhNDItM2Y3ZC00Y2I2LTkxMmMtOGNkYzM0Y2JiNTk2Iiwic3ViIjoiYTZhNzhkOTEtNTQ5NC00Y2UzLTk1NTUtODc4YTE4NWNhNGI5IiwidHlwIjoiSUQifQ==
```


## Development

### Running Unit Tests

To run unit tests, run the following command:

```
./bin/run-unit-tests.sh
```

This may take a while for the first run, as the docker image will need to be built, but subsequent runs will be quick.

### Building the Integration Test Environment

To build the integration environment (Kong with the oidc plugin enabled, and Keycloak as the OIDC Provider), you will first need to find your computer's IP, and assign that to the environment variable `IP`. Finally, you will run the `./bin/build-env.sh` command. Here's an example:

```
export IP=192.168.0.1
./bin/build-env.sh
```

To tear the environment down:

```
./bin/teardown-env.sh
```
