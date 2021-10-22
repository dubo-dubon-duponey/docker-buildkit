#!/usr/bin/env bash
set -o errexit -o errtrace -o functrace -o nounset -o pipefail

helpers::dir::writable(){
  local path="$1"
  local create="${2:-}"
  # shellcheck disable=SC2015
  ( [ ! "$create" ] || mkdir -p "$path" 2>/dev/null ) && [ -w "$path" ] && [ -d "$path" ] || {
    printf >&2 "%s does not exist, is not writable, or cannot be created. Check your mount permissions.\n" "$path"
    exit 1
  }
}

start::sidecar(){
  local disable_tls=""
  local disable_mtls=""
  local disable_auth=""

  AUTH="${AUTH:-}"
  TLS="${TLS:-}"
  MTLS="${MTLS:-}"

  local secure=s

  [ "$MTLS" != "" ] || disable_mtls=true;
  [ "$AUTH" != "" ] || disable_auth=true;
  [ "$TLS" != "" ] || {
    disable_tls=true
    secure=
  }

  XDG_CONFIG_HOME=/tmp/config \
  CDY_SERVER_NAME=${SERVER_NAME:-DuboDubonDuponey/1.0} \
  CDY_LOG_LEVEL=${LOG_LEVEL:-error} \
  CDY_SCHEME="http${secure:-}" \
  CDY_DOMAIN="${DOMAIN:-}" \
  CDY_ADDITIONAL_DOMAINS="${ADDITIONAL_DOMAINS:-}" \
  CDY_AUTH_DISABLE="$disable_auth" \
  CDY_AUTH_REALM="$AUTH" \
  CDY_AUTH_USERNAME="${AUTH_USERNAME:-}" \
  CDY_AUTH_PASSWORD="${AUTH_PASSWORD:-}" \
  CDY_TLS_DISABLE="$disable_tls" \
  CDY_TLS_MODE="$TLS" \
  CDY_TLS_MIN="${TLS_MIN:-1.3}" \
  CDY_TLS_AUTO="${TLS_AUTO:-disable_redirects}" \
  CDY_MTLS_DISABLE="$disable_mtls" \
  CDY_MTLS_MODE="$MTLS" \
  CDY_MTLS_TRUST="${MTLS_TRUST:-}" \
  CDY_HEALTHCHECK_URL="$HEALTHCHECK_URL" \
  CDY_PORT_HTTP="$PORT_HTTP" \
  CDY_PORT_HTTPS="$PORT_HTTPS" \
  CDY_ACME_CA="$TLS_SERVER" \
  CDY_ACME_CA="$TLS_SERVER" \
    caddy run -config /config/caddy/main.conf --adapter caddyfile "$@"
}
