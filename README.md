# What

Docker image for "BuildKit".

This is based on [BuildKit](https://github.com/moby/buildkit) with bits and pieces from https://github.com/docker/binfmt

Experimental. This is mostly of interest for people who want to roll their own multi-arch enabled buildkit nodes, as an example.

Notes:
 * there is no support for containerd workers
 * this is focused on hardening, specifically, buildkit runs with rootlesskit

## Image features

 * multi-architecture:
    * [x] linux/amd64
    * [x] linux/arm64
    * [x] linux/arm/v7
    * [x] linux/s390x
    * [x] linux/ppc64le
    * [ ] linux/arm/v6 (may build, but unsupported right now)
    * [ ] linux/386 (may build, but unsupported right now)
 * hardened:
    * [x] image runs read-only
    * [ ] image runs with no capabilities, although apparmor and seccomp have to be disabled
    * [x] process runs as a non-root user, disabled login, no shell
 * lightweight
    * [x] based on our slim [Debian buster version](https://github.com/dubo-dubon-duponey/docker-debian)
    * [x] simple entrypoint script
    * [ ] multi-stage build ~~with no installed dependencies~~ with git installed for the runtime image
 * observable
    * [x] healthcheck
    * [x] log to stdout
    * [ ] ~~prometheus endpoint~~ not applicable

## Run

```bash
docker run -d --rm \
    --read-only \
    --volume $(pwd)/data:/data \
    --name bk \
    --security-opt seccomp=unconfined --security-opt apparmor=unconfined \
    registry.dev.jsboot.space/dubodubonduponey/buildkit
```

## Moar?

See [DEVELOP.md](DEVELOP.md)

<!--

Possible caveats: sudo sh -c "echo 1 > /proc/sys/kernel/unprivileged_userns_clone"

-->
