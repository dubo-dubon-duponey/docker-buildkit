#!/usr/bin/env bash
set -o errexit -o errtrace -o functrace -o nounset -o pipefail

[ -w "/data" ] || {
  >&2 printf "/data is not writable. Check your mount permissions.\n"
  exit 1
}

PORT="${PORT:-}"

args=(rootlesskit buildkitd --addr tcp://0.0.0.0:"$PORT" --config /config/buildkitd.toml --root /data/buildkit --rootless)

exec "${args[@]}" "$@"
