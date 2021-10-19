#!/usr/bin/env bash
set -o errexit -o errtrace -o functrace -o nounset -o pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]:-$PWD}")" 2>/dev/null 1>&2 && pwd)"
readonly root
# shellcheck source=/dev/null
source "$root/helpers.sh"
# shellcheck source=/dev/null
source "$root/mdns.sh"

helpers::dir::writable /certs
helpers::dir::writable /tmp
helpers::dir::writable /data
helpers::dir::writable "$XDG_RUNTIME_DIR" create

# Helpers
case "${1:-run}" in
  # Short hand helper to generate password hash
  "hash")
    shift
    printf >&2 "Generating password hash\n"
    caddy hash-password -algorithm bcrypt "$@"
    exit
  ;;
  # Helper to get the ca.crt out (once initialized)
  "cert")
    if [ "${TLS_MODE:-}" == "" ]; then
      printf >&2 "Your container is not configured for TLS termination - there is no local CA in that case."
      exit 1
    fi
    if [ "${TLS_MODE:-}" != "internal" ]; then
      printf >&2 "Your container uses letsencrypt - there is no local CA in that case."
      exit 1
    fi
    if [ ! -e /certs/pki/authorities/local/root.crt ]; then
      printf >&2 "No root certificate installed or generated. Run the container so that a cert is generated, or provide one at runtime."
      exit 1
    fi
    cat /certs/pki/authorities/local/root.crt
    exit
  ;;
  "run")
    # If we want TLS and authentication, start caddy in the background
    # XXX btw relying on caddy to do this is problematic
    if [ "${TLS_MODE:-}" ]; then
      XDG_CONFIG_HOME=/tmp PORT=44444 caddy run -config /config/caddy/main.conf --adapter caddyfile &
    fi
  ;;
esac

helpers::dbus(){
  # On container restart, cleanup the crap
  rm -f /run/dbus/pid

  # https://linux.die.net/man/1/dbus-daemon-1
  dbus-daemon --system

  until [ -e /run/dbus/system_bus_socket ]; do
    sleep 1s
  done
}

helpers::dbus

helpers::dir::writable "/run/avahi-daemon" create
rm -f /run/avahi-daemon/pid
avahi-daemon --daemonize --no-chroot

# Uninstall whatever is there already
for emulator in $(binfmt | jq -rc .supported[] || true); do
  binfmt --uninstall "$emulator" || true
done
for emulator in $(binfmt | jq -rc .emulators[] || true); do
  binfmt --uninstall "$emulator" || true
done

# And install our own
QEMU_BINARY_PATH=/boot/bin/ binfmt --install all

# PORT="${PORT:-}"

# XXX What happens on renewal?
# XXX local only valid for non public properties


# mDNS blast if asked to
[ ! "${MDNS_HOST:-}" ] || {
  _mdns_port="$([ "$TLS" != "" ] && printf "%s" "${PORT_HTTPS:-443}" || printf "%s" "${PORT_HTTP:-80}")"
  [ ! "${MDNS_STATION:-}" ] || mdns::add "_workstation._tcp" "$MDNS_HOST" "${MDNS_NAME:-}" "$_mdns_port"
  mdns::add "${MDNS_TYPE:-_http._tcp}" "$MDNS_HOST" "${MDNS_NAME:-}" "$_mdns_port"
  mdns::start &
}

com=(buildkitd \
    --root /data/buildkit \
    --addr tcp://0.0.0.0:"$PORT_HTTPS"
    --oci-worker true \
    --containerd-worker false \
    --oci-worker-snapshotter native \
    --config /config/buildkitd/main.toml)

if [ "${TLS_MODE:-}" ]; then
  com+=(--tlscert /certs/certificates/local/"${DOMAIN:-}/${DOMAIN:-}".crt \
    --tlskey /certs/certificates/local/"${DOMAIN:-}/${DOMAIN:-}".key \
    --tlscacert /certs/pki/authorities/local/root.crt)

  while [ ! -e /certs/certificates/local/"${DOMAIN:-}/${DOMAIN:-}".key ]; do
    echo "Buildkit is waiting on certificate to be ready"
    sleep 1
  done
fi

if [ "${ROOTLESS:-}" ]; then
  com+=(--rootless)
  exec rootlesskit --state-dir /data/rootlesskit "${com[@]}"
else
  exec "${com[@]}"
fi

#  --rootless                                  set all the default options to be compatible with rootless containers
#   --debug                                     enable debug output in logs
#   --group value                               group (name or gid) which will own all Unix socket listening addresses
#   --debugaddr value                           debugging address (eg. 0.0.0.0:6060)
#   --allow-insecure-entitlement value          allows insecure entitlements e.g. network.host, security.insecure
