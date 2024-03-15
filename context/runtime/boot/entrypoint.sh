#!/usr/bin/env bash
set -o errexit -o errtrace -o functrace -o nounset -o pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]:-$PWD}")" 2>/dev/null 1>&2 && pwd)"
readonly root
# shellcheck source=/dev/null
. "$root/helpers.sh"
# shellcheck source=/dev/null
. "$root/mdns.sh"
# shellcheck source=/dev/null
. "$root/tls.sh"

helpers::dir::writable /certs
helpers::dir::writable /tmp
helpers::dir::writable "$XDG_DATA_HOME" create
helpers::dir::writable "$XDG_DATA_DIRS" create
helpers::dir::writable "$XDG_RUNTIME_DIR" create

# --disable-authentication
# XXX switch to unix socks for buildkit
#  ghostunnel "${flags[@]}" server --listen "0.0.0.0:443" --target "unix:/data/buildkitd.sock" --allow-all

[ "${MOD_MDNS_NSS_ENABLED:-}" != true ] || mdns::start::avahi

# mDNS blast if asked to
# XXX so no broadcast unless TLS?
[ "${MOD_MDNS_ENABLED:-}" != true ] || [ "${MOD_TLS_ENABLED:-}" != true ] || {
  _mdns_type="${MOD_MDNS_TYPE:-_buildkit._tcp}"
  _mdns_port="${MOD_TLS_PORT:-443}"

  [ "${ADVANCED_MOD_MDNS_STATION:-}" != true ] || mdns::records::add "_workstation._tcp" "${MOD_MDNS_HOST}" "${MOD_MDNS_NAME:-}" "$_mdns_port"
  mdns::records::add "$_mdns_type" "${MOD_MDNS_HOST:-}" "${MOD_MDNS_NAME:-}" "$_mdns_port"
  mdns::start::broadcaster
}

# Uninstall whatever is there already
for emulator in $(binfmt | jq -rc .supported[] || true); do
  binfmt --uninstall "$emulator" || true
done
for emulator in $(binfmt | jq -rc .emulators[] || true); do
  binfmt --uninstall "$emulator" || true
done

# And install our own
QEMU_BINARY_PATH=/boot/bin/ binfmt --install all

com=(buildkitd \
    --root /data/buildkit \
    --oci-worker true \
    --containerd-worker false \
    --oci-worker-snapshotter native \
    --config /config/buildkitd/main.toml)

[ "$LOG_LEVEL" != "debug" ] || args+=(--debug)

[ "${MOD_METRICS_ENABLED:-}" != true ] || args+=(--debugaddr "${MOD_METRICS_BIND:-:4242}")

[ "${DUBO_EXPERIMENTAL:-}" ] \
  && com+=(--addr unix:///data/buildkitd.sock) \
  || com+=(--addr tcp://0.0.0.0:"${ADVANCED_PORT_HTTPS:-443}")

# Start either buildkit or ghost for the TLS termination
if [ "${TLS:-}" ]; then
  if [ ! "${DUBO_EXPERIMENTAL:-}" ]; then
    com+=(--tlscert /certs/certificates/local/"${DOMAIN:-}/${DOMAIN:-}".crt \
      --tlskey /certs/certificates/local/"${DOMAIN:-}/${DOMAIN:-}".key \
      --tlscacert /certs/pki/authorities/local/root.crt)

    while [ ! -e /certs/certificates/local/"${DOMAIN:-}/${DOMAIN:-}".key ]; do
      echo "Buildkit is waiting on certificate to be ready"
      sleep 1
    done
  else
    tls::start :4242 /data/buildkitd.sock
  fi
fi

if [ "${ROOTLESS:-}" ]; then
  com+=(--rootless)
  exec rootlesskit --state-dir /data/rootlesskit "${com[@]}"
else
  exec "${com[@]}"
fi

#   --group value                               group (name or gid) which will own all Unix socket listening addresses
#   --allow-insecure-entitlement value          allows insecure entitlements e.g. network.host, security.insecure
