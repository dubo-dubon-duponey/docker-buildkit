ARG           BUILDER_BASE=dubodubonduponey/base@sha256:b51f084380bc1bd2b665840317b6f19ccc844ee2fc7e700bf8633d95deba2819
ARG           RUNTIME_BASE=dubodubonduponey/base@sha256:d28e8eed3e87e8dc5afdd56367d3cf2da12a0003d064b5c62405afbe4725ee99

#######################
# Goello
#######################
# hadolint ignore=DL3006,DL3029
FROM          --platform=$BUILDPLATFORM $BUILDER_BASE                                                                   AS builder-goello

ARG           GIT_REPO=github.com/dubo-dubon-duponey/goello
ARG           GIT_VERSION=3799b6035dd5c4d5d1c061259241a9bedda810d6
ARG           BUILD_TARGET=./cmd/server
ARG           BUILD_OUTPUT=goello-server
ARG           BUILD_FLAGS="-s -w"

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone git://$GIT_REPO .
RUN           git checkout $GIT_VERSION
# hadolint ignore=DL4006
RUN           env GOOS=linux GOARCH="$(printf "%s" "$TARGETPLATFORM" | sed -E 's/^[^/]+\/([^/]+).*/\1/')" go build -v \
                -ldflags "$BUILD_FLAGS" -o /dist/boot/bin/"$BUILD_OUTPUT" "$BUILD_TARGET"

#######################
# Builder root
#######################
# hadolint ignore=DL3006,DL3029
FROM          --platform=$BUILDPLATFORM $BUILDER_BASE                                                                   AS builder-root

RUN           set -eu; \
              dpkg --add-architecture s390x && \
              dpkg --add-architecture ppc64el && \
              dpkg --add-architecture armel && \
              dpkg --add-architecture armhf && \
              dpkg --add-architecture arm64 && \
              dpkg --add-architecture amd64

# hadolint ignore=DL3009
RUN           apt-get update -qq
RUN           apt-get -qq --no-install-recommends install \
                crossbuild-essential-s390x=12.6 libseccomp-dev:s390x=2.3.3-4 \
                crossbuild-essential-ppc64el=12.6 libseccomp-dev:ppc64el=2.3.3-4 \
                crossbuild-essential-armhf=12.6 libseccomp-dev:armhf=2.3.3-4 \
                crossbuild-essential-arm64=12.6 libseccomp-dev:arm64=2.3.3-4 \
                crossbuild-essential-amd64=12.6 libseccomp-dev:amd64=2.3.3-4

###################################################################
# Runc
###################################################################
# hadolint ignore=DL3006,DL3029
FROM          --platform=$BUILDPLATFORM builder-root                                                                    AS builder-runc

ARG           GIT_REPO=github.com/opencontainers/runc
# v1.0.0-rc92
# ARG           GIT_VERSION=939ad4e3fcfa1ab531458355a73688c6f4ee5003
# v1.0.0-rc95
ARG           GIT_VERSION=b9ee9c6314599f1b4a7f497e1f1f856fe433d3b7

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
              FLAGS=""; \
              TAGS="seccomp apparmor netcgo cgo"; \
              SRC="./"; \
              DEST="runc"; \
              env GOOS=linux GOARCH="$(printf "%s" "$TARGETPLATFORM" | sed -E 's/^[^/]+\/([^/]+).*/\1/')" \
                go build -v -ldflags "-s -w $FLAGS" -tags "$TAGS" -o /dist/boot/bin/"$DEST" "$SRC"

###################################################################
# Buildkit
###################################################################
# hadolint ignore=DL3006,DL3029
FROM          --platform=$BUILDPLATFORM $BUILDER_BASE                                                                   AS builder-buildkit

ARG           GIT_REPO=github.com/moby/buildkit
# 0.8.3
ARG           GIT_VERSION=81c2cbd8a418918d62b71e347a00034189eea455

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone git://$GIT_REPO .
RUN           git checkout $GIT_VERSION

# XXX do we need cgo in the tags?
# XXX what about -buildmode=pie ?

# removing static for now: FLAGS=-extldflags -static TAGS=static_build
# hadolint ignore=DL4006
RUN           set -eu; \
              export CGO_ENABLED=1; \
              FLAGS="-X $GIT_REPO/version.Version=$BUILD_VERSION -X $GIT_REPO/version.Revision=$BUILD_REVISION -X $GIT_REPO/version.Package=$GIT_REPO"; \
              TAGS="seccomp netcgo cgo"; \
              SRC="./cmd/buildkitd"; \
              DEST="buildkitd"; \
              env GOOS=linux GOARCH="$(printf "%s" "$TARGETPLATFORM" | sed -E 's/^[^/]+\/([^/]+).*/\1/')" \
                go build -v -ldflags "-s -w $FLAGS" -tags "$TAGS" -o /dist/boot/bin/"$DEST" "$SRC"

# hadolint ignore=DL4006
RUN           set -eu; \
              export CGO_ENABLED=1; \
              FLAGS="-X $GIT_REPO/version.Version=$BUILD_VERSION -X $GIT_REPO/version.Revision=$BUILD_REVISION -X $GIT_REPO/version.Package=$GIT_REPO"; \
              TAGS=""; \
              SRC="./cmd/buildctl"; \
              DEST="buildctl"; \
              env GOOS=linux GOARCH="$(printf "%s" "$TARGETPLATFORM" | sed -E 's/^[^/]+\/([^/]+).*/\1/')" \
                go build -v -ldflags "-s -w $FLAGS" -tags "$TAGS" -o /dist/boot/bin/"$DEST" "$SRC";
                # \
# Does not build anymore without static build - might have to forgo on this
#              env GOOS=darwin GOARCH=amd64 \
#                go build -v -ldflags "-s -w $FLAGS" -tags "$TAGS" -o /dist/boot/bin/"$DEST"_mac "$SRC"

###################################################################
# Rootless
###################################################################
# hadolint ignore=DL3006,DL3029
FROM          --platform=$BUILDPLATFORM $BUILDER_BASE                                                                   AS builder-rootless

ARG           GIT_REPO=github.com/rootless-containers/rootlesskit
# 0.14.2
ARG           GIT_VERSION=4cd567642273d369adaadcbadca00880552c1778

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone git://$GIT_REPO .
RUN           git checkout $GIT_VERSION

# hadolint ignore=DL4006
RUN           FLAGS="-extldflags -static"; \
              env GOOS=linux GOARCH="$(printf "%s" "$TARGETPLATFORM" | sed -E 's/^[^/]+\/([^/]+).*/\1/')" go build -v -ldflags "-s -w $FLAGS" \
                -o /dist/boot/bin/rootlesskit ./cmd/rootlesskit


###################################################################
# binfmt
###################################################################
# hadolint ignore=DL3006,DL3029
FROM          --platform=$BUILDPLATFORM $BUILDER_BASE                                                                   AS builder-binfmt

COPY          build/main.go .

# hadolint ignore=DL4006
RUN           FLAGS="-extldflags \"-fno-PIC -static\""; \
              env GOOS=linux GOARCH="$(printf "%s" "$TARGETPLATFORM" | sed -E 's/^[^/]+\/([^/]+).*/\1/')" go build -buildmode pie -v -ldflags "-s -w $FLAGS" \
                -o /dist/boot/bin/binfmt ./main.go

###################################################################
# newuid
###################################################################
# hadolint ignore=DL3006
FROM          $BUILDER_BASE                                                                                             AS builder-idmap

# 4.8.1
ARG           GIT_REPO=github.com/shadow-maint/shadow
ARG           GIT_VERSION=2cc7da6058152ec0cd338d4e15d29bd7124ae3d7

WORKDIR       /shadow
RUN           git clone git://$GIT_REPO .
RUN           git checkout $GIT_VERSION

RUN           set -eu; \
              apt-get update && \
              apt-get --no-install-recommends install -qq \
                libcap-dev=1:2.25-2 autopoint=0.19.8.1-9 gettext=0.19.8.1-9 byacc=20140715-1+b1 libcap2-bin=1:2.25-2 xsltproc=1.1.32-2.2~deb10u1

# RUN ./autogen.sh --help && exit 1
# RUN apk add --no-cache autoconf automake build-base byacc gettext gettext-dev gcc git libcap-dev libtool libxslt
RUN           ./autogen.sh --with-fcaps --disable-nls --without-audit --without-selinux --without-acl --without-attr --without-tcb --without-nscd --without-btrfs \
                && make \
                && mkdir -p /dist/boot/bin \
                && cp src/newuidmap src/newgidmap /dist/boot/bin

###################################################################
# Stargz
###################################################################
# hadolint ignore=DL3006,DL3029
FROM          --platform=$BUILDPLATFORM $BUILDER_BASE                                                                   AS xxx-ignored-builder-stargz

# 0.6.0
ARG           GIT_REPO=github.com/containerd/stargz-snapshotter
ARG           GIT_VERSION=cb2f52ae082afc25c704de7ada28b5b89b1dbc4a

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
# hadolint ignore=DL3006,DL3029
FROM          --platform=$BUILDPLATFORM $BUILDER_BASE                                                                   AS xxx-ignored-builder-containerd
# 1.5.2
ARG           GIT_REPO=github.com/containerd/containerd
ARG           GIT_VERSION=36cc874494a56a253cd181a1a685b44b58a2e34a

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone git://$GIT_REPO .
RUN           git checkout $GIT_VERSION

# hadolint ignore=DL4006
RUN           set -eu; \
              export GO111MODULE=auto; \
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

###################################################################
# QEMU
###################################################################
# hadolint ignore=DL3006
FROM          $BUILDER_BASE                                                                                             AS builder-qemu

# XXX this is abandonware at this point - move upstream after some testing
ARG           GIT_REPO=github.com/moby/qemu
# 4.1.0
ARG           GIT_VERSION=2d04bf7914ad68a6f83b8a480948e604bbe8fea2

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone git://$GIT_REPO .
RUN           git checkout $GIT_VERSION

ARG           VERSION=v4.1.0

RUN           apt-get update -qq && \
              apt-get install -qq --no-install-recommends \
                  build-essential=12.6 \
                  libpixman-1-dev=0.36.0-1 \
                  libglib2.0-dev=2.58.3-2+deb10u2

#                  libtool \
#                  git \
#                  pkg-config \
#                  python

RUN           scripts/git-submodule.sh update \
              ui/keycodemapdb \
              tests/fp/berkeley-testfloat-3 \
              tests/fp/berkeley-softfloat-3 \
              dtc

RUN           ./configure \
                --prefix=/usr \
                --with-pkgversion=$VERSION \
                --enable-linux-user \
                --disable-system \
                --static \
                --disable-blobs \
                --disable-bluez \
                --disable-brlapi \
                --disable-cap-ng \
                --disable-capstone \
                --disable-curl \
                --disable-curses \
                --disable-docs \
                --disable-gcrypt \
                --disable-gnutls \
                --disable-gtk \
                --disable-guest-agent \
                --disable-guest-agent-msi \
                --disable-libiscsi \
                --disable-libnfs \
                --disable-mpath \
                --disable-nettle \
                --disable-opengl \
                --disable-sdl \
                --disable-spice \
                --disable-tools \
                --disable-vte \
                --target-list="aarch64-linux-user arm-linux-user ppc64le-linux-user s390x-linux-user riscv64-linux-user"

RUN           make -j "$(getconf _NPROCESSORS_ONLN)"
RUN           make install

#COPY          build/main.go .
#RUN           env CGO_ENABLED=0 go build -buildmode pie -ldflags "-s -w ${ldflags} -extldflags \"-fno-PIC -static\"" -o /dist/boot/bin/binfmt ./main.go

RUN           mkdir -p /dist/boot/bin/ && cp /usr/bin/qemu-* /dist/boot/bin/

# CMD ["/usr/bin/binfmt"]



# hadolint ignore=DL3006,DL3029
FROM          --platform=$BUILDPLATFORM $BUILDER_BASE                                                                   AS builder-overlay
RUN           apt-get update -qq          && \
              apt-get install -qq --no-install-recommends \
                curl=7.64.0-4+deb10u1

#ARG           FUSEOVERLAYFS_VERSION=v1.1.2
ARG           FUSEOVERLAYFS_VERSION=v1.4.0
ARG           TARGETARCH

# hadolint ignore=DL4006
RUN           echo "$TARGETARCH" | sed -e s/^amd64$/x86_64/ -e s/^arm64$/aarch64/ -e s/^arm$/armv7l/ > /uname_m && \
                mkdir -p /dist/boot/bin && \
                curl -sSL -o /dist/boot/bin/fuse-overlayfs https://github.com/containers/fuse-overlayfs/releases/download/"${FUSEOVERLAYFS_VERSION}"/fuse-overlayfs-"$(cat /uname_m)" && \
                chmod +x /dist/boot/bin/fuse-overlayfs




#######################
# Builder assembly
#######################
# hadolint ignore=DL3006
FROM          $BUILDER_BASE                                                                                             AS builder

#COPY          --from=builder-healthcheck /dist/boot/bin /dist/boot/bin
COPY          --from=builder-goello /dist/boot/bin /dist/boot/bin
#COPY          --from=builder-caddy /dist/boot/bin /dist/boot/bin
#COPY          --from=builder-stargz     /dist/boot/bin /dist/boot/bin
#COPY          --from=builder-containerd /dist/boot/bin /dist/boot/bin
COPY          --from=builder-idmap      /dist /dist
COPY          --from=builder-rootless   /dist /dist
COPY          --from=builder-buildkit   /dist /dist
COPY          --from=builder-runc       /dist /dist
COPY          --from=builder-binfmt     /dist /dist

RUN           chmod 555 /dist/boot/bin/*; \
              epoch="$(date --date "$BUILD_CREATED" +%s)"; \
              find /dist/boot/bin -newermt "@$epoch" -exec touch --no-dereference --date="@$epoch" '{}' +;

#######################
# Runtime
#######################
# hadolint ignore=DL3006
FROM          $RUNTIME_BASE

USER          root

# Prepare dbus
RUN           mkdir -p /run/dbus; chown "$BUILD_UID":root /run/dbus; chmod 775 /run/dbus

# ca-certificates=20200601~deb10u1 is not necessary in itself
RUN           apt-get update -qq          && \
              apt-get install -qq --no-install-recommends \
                git=1:2.20.1-2+deb10u3 pigz=2.4-1 fuse3=3.4.1-1+deb10u1 xz-utils=5.2.4-1 \
                libnss-mdns=0.14.1-1 && \
              apt-get -qq autoremove      && \
              apt-get -qq clean           && \
              rm -rf /var/lib/apt/lists/* && \
              rm -rf /tmp/*               && \
              rm -rf /var/tmp/*

COPY          --from=builder --chown=$BUILD_UID:root /dist .
COPY          --from=builder-qemu --chown=$BUILD_UID:root /dist/boot/bin/* /usr/bin
COPY          --from=builder-overlay --chown=$BUILD_UID:root /dist/boot/bin/* /usr/bin

RUN           chown root:root /boot/bin/newuidmap \
                && chown root:root /boot/bin/newgidmap \
                && chmod u+s /boot/bin/newuidmap \
                && chmod u+s /boot/bin/newgidmap

# hadolint ignore=DL4006
RUN           echo dubo-dubon-duponey:100000:65536 | tee /etc/subuid | tee /etc/subgid

USER          dubo-dubon-duponey

### Front server configuration
# Port to use
ENV           PORT=4242
EXPOSE        4242

### mDNS broadcasting
# Enable/disable mDNS support
ENV           MDNS_ENABLED=false
# Name is used as a short description for the service
ENV           MDNS_NAME="Buildkit mDNS display name"
# The service will be annonced and reachable at $MDNS_HOST.local
ENV           MDNS_HOST=buildkit
# Type to advertise
ENV           MDNS_TYPE=_buildkit._tcp

ENV           XDG_RUNTIME_DIR=/data

VOLUME        /data
VOLUME        /certs
VOLUME        /run

# System constants, unlikely to ever require modifications in normal use
#ENV           HEALTHCHECK_URL=http://127.0.0.1:10042/healthcheck

HEALTHCHECK   --interval=90s --timeout=30s --start-period=90s --retries=1 CMD BUILDKIT_HOST=tcp://127.0.0.1:$PORT buildctl debug workers || exit 1


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
