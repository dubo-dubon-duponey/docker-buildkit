ARG           BUILDER_BASE=dubodubonduponey/base@sha256:b51f084380bc1bd2b665840317b6f19ccc844ee2fc7e700bf8633d95deba2819
ARG           RUNTIME_BASE=dubodubonduponey/base@sha256:d28e8eed3e87e8dc5afdd56367d3cf2da12a0003d064b5c62405afbe4725ee99

# sudo sh -c "echo 1 > /proc/sys/kernel/unprivileged_userns_clone"
# docker run -ti --net dubo-vlan --entrypoint rootlesskit --privileged registry.dev.jsboot.space/dubodubonduponey/aptly:test-bk buildkitd --addr tcp://0.0.0.0:4242

# hadolint ignore=DL3006
FROM          --platform=$BUILDPLATFORM $BUILDER_BASE                                                                   AS builder-root

RUN           set -eu; \
              dpkg --add-architecture s390x && \
              dpkg --add-architecture ppc64el && \
              dpkg --add-architecture armel && \
              dpkg --add-architecture armhf && \
              dpkg --add-architecture arm64 && \
              dpkg --add-architecture amd64 && \
              apt-get update && \
              apt-get --no-install-recommends install -qq \
                crossbuild-essential-s390x libseccomp-dev:s390x \
                crossbuild-essential-ppc64el libseccomp-dev:ppc64el \
                crossbuild-essential-armhf libseccomp-dev:armhf \
                crossbuild-essential-arm64 libseccomp-dev:arm64 \
                crossbuild-essential-amd64 libseccomp-dev:amd64

###################################################################
# Runc
###################################################################
# hadolint ignore=DL3006
FROM          --platform=$BUILDPLATFORM builder-root                                                                    AS builder-runc

# v1.0.0-rc92
ARG           GIT_REPO=github.com/opencontainers/runc
ARG           GIT_VERSION=ff819c7e9184c13b7c2607fe6c30ae19403a7aff

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone git://$GIT_REPO .
RUN           git checkout $GIT_VERSION

# hadolint ignore=DL4006
RUN           set -eu; \
              case "$TARGETPLATFORM" in \
                "linux/amd64")    abi=gnu;        ga=x86_64;      ;; \
                "linux/arm64")    abi=gnu;        ga=aarch64;     ;; \
                "linux/arm/v7")   abi=gnueabihf;  ga=arm;         ;; \
                "linux/ppc64le")  abi=gnu;        ga=powerpc64le; ;; \
                "linux/s390x")    abi=gnu;        ga=s390x;       ;; \
              esac; \
              export CC=${ga}-linux-${abi}-gcc; \
              export CC_FOR_TARGET=${ga}-linux-${abi}-gcc; \
              export CGO_ENABLED=1; \
              FLAGS="-extldflags -static"; \
              TAGS="seccomp apparmor netgo static_build osusergo cgo"; \
              SRC="./"; \
              DEST="runc"; \
              env GOOS=linux GOARCH="$(printf "%s" "$TARGETPLATFORM" | sed -E 's/^[^/]+\/([^/]+).*/\1/')" \
                go build -v -ldflags "-s -w $FLAGS" -tags "$TAGS" -o /dist/boot/bin/"$DEST" "$SRC"

###################################################################
# Buildkit
###################################################################
# hadolint ignore=DL3006
FROM          --platform=$BUILDPLATFORM $BUILDER_BASE                                                                   AS builder-buildkit

ARG           GIT_REPO=github.com/moby/buildkit
ARG           GIT_VERSION=3aa7902d40d8a7fe911ee35488985cb58a346710

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone git://$GIT_REPO .
RUN           git checkout $GIT_VERSION

# XXX do we need cgo in the tags?
# XXX what about -buildmode=pie ?
# hadolint ignore=DL4006
RUN           set -eu; \
              FLAGS="-extldflags -static -X $GIT_REPO/version.Version=$BUILD_VERSION -X $GIT_REPO/version.Revision=$BUILD_REVISION -X $GIT_REPO/version.Package=$GIT_REPO"; \
              TAGS="seccomp netgo static_build osusergo"; \
              SRC="./cmd/buildkitd"; \
              DEST="buildkitd"; \
              env GOOS=linux GOARCH="$(printf "%s" "$TARGETPLATFORM" | sed -E 's/^[^/]+\/([^/]+).*/\1/')" \
                go build -v -ldflags "-s -w $FLAGS" -tags "$TAGS" -o /dist/boot/bin/"$DEST" "$SRC"

# hadolint ignore=DL4006
RUN           set -eu; \
              FLAGS="-extldflags -static -X $GIT_REPO/version.Version=$BUILD_VERSION -X $GIT_REPO/version.Revision=$BUILD_REVISION -X $GIT_REPO/version.Package=$GIT_REPO"; \
              TAGS=""; \
              SRC="./cmd/buildctl"; \
              DEST="buildctl"; \
              env GOOS=linux GOARCH="$(printf "%s" "$TARGETPLATFORM" | sed -E 's/^[^/]+\/([^/]+).*/\1/')" \
                go build -v -ldflags "-s -w $FLAGS" -tags "$TAGS" -o /dist/boot/bin/"$DEST" "$SRC"

###################################################################
# Rootless
###################################################################
# hadolint ignore=DL3006
FROM          --platform=$BUILDPLATFORM $BUILDER_BASE                                                                   AS builder-rootless
ARG           GIT_REPO=github.com/rootless-containers/rootlesskit
ARG           GIT_VERSION=36f981d4cf0631b96775c5969df6d7a2df757441

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone git://$GIT_REPO .
RUN           git checkout $GIT_VERSION

# hadolint ignore=DL4006
RUN           FLAGS="-extldflags -static"; \
              env GOOS=linux GOARCH="$(printf "%s" "$TARGETPLATFORM" | sed -E 's/^[^/]+\/([^/]+).*/\1/')" go build -v -ldflags "-s -w $FLAGS" \
                -o /dist/boot/bin/rootlesskit ./cmd/rootlesskit

###################################################################
# Stargz
###################################################################
# hadolint ignore=DL3006
FROM          --platform=$BUILDPLATFORM $BUILDER_BASE                                                                   AS builder-stargz
ARG           GIT_REPO=github.com/containerd/stargz-snapshotter
ARG           GIT_VERSION=6ab4c0507ad44fa9d850c401849734795bea564c

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone git://$GIT_REPO .
RUN           git checkout $GIT_VERSION

# hadolint ignore=DL4006
RUN           FLAGS="-extldflags -static"; \
              env GOOS=linux GOARCH="$(printf "%s" "$TARGETPLATFORM" | sed -E 's/^[^/]+\/([^/]+).*/\1/')" go build -v -ldflags "-s -w $FLAGS" \
                -o /dist/boot/bin/containerd-stargz-grpc ./cmd/containerd-stargz-grpc

# hadolint ignore=DL4006
RUN           FLAGS="-extldflags -static"; \
              env GOOS=linux GOARCH="$(printf "%s" "$TARGETPLATFORM" | sed -E 's/^[^/]+\/([^/]+).*/\1/')" go build -v -ldflags "-s -w $FLAGS" \
                -o /dist/boot/bin/ctr-remote ./cmd/ctr-remote

###################################################################
# Containerd
###################################################################
# hadolint ignore=DL3006
FROM          --platform=$BUILDPLATFORM $BUILDER_BASE                                                                   AS builder-containerd
ARG           GIT_REPO=github.com/containerd/containerd
ARG           GIT_VERSION=6b5fc7f2044797cde2b8eea8fa59cf754e7b5d30

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone git://$GIT_REPO .
RUN           git checkout $GIT_VERSION

# hadolint ignore=DL4006
RUN           set -eu; \
              GO111MODULE=auto; \
              TAGS="apparmor no_btrfs no_devmapper no_cri"; \
              FLAGS="-X $GIT_REPO/version.Version=$BUILD_VERSION -X $GIT_REPO/version.Revision=$BUILD_REVISION -X $GIT_REPO/version.Package=$GIT_REPO"; \
              env GOOS=linux GOARCH="$(printf "%s" "$TARGETPLATFORM" | sed -E 's/^[^/]+\/([^/]+).*/\1/')" go build -v -ldflags "-s -w $FLAGS -extldflags -static" -tags "$TAGS" \
                -o /dist/boot/bin/containerd-shim ./cmd/containerd-shim; \
              env GOOS=linux GOARCH="$(printf "%s" "$TARGETPLATFORM" | sed -E 's/^[^/]+\/([^/]+).*/\1/')" go build -v -ldflags "-s -w $FLAGS -extldflags -static" -tags "$TAGS" \
                -o /dist/boot/bin/containerd-shim-runc-v2 ./cmd/containerd-shim-runc-v2; \
              env GOOS=linux GOARCH="$(printf "%s" "$TARGETPLATFORM" | sed -E 's/^[^/]+\/([^/]+).*/\1/')" go build -v -ldflags "-s -w $FLAGS" -tags "$TAGS" \
                -o /dist/boot/bin/ctr ./cmd/ctr; \
              env GOOS=linux GOARCH="$(printf "%s" "$TARGETPLATFORM" | sed -E 's/^[^/]+\/([^/]+).*/\1/')" go build -v -ldflags "-s -w $FLAGS" -tags "$TAGS" \
                -o /dist/boot/bin/containerd ./cmd/containerd

#######################
# Builder assembly
#######################
# hadolint ignore=DL3006
FROM          $BUILDER_BASE                                                                                             AS builder

#COPY          --from=builder-stargz     /dist/boot/bin /dist/boot/bin
#COPY          --from=builder-containerd /dist/boot/bin /dist/boot/bin
COPY          --from=builder-rootless   /dist/boot/bin /dist/boot/bin
COPY          --from=builder-buildkit   /dist/boot/bin /dist/boot/bin
COPY          --from=builder-runc       /dist/boot/bin /dist/boot/bin

RUN           chmod 555 /dist/boot/bin/*; \
              epoch="$(date --date "$BUILD_CREATED" +%s)"; \
              find /dist/boot/bin -newermt "@$epoch" -exec touch --no-dereference --date="@$epoch" '{}' +;


#######################
# Runtime
#######################
# hadolint ignore=DL3006
FROM          $RUNTIME_BASE

USER          root

RUN           apt-get update -qq          && \
              apt-get install -qq --no-install-recommends \
                uidmap=1:4.5-1.1 \
                git=1:2.20.1-2+deb10u3 && \
              apt-get -qq autoremove      && \
              apt-get -qq clean           && \
              rm -rf /var/lib/apt/lists/* && \
              rm -rf /tmp/*               && \
              rm -rf /var/tmp/*

USER          dubo-dubon-duponey

ENV           PORT=4242

VOLUME        /data
VOLUME        /tmp

COPY          --from=builder --chown=$BUILD_UID:root /dist .

# System constants, unlikely to ever require modifications in normal use
#ENV           HEALTHCHECK_URL=http://127.0.0.1:10042/healthcheck

# HEALTHCHECK   --interval=30s --timeout=30s --start-period=10s --retries=1 CMD http-health || exit 1



# RUN apk add --no-cache fuse3 git xz
#COPY --from=idmap /usr/bin/newuidmap /usr/bin/newuidmap
#COPY --from=idmap /usr/bin/newgidmap /usr/bin/newgidmap
#COPY --from=fuse-overlayfs /out/fuse-overlayfs /usr/bin/
# we could just set CAP_SETUID filecap rather than `chmod u+s`, but requires kernel >= 4.14
#RUN chmod u+s /usr/bin/newuidmap /usr/bin/newgidmap \
#  && adduser -D -u 1000 user \
#  && mkdir -p /run/user/1000 /home/user/.local/tmp /home/user/.local/share/buildkit \
#  && chown -R user /run/user/1000 /home/user \
#  && echo user:100000:65536 | tee /etc/subuid | tee /etc/subgid
#COPY --from=rootlesskit /rootlesskit /usr/bin/
#COPY --from=binaries / /usr/bin/
#COPY examples/buildctl-daemonless/buildctl-daemonless.sh /usr/bin/
# Kubernetes runAsNonRoot requires USER to be numeric
#USER 1000:1000
#ENV HOME /home/user
#ENV USER user
#ENV XDG_RUNTIME_DIR=/run/user/1000
#ENV TMPDIR=/home/user/.local/tmp
#ENV BUILDKIT_HOST=unix:///run/user/1000/buildkit/buildkitd.sock
#VOLUME /home/user/.local/share/buildkit
#ENTRYPOINT ["rootlesskit", "buildkitd"]
