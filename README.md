# What

A Docker image to run a BuildKit server.

This is based on [BuildKit](https://github.com/moby/buildkit) with bits and pieces from https://github.com/docker/binfmt

Experimental.

This is mostly of interest for people who want to roll their own multi-arch enabled buildkit nodes, as an example.

## Image features

* multi-architecture:
  * [x] linux/amd64
  * [x] linux/arm64
* hardened:
  * [x] image runs read-only
  * [ ] image runs with no capabilities, although apparmor and seccomp have to be disabled
  * [ ] process runs as a non-root user, disabled login, no shell
* lightweight
  * [x] based on our slim [Debian Bookworm](https://github.com/dubo-dubon-duponey/docker-debian)
  * [x] simple entrypoint script
  * [ ] multi-stage build with ~~zero packages~~ `git`, `pigz`, `xz-utils`, `jq`, `libnss-mdns` installed in the runtime image
* observable
  * [x] healthcheck
  * [x] log to stdout
  * [x] prometheus endpoint

## Run

```bash
docker run -d --rm \
    --read-only \
    --volume $(pwd)/data:/data \
    --name bk \
    --security-opt seccomp=unconfined --security-opt apparmor=unconfined \
    docker.io/dubodubonduponey/buildkit
```

## Notes

We are bundling in avahi to provide mDNS *resolution* for buildkit, if configured.
Specifically useful to allow access for local services (registry, apt-cache) which advertise
their ip over mDNS.

Configuration is mostly experimental right now and undocumented.
You have to look at the bottom of the Dockerfile, and the entrypoint script.

## Moar?

See [DEVELOP.md](DEVELOP.md)

<!--

Possible caveats: sudo sh -c "echo 1 > /proc/sys/kernel/unprivileged_userns_clone"

-->
