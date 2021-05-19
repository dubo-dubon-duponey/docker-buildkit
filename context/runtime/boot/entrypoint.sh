#!/usr/bin/env bash
set -o errexit -o errtrace -o functrace -o nounset -o pipefail

[ -w /data ] || {
  printf >&2 "/data is not writable. Check your mount permissions.\n"
  exit 1
}

# Helpers (TODO this is purely provisional right now)
case "${1:-}" in
  # Short hand helper to generate password hash
  "hash")
    shift
    printf >&2 "Generating password hash\n"
    caddy hash-password -algorithm bcrypt "$@"
    exit
  ;;
  # Helper to get the ca.crt out (once initialized)
  "cert")
    if [ "$TLS" != "internal" ]; then
      echo "Your server is not configured in self-signing mode. This command is a no-op in that case."
      exit 1
    fi
    if [ ! -e /certs/pki/authorities/local/root.crt ]; then
      printf >&2 "No root certificate installed or generated. Run the container so that a cert is generated, or provide one at runtime."
      exit 1
    fi
    cat /certs/pki/authorities/local/root.crt
    exit
  ;;
esac

# Bonjour the container if asked to
if [ "${MDNS_ENABLED:-}" == true ]; then
  goello-server -name "$MDNS_NAME" -host "$MDNS_HOST" -port "$PORT" -type "$MDNS_TYPE" &
fi


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

# TODO automate that as part of our Debian base image with facility to provide a root?
# XXX this is probably not necessary anymore with the new strategy in terraform
# Buildkit has to access our internal registry, so, this is necessary for now
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
