ARG           FROM_IMAGE_BUILDER=dubodubonduponey/base@sha256:b51f084380bc1bd2b665840317b6f19ccc844ee2fc7e700bf8633d95deba2819
ARG           FROM_IMAGE_RUNTIME=dubodubonduponey/base@sha256:d28e8eed3e87e8dc5afdd56367d3cf2da12a0003d064b5c62405afbe4725ee99

# Cross notes:
# https://github.com/docker/golang-cross/blob/master/Dockerfile
# https://github.com/troian/golang-cross-example/blob/master/.goreleaser.yaml
#

#RUN echo "package main" > /main.go; echo "func main(){}" >> /main.go

# Alternatively, try static-pie
#RUN           export GO_TAGS="osusergo netgo static_build"; \
#              export GO_LD_FLAGS="-s -w -extldflags \"-fno-PIC -static\""; \
#              env GOARM="$(printf "%s" "$TARGETVARIANT" | tr -d v)" go build -trimpath $(if [ "$CGO_ENABLED" = 1 ]; then printf "%s" "-buildmode pie"; fi) \
#                -ldflags "$GO_LD_FLAGS" -tags "$GO_TAGS" -o /dist/boot/bin/"$GO_BUILD_OUTPUT"_static "/main.go"

# RUN ls -lA /dist/boot/bin; ldd /dist/boot/bin/*; exit 1

#Linux:
#-ldflags '-extldflags "-fno-PIC -static"' -buildmode pie -tags 'osusergo netgo static_build'
#windows: -tags netgo -ldflags '-H=windowsgui -extldflags "-static"'
#linux/bsd: -tags netgo -ldflags '-extldflags "-static"'
#macos: -ldflags '-s -extldflags "-sectcreate __TEXT __info_plist Info.plist"'
#android: -ldflags -s
#GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o test -ldflags '-extldflags "-f no-PIC -static"' -buildmode pie -tags 'osusergo netgo static_build' test.go

#https://golang.org/doc/go1.15#linker
#https://github.com/golang/go/issues/26492#issuecomment-702746919
#-linkmode=external


#readonly GO_LDFLAGS='-linkmode=external -extldflags "-fno-PIC -static -Wl,-z,stack-size=8388608" -buildid='
#readonly GO_STATICTAGS='osusergo netgo static_build'

#go build -ldflags "${GO_LDFLAGS}" -buildmode pie -tags "${GO_STATICTAGS}" "$@"

#CGO_ENABLED=1 go build -buildmode=pie -tags 'osusergo,netgo,static,' -ldflags '-linkmode=external -extldflags "-static-pie"' .

#              export PKG_CONFIG_SYSROOT_DIR=/usr/$DEB_TARGET_MULTIARCH; \
# --sysroot=/usr/$DEB_TARGET_MULTIARCH
# PKG_CONFIG_SYSROOT_DIR=/usr/$DEB_TARGET_MULTIARCH
#      - CGO_FLAGS=--sysroot=/sysroot/linux/armhf
#      - CGO_LDFLAGS=--sysroot=/sysroot/linux/armhf
#      - PKG_CONFIG_SYSROOT_DIR=/sysroot/linux/armhf
#      - PKG_CONFIG_PATH=/sysroot/linux/armhf/opt/vc/lib/pkgconfig:/sysroot/linux/armhf/usr/lib/arm-linux-gnueabihf/pkgconfig:/sysroot/linux/armhf/usr/lib/pkgconfig:/sysroot/linux/armhf/usr/local/lib/pkgconfig

# XXX can we use netgo for runc???
# 	$(GO_BUILD_STATIC) -o contrib/cmd/recvtty/recvtty ./contrib/cmd/recvtty


#######################
# Builder root - could / should be part of base builder image?
#######################
FROM          --platform=$BUILDPLATFORM $FROM_IMAGE_BUILDER                                                             AS builder-cross

# XXX port this to the base builder image
SHELL         ["/bin/bash", "-o", "errexit", "-o", "errtrace", "-o", "functrace", "-o", "nounset", "-o", "pipefail", "-c"]

RUN           --mount=type=secret,mode=0444,id=CA,dst=/etc/ssl/certs/ca-certificates.crt \
              --mount=type=secret,id=CERTIFICATE \
              --mount=type=secret,id=KEY \
              --mount=type=secret,id=PASSPHRASE \
              --mount=type=secret,mode=0444,id=GPG.gpg \
              --mount=type=secret,id=NETRC \
              --mount=type=secret,id=APT_SOURCES \
              --mount=type=secret,id=APT_OPTIONS,dst=/etc/apt/apt.conf.d/dbdbdp.conf \
              DEB_TARGET_ARCH="$(echo "$TARGETARCH$TARGETVARIANT" | sed -e "s/armv6/armel/" -e "s/armv7/armhf/" -e "s/ppc64le/ppc64el/" -e "s/386/i686/")"; \
              dpkg --add-architecture "$DEB_TARGET_ARCH"; \
              apt-get update -qq && apt-get install -qq --no-install-recommends \
                crossbuild-essential-"$DEB_TARGET_ARCH"=12.9 \
                libseccomp-dev:"$DEB_TARGET_ARCH"=2.5.1-1 && \
              rm -rf /var/lib/apt/lists/*

#######################
# Goello
#######################
FROM          --platform=$BUILDPLATFORM $FROM_IMAGE_BUILDER                                                             AS builder-goello

ARG           GIT_REPO=github.com/dubo-dubon-duponey/goello
ARG           GIT_VERSION=275a1eb
ARG           GIT_COMMIT=275a1eb5f3fc21bb4a8e8e14e8fbf45d237bbc97
ARG           GO_BUILD_SOURCE=./cmd/server
ARG           GO_BUILD_OUTPUT=goello-server
ARG           GO_LD_FLAGS="-s -w"
ARG           GO_TAGS="osusergo netgo"

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone --recurse-submodules git://"$GIT_REPO" . && git checkout "$GIT_COMMIT"
ARG           GOOS="$TARGETOS"
ARG           GOARCH="$TARGETARCH"

# hadolint ignore=SC2046
RUN           env GOARM="$(printf "%s" "$TARGETVARIANT" | tr -d v)" go build -trimpath $(if [ "$CGO_ENABLED" = 1 ]; then printf "%s" "-buildmode pie"; fi) \
                -ldflags "$GO_LD_FLAGS" -tags "$GO_TAGS" -o /dist/boot/bin/"$GO_BUILD_OUTPUT" "$GO_BUILD_SOURCE"

###################################################################
# binfmt
###################################################################
FROM          --platform=$BUILDPLATFORM $FROM_IMAGE_BUILDER                                                             AS builder-binfmt

# hadolint ignore=DL3045
COPY          build/main.go .

ARG           GO_BUILD_SOURCE="./main.go"
ARG           GO_BUILD_OUTPUT="binfmt"
ARG           GO_LD_FLAGS="-s -w"
ARG           GO_TAGS="osusergo netgo"

ARG           GOOS="$TARGETOS"
ARG           GOARCH="$TARGETARCH"

# hadolint ignore=SC2046
RUN           env GOARM="$(printf "%s" "$TARGETVARIANT" | tr -d v)" go build -trimpath $(if [ "$CGO_ENABLED" = 1 ]; then printf "%s" "-buildmode pie"; fi) \
                -ldflags "$GO_LD_FLAGS" -tags "$GO_TAGS" -o /dist/boot/bin/"$GO_BUILD_OUTPUT" "$GO_BUILD_SOURCE"

###################################################################
# Runc
###################################################################
FROM          --platform=$BUILDPLATFORM builder-cross                                                                   AS builder-runc

ARG           GIT_REPO=github.com/opencontainers/runc
ARG           GIT_VERSION=v1.0.0-rc95
ARG           GIT_COMMIT=b9ee9c6314599f1b4a7f497e1f1f856fe433d3b7

ARG           GO_BUILD_SOURCE="./"
ARG           GO_BUILD_OUTPUT="runc"
ARG           GO_LD_FLAGS="-s -w -extldflags -static -X main.version=$GIT_VERSION -X main.gitCommit=$GIT_COMMIT"
# Does not seem to need netcgo but double check
ARG           GO_TAGS="seccomp netgo osusergo cgo static_build"
ARG           CGO_ENABLED=1

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone --recurse-submodules git://"$GIT_REPO" . && git checkout "$GIT_COMMIT"
ARG           GOOS="$TARGETOS"
ARG           GOARCH="$TARGETARCH"

# hadolint ignore=SC2046
RUN           DEB_TARGET_ARCH="$(echo "$TARGETARCH$TARGETVARIANT" | sed -e "s/armv6/armel/" -e "s/armv7/armhf/" -e "s/ppc64le/ppc64el/" -e "s/386/i686/")"; \
              eval "$(dpkg-architecture -A "$DEB_TARGET_ARCH")"; \
              export PKG_CONFIG_PATH="/usr/lib/${DEB_TARGET_MULTIARCH}/pkgconfig"; \
              export CC="${DEB_TARGET_MULTIARCH}-gcc"; \
              export CXX="${DEB_TARGET_MULTIARCH}-g++"; \
              env GOARM="$(printf "%s" "$TARGETVARIANT" | tr -d v)" go build -trimpath $(if [ "$CGO_ENABLED" = 1 ]; then printf "%s" "-buildmode pie"; fi) \
                -mod=vendor \
                -ldflags "$GO_LD_FLAGS" -tags "$GO_TAGS" -o /dist/boot/bin/"$GO_BUILD_OUTPUT" "$GO_BUILD_SOURCE"

###################################################################
# Buildkit
###################################################################
FROM          --platform=$BUILDPLATFORM builder-cross                                                                   AS builder-buildkit

# Master as of June 9
ARG           GIT_REPO=github.com/moby/buildkit
ARG           GIT_VERSION=0f9f55f
ARG           GIT_COMMIT=0f9f55ff7ce061b1a089681cdc889c564bf9749b

ARG           GO_BUILD_SOURCE="./cmd/buildkitd"
ARG           GO_BUILD_OUTPUT="buildkitd"
ARG           GO_LD_FLAGS="-s -w -extldflags -static -X $GIT_REPO/version.Version=$GIT_VERSION -X $GIT_REPO/version.Revision=$GIT_COMMIT -X $GIT_REPO/version.Package=$GIT_REPO"
ARG           GO_TAGS="seccomp netcgo cgo osusergo static_build"
ARG           CGO_ENABLED=1

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone --recurse-submodules git://"$GIT_REPO" . && git checkout "$GIT_COMMIT"
ARG           GOOS="$TARGETOS"
ARG           GOARCH="$TARGETARCH"

# hadolint ignore=SC2046
RUN           DEB_TARGET_ARCH="$(echo "$TARGETARCH$TARGETVARIANT" | sed -e "s/armv6/armel/" -e "s/armv7/armhf/" -e "s/ppc64le/ppc64el/" -e "s/386/i686/")"; \
              eval "$(dpkg-architecture -A "$DEB_TARGET_ARCH")"; \
              export PKG_CONFIG_PATH="/usr/lib/${DEB_TARGET_MULTIARCH}/pkgconfig"; \
              export CC="${DEB_TARGET_MULTIARCH}-gcc"; \
              export CXX="${DEB_TARGET_MULTIARCH}-g++"; \
              env GOARM="$(printf "%s" "$TARGETVARIANT" | tr -d v)" go build -trimpath $(if [ "$CGO_ENABLED" = 1 ]; then printf "%s" "-buildmode pie"; fi) \
                -ldflags "$GO_LD_FLAGS" -tags "$GO_TAGS" -o /dist/boot/bin/"$GO_BUILD_OUTPUT" "$GO_BUILD_SOURCE"

###################################################################
# Rootless
###################################################################
FROM          --platform=$BUILDPLATFORM $FROM_IMAGE_BUILDER                                                             AS builder-rootless

# 0.14.2
ARG           GIT_REPO=github.com/rootless-containers/rootlesskit
ARG           GIT_VERSION=v0.14.2
ARG           GIT_COMMIT=4cd567642273d369adaadcbadca00880552c1778

ARG           GO_BUILD_SOURCE="./cmd/rootlesskit"
ARG           GO_BUILD_OUTPUT="rootlesskit"
ARG           GO_LD_FLAGS="-s -w"
ARG           GO_TAGS="osusergo netgo"

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone --recurse-submodules git://"$GIT_REPO" . && git checkout "$GIT_COMMIT"
ARG           GOOS="$TARGETOS"
ARG           GOARCH="$TARGETARCH"

# hadolint ignore=SC2046
RUN           env GOARM="$(printf "%s" "$TARGETVARIANT" | tr -d v)" go build -trimpath $(if [ "$CGO_ENABLED" = 1 ]; then printf "%s" "-buildmode pie"; fi) \
                -ldflags "$GO_LD_FLAGS" -tags "$GO_TAGS" -o /dist/boot/bin/"$GO_BUILD_OUTPUT" "$GO_BUILD_SOURCE"

###################################################################
# Buildctl
###################################################################
FROM          --platform=$BUILDPLATFORM builder-cross                                                                   AS builder-buildctl

# Master as of June 9
ARG           GIT_REPO=github.com/moby/buildkit
ARG           GIT_VERSION=0f9f55f
ARG           GIT_COMMIT=0f9f55ff7ce061b1a089681cdc889c564bf9749b

ARG           GO_BUILD_SOURCE="./cmd/buildctl"
ARG           GO_BUILD_OUTPUT="buildctl"
ARG           GO_LD_FLAGS="-s -w -extldflags -static -X $GIT_REPO/version.Version=$GIT_VERSION -X $GIT_REPO/version.Revision=$GIT_COMMIT -X $GIT_REPO/version.Package=$GIT_REPO"
ARG           GO_TAGS="netcgo cgo osusergo static_build"
ARG           CGO_ENABLED=1

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone --recurse-submodules git://"$GIT_REPO" . && git checkout "$GIT_COMMIT"
ARG           GOOS="$TARGETOS"
ARG           GOARCH="$TARGETARCH"

# hadolint ignore=SC2046
RUN           DEB_TARGET_ARCH="$(echo "$TARGETARCH$TARGETVARIANT" | sed -e "s/armv6/armel/" -e "s/armv7/armhf/" -e "s/ppc64le/ppc64el/" -e "s/386/i686/")"; \
              eval "$(dpkg-architecture -A "$DEB_TARGET_ARCH")"; \
              export CC="${DEB_TARGET_MULTIARCH}-gcc"; \
              export CXX="${DEB_TARGET_MULTIARCH}-g++"; \
              env GOARM="$(printf "%s" "$TARGETVARIANT" | tr -d v)" go build -trimpath $(if [ "$CGO_ENABLED" = 1 ]; then printf "%s" "-buildmode pie"; fi) \
                -ldflags "$GO_LD_FLAGS" -tags "$GO_TAGS" -o /dist/boot/bin/"$GO_BUILD_OUTPUT" "$GO_BUILD_SOURCE"


###################################################################
# newuid
###################################################################
# XXX make it static?
FROM          --platform=$BUILDPLATFORM builder-cross                                                                   AS builder-idmap
ARG           GIT_REPO=github.com/shadow-maint/shadow
ARG           GIT_VERSION=v4.8.1
ARG           GIT_COMMIT=2cc7da6058152ec0cd338d4e15d29bd7124ae3d7

WORKDIR       /shadow
RUN           git clone --recurse-submodules git://"$GIT_REPO" . && git checkout "$GIT_COMMIT"

RUN           --mount=type=secret,mode=0444,id=CA,dst=/etc/ssl/certs/ca-certificates.crt \
              --mount=type=secret,id=CERTIFICATE \
              --mount=type=secret,id=KEY \
              --mount=type=secret,id=PASSPHRASE \
              --mount=type=secret,mode=0444,id=GPG.gpg \
              --mount=type=secret,id=NETRC \
              --mount=type=secret,id=APT_SOURCES \
              --mount=type=secret,id=APT_OPTIONS,dst=/etc/apt/apt.conf.d/dbdbdp.conf \
              DEB_TARGET_ARCH="$(echo "$TARGETARCH$TARGETVARIANT" | sed -e "s/armv6/armel/" -e "s/armv7/armhf/" -e "s/ppc64le/ppc64el/" -e "s/386/i686/")"; \
              apt-get update && \
              apt-get --no-install-recommends install -qq \
                autopoint=0.21-4 \
                gettext=0.21-4 \
                libcap2-bin=1:2.44-1 \
                byacc=20140715-1+b1 \
                xsltproc=1.1.34-4 \
                libcap-dev:"$DEB_TARGET_ARCH"=1:2.44-1 \
                libcrypt-dev:"$DEB_TARGET_ARCH"=1:4.4.18-4

RUN           DEB_TARGET_ARCH="$(echo "$TARGETARCH$TARGETVARIANT" | sed -e "s/armv6/armel/" -e "s/armv7/armhf/" -e "s/ppc64le/ppc64el/" -e "s/386/i686/")"; \
              eval "$(dpkg-architecture -A "$DEB_TARGET_ARCH")"; \
              export CC="${DEB_TARGET_MULTIARCH}-gcc"; \
              ./autogen.sh --disable-nls --disable-man --without-audit --without-selinux --without-acl --without-attr --without-tcb --without-nscd --without-btrfs \
                --with-fcaps \
                && make -j "$(getconf _NPROCESSORS_ONLN)" \
                && mkdir -p /dist/boot/bin \
                && cp src/newuidmap src/newgidmap /dist/boot/bin
              # XXX MISSING? --host $(clang --print-target-triple) \

###################################################################
# Stargz
###################################################################
FROM          --platform=$BUILDPLATFORM $FROM_IMAGE_BUILDER                                                             AS builder-stargz

# XXX possibly does not need cgo
ARG           GIT_REPO=github.com/containerd/stargz-snapshotter
ARG           GIT_VERSION=v0.6.0
ARG           GIT_COMMIT=cb2f52ae082afc25c704de7ada28b5b89b1dbc4a

ARG           GO_BUILD_SOURCE="./cmd/containerd-stargz-grpc"
ARG           GO_BUILD_OUTPUT="containerd-stargz-grpc"
ARG           GO_LD_FLAGS="-s -w -extldflags -static"
ARG           GO_TAGS="netcgo cgo osusergo static_build"
ARG           CGO_ENABLED=1

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone --recurse-submodules git://"$GIT_REPO" . && git checkout "$GIT_COMMIT"
ARG           GOOS="$TARGETOS"
ARG           GOARCH="$TARGETARCH"

# hadolint ignore=SC2046
RUN           DEB_TARGET_ARCH="$(echo "$TARGETARCH$TARGETVARIANT" | sed -e "s/armv6/armel/" -e "s/armv7/armhf/" -e "s/ppc64le/ppc64el/" -e "s/386/i686/")"; \
              eval "$(dpkg-architecture -A "$DEB_TARGET_ARCH")"; \
              export CC="${DEB_TARGET_MULTIARCH}-gcc"; \
              export CXX="${DEB_TARGET_MULTIARCH}-g++"; \
              env GOARM="$(printf "%s" "$TARGETVARIANT" | tr -d v)" go build -trimpath $(if [ "$CGO_ENABLED" = 1 ]; then printf "%s" "-buildmode pie"; fi) \
                -ldflags "$GO_LD_FLAGS" -tags "$GO_TAGS" -o /dist/boot/bin/"$GO_BUILD_OUTPUT" "$GO_BUILD_SOURCE"; \
              env GOARM="$(printf "%s" "$TARGETVARIANT" | tr -d v)" go build -trimpath $(if [ "$CGO_ENABLED" = 1 ]; then printf "%s" "-buildmode pie"; fi) \
                -ldflags "$GO_LD_FLAGS" -tags "$GO_TAGS" -o /dist/boot/bin/ctr-remote ctr-remote

###################################################################
# Containerd
###################################################################
FROM          --platform=$BUILDPLATFORM $FROM_IMAGE_BUILDER                                                             AS builder-containerd

ARG           GIT_REPO=github.com/containerd/containerd
ARG           GIT_VERSION=1.5.2
ARG           GIT_COMMIT=36cc874494a56a253cd181a1a685b44b58a2e34a

ARG           GO_BUILD_SOURCE="./cmd/containerd-shim"
ARG           GO_BUILD_OUTPUT="containerd-shim"
ARG           GO_LD_FLAGS="-s -w -extldflags -static -X $GIT_REPO/version.Version=$GIT_VERSION -X $GIT_REPO/version.Revision=$GIT_COMMIT -X $GIT_REPO/version.Package=$GIT_REPO"
ARG           GO_TAGS="netcgo cgo osusergo static_build apparmor no_btrfs no_devmapper no_cri"
ARG           CGO_ENABLED=1

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone --recurse-submodules git://"$GIT_REPO" . && git checkout "$GIT_COMMIT"
ARG           GOOS="$TARGETOS"
ARG           GOARCH="$TARGETARCH"

# XXX do we still need auto?
# hadolint ignore=SC2046
RUN           export GO111MODULE=auto; \
              DEB_TARGET_ARCH="$(echo "$TARGETARCH$TARGETVARIANT" | sed -e "s/armv6/armel/" -e "s/armv7/armhf/" -e "s/ppc64le/ppc64el/" -e "s/386/i686/")"; \
              eval "$(dpkg-architecture -A "$DEB_TARGET_ARCH")"; \
              export CC="${DEB_TARGET_MULTIARCH}-gcc"; \
              export CXX="${DEB_TARGET_MULTIARCH}-g++"; \
              env GOARM="$(printf "%s" "$TARGETVARIANT" | tr -d v)" go build -trimpath $(if [ "$CGO_ENABLED" = 1 ]; then printf "%s" "-buildmode pie"; fi) \
                -ldflags "$GO_LD_FLAGS" -tags "$GO_TAGS" -o /dist/boot/bin/"$GO_BUILD_OUTPUT" "$GO_BUILD_SOURCE"; \
              env GOARM="$(printf "%s" "$TARGETVARIANT" | tr -d v)" go build -trimpath $(if [ "$CGO_ENABLED" = 1 ]; then printf "%s" "-buildmode pie"; fi) \
                -ldflags "$GO_LD_FLAGS" -tags "$GO_TAGS" -o /dist/boot/bin/containerd-shim-runc-v2 ./cmd/containerd-shim-runc-v2; \
              env GOARM="$(printf "%s" "$TARGETVARIANT" | tr -d v)" go build -trimpath $(if [ "$CGO_ENABLED" = 1 ]; then printf "%s" "-buildmode pie"; fi) \
                -ldflags "$GO_LD_FLAGS" -tags "$GO_TAGS" -o /dist/boot/bin/ctr ./cmd/ctr; \
              env GOARM="$(printf "%s" "$TARGETVARIANT" | tr -d v)" go build -trimpath $(if [ "$CGO_ENABLED" = 1 ]; then printf "%s" "-buildmode pie"; fi) \
                -ldflags "$GO_LD_FLAGS" -tags "$GO_TAGS" -o /dist/boot/bin/containerd ./cmd/containerd


###################################################################
# QEMU
###################################################################
FROM          $FROM_IMAGE_BUILDER                                                                                       AS builder-qemu-nocross

# XXX this is abandonware at this point
# 4.1.0
#ARG           GIT_REPO=github.com/moby/qemu
#ARG           GIT_COMMIT=2d04bf7914ad68a6f83b8a480948e604bbe8fea2
# https://github.com/qemu/qemu/compare/master...moby:moby/master
# There is very little in here

ARG           GIT_REPO=github.com/qemu/qemu
ARG           GIT_VERSION=v4.2.1
ARG           GIT_COMMIT=6cdf8c4efa073eac7d5f9894329e2d07743c2955

# v5.2.0
#ARG           GIT_REPO=github.com/qemu/qemu
#ARG           GIT_COMMIT=553032db17440f8de011390e5a1cfddd13751b0b
#ARG           GIT_VERSION=v5.2.0

# v6.0.0
#ARG           GIT_REPO=github.com/qemu/qemu
#ARG           GIT_COMMIT=609d7596524ab204ccd71ef42c9eee4c7c338ea4
#ARG           GIT_VERSION=v6.0.0

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone --recurse-submodules git://"$GIT_REPO" . && git checkout "$GIT_COMMIT"

# hadolint ignore=SC2046
RUN           --mount=type=secret,mode=0444,id=CA,dst=/etc/ssl/certs/ca-certificates.crt \
              --mount=type=secret,id=CERTIFICATE \
              --mount=type=secret,id=KEY \
              --mount=type=secret,id=PASSPHRASE \
              --mount=type=secret,mode=0444,id=GPG.gpg \
              --mount=type=secret,id=NETRC \
              --mount=type=secret,id=APT_SOURCES \
              --mount=type=secret,id=APT_OPTIONS,dst=/etc/apt/apt.conf.d/dbdbdp.conf \
              apt-get update -qq && \
              apt-get install -qq --no-install-recommends \
                  build-essential=12.9 \
                  bc \
                  ca-certificates \
                  ccache \
                  clang \
                  dbus \
                  gdb-multiarch \
                  gettext \
                  git \
                  libncurses5-dev \
                  ninja-build \
                  pkg-config \
                  psmisc \
                  python3 \
                  python3-sphinx \
                  python3-sphinx-rtd-theme \
                  libglib2.0-dev=2.66.8-1 \
                  $(apt-get -s build-dep --no-install-recommends --arch-only qemu | grep -E ^Inst | grep -F '[all]' | cut -d\  -f2)
# XXX could remove python if no doc?

# glib-2.48 gthread-2.0

#                  libglib2.0-dev=2.58.3-2+deb10u2 \
#                  libfdt-dev zlib1g-dev libnfs-dev libiscsi-dev \
#                   libpixman-1-dev=0.36.0-1 \

#                  libtool \
#                  git \
#                  pkg-config \
#                  python

#RUN           scripts/git-submodule.sh update \
#              ui/keycodemapdb \
#              tests/fp/berkeley-testfloat-3 \
#              tests/fp/berkeley-softfloat-3 \
#              dtc

# XXX?              mkdir -p /dist/boot
RUN           ./configure \
                --prefix=/dist/boot \
                --with-pkgversion=$GIT_VERSION \
                --enable-linux-user \
                --disable-system \
                --static \
                --disable-blobs \
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
                --disable-bluez \
                --target-list="aarch64-linux-user arm-linux-user ppc64le-linux-user s390x-linux-user riscv64-linux-user"

RUN           make -j "$(getconf _NPROCESSORS_ONLN)"

RUN           make install
              # ; \
              # mkdir -p /dist/boot/bin/ && cp /usr/bin/qemu-* /dist/boot/bin/



###################################################################
# QEMU cross
###################################################################
FROM          --platform=$BUILDPLATFORM builder-cross                                                                   AS builder-qemu

ARG           GIT_REPO=github.com/qemu/qemu
ARG           GIT_VERSION=v4.2.1
ARG           GIT_COMMIT=6cdf8c4efa073eac7d5f9894329e2d07743c2955

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone --recurse-submodules git://"$GIT_REPO" . && git checkout "$GIT_COMMIT"

# XXX FIXME
# hadolint ignore=SC2046
RUN           --mount=type=secret,mode=0444,id=CA,dst=/etc/ssl/certs/ca-certificates.crt \
              --mount=type=secret,id=CERTIFICATE \
              --mount=type=secret,id=KEY \
              --mount=type=secret,id=PASSPHRASE \
              --mount=type=secret,mode=0444,id=GPG.gpg \
              --mount=type=secret,id=NETRC \
              --mount=type=secret,id=APT_SOURCES \
              --mount=type=secret,id=APT_OPTIONS,dst=/etc/apt/apt.conf.d/dbdbdp.conf \
              DEB_TARGET_ARCH="$(echo "$TARGETARCH$TARGETVARIANT" | sed -e "s/armv6/armel/" -e "s/armv7/armhf/" -e "s/ppc64le/ppc64el/" -e "s/386/i686/")"; \
              apt-get update -qq && \
              apt-get install -qq --no-install-recommends \
                  libncurses5-dev:"$DEB_TARGET_ARCH" \
                  libglib2.0-dev:"$DEB_TARGET_ARCH"=2.66.8-1 \
                  build-essential=12.9 \
                  bc \
                  ca-certificates \
                  ccache \
                  clang \
                  dbus \
                  gdb-multiarch \
                  gettext \
                  git \
                  ninja-build \
                  pkg-config \
                  psmisc \
                  $(apt-get -s build-dep --no-install-recommends --arch-only qemu | grep -E ^Inst | grep -F '[all]' | cut -d\  -f2)

# [--extra-cflags=-mthreads]
# PKG_CONFIG_LIBDIR=
RUN           DEB_TARGET_ARCH="$(echo "$TARGETARCH$TARGETVARIANT" | sed -e "s/armv6/armel/" -e "s/armv7/armhf/" -e "s/ppc64le/ppc64el/" -e "s/386/i686/")"; \
              eval "$(dpkg-architecture -A "$DEB_TARGET_ARCH")"; \
              export PKG_CONFIG_PATH="/usr/lib/${DEB_TARGET_MULTIARCH}/pkgconfig"; \
              export CC="${DEB_TARGET_MULTIARCH}-gcc"; \
              export CXX="${DEB_TARGET_MULTIARCH}-g++"; \
              ./configure \
                --prefix=/dist/boot \
                --with-pkgversion=$GIT_VERSION \
                --enable-linux-user \
                --disable-system \
                --static \
                --disable-blobs \
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
                --disable-bluez \
                --cross-prefix="${DEB_TARGET_MULTIARCH}-" \
                --target-list="aarch64-linux-user arm-linux-user ppc64le-linux-user s390x-linux-user riscv64-linux-user i386-linux-user x86_64-linux-user"
# XXX ideally, would avoid building the one matching the targetplatform...

RUN           make -j "$(getconf _NPROCESSORS_ONLN)"

RUN           make install
              # ; \
              # mkdir -p /dist/boot/bin/ && cp /usr/bin/qemu-* /dist/boot/bin/




FROM          --platform=$BUILDPLATFORM $FROM_IMAGE_BUILDER                                                             AS builder-fuse-overlay

ARG           FUSEOVERLAYFS_VERSION=v1.5.0

RUN           echo "$TARGETARCH" | sed -e s/^amd64$/x86_64/ -e s/^arm64$/aarch64/ -e s/^arm$/armv7l/ > /uname_m && \
                mkdir -p /dist/boot/bin && \
                curl -sSL -o /dist/boot/bin/fuse-overlayfs https://github.com/containers/fuse-overlayfs/releases/download/"${FUSEOVERLAYFS_VERSION}"/fuse-overlayfs-"$(cat /uname_m)" && \
                chmod +x /dist/boot/bin/fuse-overlayfs


# gcc pkgconf libfuse3-dev
# ./autogen.sh
# CC=$(/cross.sh cross-prefix)-gcc LD=$(/cross.sh cross-prefix)-ld LIBS="-ldl" LDFLAGS="-static" ./configure && \
#  make && mkdir /out && cp fuse-overlayfs /out && \
#  file /out/fuse-overlayfs | grep "statically linked"

#######################
# Builder assembly
#######################
FROM          $FROM_IMAGE_BUILDER                                                                                       AS builder

#COPY          --from=builder-healthcheck /dist/boot/bin /dist/boot/bin
COPY          --from=builder-goello         /dist/boot/bin /dist/boot/bin
COPY          --from=builder-binfmt         /dist /dist
COPY          --from=builder-rootless       /dist /dist
COPY          --from=builder-runc           /dist /dist

# TMP remove
COPY          --from=builder-fuse-overlay --chown=$BUILD_UID:root /dist /dist
COPY          --from=builder-qemu --chown=$BUILD_UID:root /dist /dist

RUN           for i in /dist/boot/bin/*; do file "$i" | grep "statically linked" || { echo "$i is NOT static"; ldd "$i"; exit 1; }; done

COPY          --from=builder-idmap          /dist /dist
COPY          --from=builder-buildctl       /dist /dist
COPY          --from=builder-buildkit       /dist /dist

#COPY          --from=builder-caddy /dist/boot/bin /dist/boot/bin
#COPY          --from=builder-stargz     /dist/boot/bin /dist/boot/bin
#COPY          --from=builder-containerd /dist/boot/bin /dist/boot/bin

RUN           chmod 555 /dist/boot/bin/*; \
              epoch="$(date --date "$BUILD_CREATED" +%s)"; \
              find /dist/boot/bin -newermt "@$epoch" -exec touch --no-dereference --date="@$epoch" '{}' +;

#######################
# Runtime
#######################
FROM          $FROM_IMAGE_RUNTIME

USER          root

# Prepare dbus
RUN           mkdir -p /run/dbus; chown "$BUILD_UID":root /run/dbus; chmod 775 /run/dbus

# ca-certificates=20200601~deb10u1 is not necessary in itself
RUN           --mount=type=secret,mode=0444,id=CA,dst=/etc/ssl/certs/ca-certificates.crt \
              --mount=type=secret,id=CERTIFICATE \
              --mount=type=secret,id=KEY \
              --mount=type=secret,id=PASSPHRASE \
              --mount=type=secret,mode=0444,id=GPG.gpg \
              --mount=type=secret,id=NETRC \
              --mount=type=secret,id=APT_SOURCES \
              --mount=type=secret,id=APT_OPTIONS,dst=/etc/apt/apt.conf.d/dbdbdp.conf \
              apt-get update -qq && apt-get install -qq --no-install-recommends \
                git=1:2.30.2-1 \
                pigz=2.6-1 \
                fuse3=3.10.3-1 \
                xz-utils=5.2.5-2 \
                libnss-mdns=0.14.1-2 && \
              apt-get -qq autoremove      && \
              apt-get -qq clean           && \
              rm -rf /var/lib/apt/lists/* && \
              rm -rf /tmp/*               && \
              rm -rf /var/tmp/*

COPY          --from=builder --chown=$BUILD_UID:root /dist /
COPY          --from=builder-qemu --chown=$BUILD_UID:root /dist/boot/bin/* /usr/bin
COPY          --from=builder-fuse-overlay --chown=$BUILD_UID:root /dist/boot/bin/* /usr/bin

RUN           chown root:root /boot/bin/newuidmap \
                && chown root:root /boot/bin/newgidmap \
                && chmod u+s /boot/bin/newuidmap \
                && chmod u+s /boot/bin/newgidmap

RUN           echo dubo-dubon-duponey:100000:65536 | tee /etc/subuid | tee /etc/subgid

USER          dubo-dubon-duponey

### Front server configuration
# Port to use
ENV           PORT=4242
EXPOSE        4242

# XXX temporary until we replace caddy
# Log verbosity for
ENV           LOG_LEVEL="warn"
# Domain name to serve
ENV           DOMAIN="buildkit.local"
# Control wether tls is going to be "internal" (eg: self-signed), or alternatively an email address to enable letsencrypt
ENV           TLS=""

# Realm in case access is authenticated
ENV           REALM="My Precious Realm"
# Provide username and password here (call the container with the "hash" command to generate a properly encrypted password, otherwise, a random one will be generated)
ENV           USERNAME=""
ENV           PASSWORD=""

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
