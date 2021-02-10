#!/usr/bin/env bash
set -o errexit -o errtrace -o functrace -o nounset -o pipefail

[ -w "/data" ] || {
  >&2 printf "/data is not writable. Check your mount permissions.\n"
  exit 1
}

# Helpers (TODO this is purely provisional right now)
case "${1:-}" in
  # Short hand helper to generate password hash
  "hash")
    shift
    # Interactive.
    echo "Going to generate a password hash with salt: $SALT"
    caddy hash-password -algorithm bcrypt -salt "$SALT"
    exit
  ;;
  # Helper to get the ca.crt out (once initialized)
  "cert")
    if [ "$TLS" != internal ]; then
      echo "Your server is not configured in self-signing mode. This command is a no-op in that case."
      exit 1
    fi
    if [ ! -e "/certs/pki/authorities/local/root.crt" ]; then
      echo "No root certificate installed or generated. Run the container so that a cert is generated, or provide one at runtime."
      exit 1
    fi
    cat /certs/pki/authorities/local/root.crt
    exit
  ;;
esac

# Given how the caddy conf is set right now, we cannot have these be not set, so, stuff in randomized shit in there
readonly SALT="${SALT:-"$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 64 | base64)"}"
readonly USERNAME="${USERNAME:-"$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 64)"}"
readonly PASSWORD="${PASSWORD:-$(caddy hash-password -algorithm bcrypt -salt "$SALT" -plaintext "$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 64)")}"

# Bonjour the container if asked to
if [ "${MDNS_ENABLED:-}" == true ]; then
  goello-server -name "$MDNS_NAME" -host "$MDNS_HOST" -port "$PORT" -type "$MDNS_TYPE" &
fi


mkdir -p "$XDG_RUNTIME_DIR" || {
  >&2 printf "$XDG_RUNTIME_DIR is not writable. Check your mount permissions.\n"
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
avahi-daemon --daemonize --no-chroot

# TODO automate that as part of our Debian base image with facility to provide a root?

echo "-----BEGIN CERTIFICATE-----
MIIBozCCAUmgAwIBAgIQBd+mZ7Uj+1lnuzBd1klrvzAKBggqhkjOPQQDAjAwMS4w
LAYDVQQDEyVDYWRkeSBMb2NhbCBBdXRob3JpdHkgLSAyMDIwIEVDQyBSb290MB4X
DTIwMTEzMDIzMTA0NVoXDTMwMTAwOTIzMTA0NVowMDEuMCwGA1UEAxMlQ2FkZHkg
TG9jYWwgQXV0aG9yaXR5IC0gMjAyMCBFQ0MgUm9vdDBZMBMGByqGSM49AgEGCCqG
SM49AwEHA0IABOzpNQ/wkHMGFibVR5Gk14PspP+kQ5LpR3XWwvD+rpJjhylvQLW3
/ZvOzKHKHfilkOHI3FCHct8IImF5qhpbJF6jRTBDMA4GA1UdDwEB/wQEAwIBBjAS
BgNVHRMBAf8ECDAGAQH/AgEBMB0GA1UdDgQWBBTGwiMW3cMgyEeZY09nyHbUWMCt
5TAKBggqhkjOPQQDAgNIADBFAiBKZePDr6aXHiMwESluwVM1/y/WVMr4dPNcf2+4
JX0jYwIhALi9+u+eHd2DGP93NXXMgcZMV+YwhSuaFu04pY6Mdwul
-----END CERTIFICATE-----" > /etc/ssl/certs/ca.pem

# /usr/local/share/ca-certificates/ca.crt
# update-ca-certificates

binfmt

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
