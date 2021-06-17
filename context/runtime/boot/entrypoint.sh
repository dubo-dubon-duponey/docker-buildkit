#!/usr/bin/env bash
set -o errexit -o errtrace -o functrace -o nounset -o pipefail

[ -w /certs ] || {
  printf >&2 "/certs is not writable. Check your mount permissions.\n"
  exit 1
}

[ -w /tmp ] || {
  printf >&2 "/tmp is not writable. Check your mount permissions.\n"
  exit 1
}

[ -w /data ] || {
  printf >&2 "/data is not writable. Check your mount permissions.\n"
  exit 1
}

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
    if [ "$TLS" == "" ]; then
      printf >&2 "Your container is not configured for TLS termination - there is no local CA in that case."
      exit 1
    fi
    if [ "$TLS" != "internal" ]; then
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
    # Bonjour the container if asked to. While the PORT is no guaranteed to be mapped on the host in bridge, this does not matter since mDNS will not work at all in bridge mode.
    if [ "${MDNS_ENABLED:-}" == true ]; then
      goello-server -name "$MDNS_NAME" -host "$MDNS_HOST" -port "$PORT" -type "$MDNS_TYPE" &
    fi

    # If we want TLS and authentication, start caddy in the background
    if [ "$TLS" ]; then
      HOME=/tmp/caddy-home exec caddy run -config /config/caddy/main.conf --adapter caddyfile &
    fi
  ;;
esac

mkdir -p "$XDG_RUNTIME_DIR" || {
  printf >&2 "$XDG_RUNTIME_DIR is not writable. Check your mount permissions.\n"
  exit 1
}

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

mkdir -p /run/avahi-daemon
rm -f /run/avahi-daemon/pid
avahi-daemon --daemonize --no-chroot

binfmt -dir /config/binfmt.d

PORT="${PORT:-}"

exec buildkitd \
  --root /data/buildkit \
  --debug \
  --oci-worker true \
  --containerd-worker false \
  --oci-worker-snapshotter native \
  --config /config/buildkitd/main.toml \
  --addr tcp://0.0.0.0:"$PORT"

exit

args=(rootlesskit --state-dir /data/rootlesskit buildkitd --oci-worker true --containerd-worker false --oci-worker-snapshotter native \
  --addr tcp://0.0.0.0:"$PORT" --config /config/buildkitd.toml --root /data/buildkit \
  --rootless)

exec "${args[@]}" "$@"
