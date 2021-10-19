ARG           FROM_REGISTRY=ghcr.io/dubo-dubon-duponey

ARG           FROM_IMAGE_BUILDER=base:builder-bullseye-2021-10-15@sha256:33e021267790132e63be2cea08e77d64ec5d0434355734e94f8ff2d90c6f8944
ARG           FROM_IMAGE_AUDITOR=base:auditor-bullseye-2021-10-15@sha256:eb822683575d68ccbdf62b092e1715c676b9650a695d8c0235db4ed5de3e8534
ARG           FROM_IMAGE_RUNTIME=base:runtime-bullseye-2021-10-15@sha256:7072702dab130c1bbff5e5c4a0adac9c9f2ef59614f24e7ee43d8730fae2764c
ARG           FROM_IMAGE_TOOLS=tools:linux-bullseye-2021-10-15@sha256:e8ec2d1d185177605736ba594027f27334e68d7984bbfe708a0b37f4b6f2dbd7

FROM          $FROM_REGISTRY/$FROM_IMAGE_TOOLS                                                                          AS builder-tools
# XXX grrr
FROM          $FROM_REGISTRY/tools:linux-dev-latest                                                                     AS builder-tools-dev

#######################
# Fetchers
#######################
FROM          --platform=$BUILDPLATFORM $FROM_REGISTRY/$FROM_IMAGE_BUILDER                                              AS fetcher-qemu

ARG           GIT_REPO=github.com/qemu/qemu
ARG           GIT_VERSION=v6.1.0
ARG           GIT_COMMIT=f9baca549e44791be0dd98de15add3d8452a8af0

RUN           git clone --recurse-submodules git://"$GIT_REPO" .; git checkout "$GIT_COMMIT"

# hadolint ignore=DL3009
RUN           --mount=type=secret,uid=100,id=CA \
              --mount=type=secret,uid=100,id=CERTIFICATE \
              --mount=type=secret,uid=100,id=KEY \
              --mount=type=secret,uid=100,id=GPG.gpg \
              --mount=type=secret,id=NETRC \
              --mount=type=secret,id=APT_SOURCES \
              --mount=type=secret,id=APT_CONFIG \
              apt-get update -qq; \
              apt-get install -qq --no-install-recommends ninja-build=1.10.1-1; \
              for architecture in armel armhf arm64 ppc64el i386 s390x amd64; do \
                apt-get install -qq --no-install-recommends \
                  libglib2.0-dev:"$architecture"=2.66.8-1 \
                  libaio-dev:"$architecture"=0.3.112-9 \
                  libcap-ng-dev:"$architecture"=0.7.9-2.2+b1 \
                  libseccomp-dev:"$architecture"=2.5.1-1 \
                  zlib1g-dev:"$architecture"=1:1.2.11.dfsg-2; \
              done

FROM          --platform=$BUILDPLATFORM $FROM_REGISTRY/$FROM_IMAGE_BUILDER                                              AS fetcher-binfmt

ARG           GIT_REPO=github.com/tonistiigi/binfmt
ARG           GIT_VERSION=0a2d7e3
ARG           GIT_COMMIT=0a2d7e397705782ab543b3c9a650d4bf8c70902a

ENV           WITH_BUILD_SOURCE="./cmd/binfmt"
ENV           WITH_BUILD_OUTPUT="binfmt"
ENV           WITH_LDFLAGS="-X main.revision=${GIT_COMMIT} -X main.qemuVersion=${GIT_VERSION}"

RUN           git clone --recurse-submodules git://"$GIT_REPO" .; git checkout "$GIT_COMMIT"
RUN           --mount=type=secret,id=CA \
              --mount=type=secret,id=NETRC \
              [[ "${GOFLAGS:-}" == *-mod=vendor* ]] || go mod download

FROM          --platform=$BUILDPLATFORM $FROM_REGISTRY/$FROM_IMAGE_BUILDER                                              AS fetcher-runc

ARG           GIT_REPO=github.com/opencontainers/runc
ARG           GIT_VERSION=v1.0.2
ARG           GIT_COMMIT=52b36a2dd837e8462de8e01458bf02cf9eea47dd

ENV           WITH_BUILD_SOURCE="./"
ENV           WITH_BUILD_OUTPUT="runc"
ENV           WITH_LDFLAGS="-X main.version=$GIT_VERSION -X main.gitCommit=$GIT_COMMIT"
ENV           WITH_TAGS="seccomp"

ENV           ENABLE_STATIC=true
ENV           CGO_ENABLED=1
ENV           GOFLAGS="-mod=vendor"

RUN           git clone --recurse-submodules git://"$GIT_REPO" .; git checkout "$GIT_COMMIT"
RUN           --mount=type=secret,id=CA \
              --mount=type=secret,id=NETRC \
              [[ "${GOFLAGS:-}" == *-mod=vendor* ]] || go mod download

# Requires libseccomp-dev on all target platforms
# hadolint ignore=DL3009
RUN           --mount=type=secret,uid=100,id=CA \
              --mount=type=secret,uid=100,id=CERTIFICATE \
              --mount=type=secret,uid=100,id=KEY \
              --mount=type=secret,uid=100,id=GPG.gpg \
              --mount=type=secret,id=NETRC \
              --mount=type=secret,id=APT_SOURCES \
              --mount=type=secret,id=APT_CONFIG \
              apt-get update -qq; \
              for architecture in armel armhf arm64 ppc64el i386 s390x amd64; do \
                apt-get install -qq --no-install-recommends libseccomp-dev:"$architecture"=2.5.1-1; \
              done

FROM          --platform=$BUILDPLATFORM $FROM_REGISTRY/$FROM_IMAGE_BUILDER                                              AS fetcher-buildkit

#ARG           GIT_VERSION=v0.9.0
#ARG           GIT_COMMIT=c8bb937807d405d92be91f06ce2629e6202ac7a9
# Previous good point
#ARG           GIT_VERSION=a83721a
#ARG           GIT_COMMIT=a83721aa6a2f538f4e58ada06aa76688ad39c147
# Before massive, potentially damaging cache refactor
#ARG           GIT_VERSION=f314c4b
#ARG           GIT_COMMIT=f314c4bd0375b97d711d9cfe3898463238f9fff9
# embracing it :s
ARG           GIT_REPO=github.com/moby/buildkit
ARG           GIT_VERSION=v0.9.1
ARG           GIT_COMMIT=966bcf4aa3ef397a9d6025fade18f2d59a5bf29d


ENV           WITH_BUILD_SOURCE="./cmd/buildkitd"
ENV           WITH_BUILD_OUTPUT="buildkitd"
ENV           WITH_LDFLAGS="-X $GIT_REPO/version.Version=$GIT_VERSION -X $GIT_REPO/version.Revision=$GIT_COMMIT -X $GIT_REPO/version.Package=$GIT_REPO"
ENV           WITH_TAGS="seccomp apparmor"
ENV           WITH_CGO_NET=true

ENV           ENABLE_STATIC=true
ENV           CGO_ENABLED=1
ENV           GOFLAGS="-mod=vendor"

RUN           git clone --recurse-submodules git://"$GIT_REPO" .; git checkout "$GIT_COMMIT"
RUN           --mount=type=secret,id=CA \
              --mount=type=secret,id=NETRC \
              [[ "${GOFLAGS:-}" == *-mod=vendor* ]] || go mod download

# Requires libseccomp-dev on all target platforms
# hadolint ignore=DL3009
RUN           --mount=type=secret,uid=100,id=CA \
              --mount=type=secret,uid=100,id=CERTIFICATE \
              --mount=type=secret,uid=100,id=KEY \
              --mount=type=secret,uid=100,id=GPG.gpg \
              --mount=type=secret,id=NETRC \
              --mount=type=secret,id=APT_SOURCES \
              --mount=type=secret,id=APT_CONFIG \
              apt-get update -qq; \
              for architecture in armel armhf arm64 ppc64el i386 s390x amd64; do \
                apt-get install -qq --no-install-recommends libseccomp-dev:"$architecture"=2.5.1-1; \
              done

FROM          --platform=$BUILDPLATFORM $FROM_REGISTRY/$FROM_IMAGE_BUILDER                                              AS fetcher-rootless

ARG           GIT_REPO=github.com/rootless-containers/rootlesskit
ARG           GIT_VERSION=v0.14.5
ARG           GIT_COMMIT=1216988f0e4f48a70ce849a8f690352aaeae8c13

ENV           WITH_BUILD_SOURCE="./cmd/rootlesskit"
ENV           WITH_BUILD_OUTPUT="rootlesskit"

RUN           git clone --recurse-submodules git://"$GIT_REPO" .; git checkout "$GIT_COMMIT"
RUN           --mount=type=secret,id=CA \
              --mount=type=secret,id=NETRC \
              [[ "${GOFLAGS:-}" == *-mod=vendor* ]] || go mod download

FROM          --platform=$BUILDPLATFORM $FROM_REGISTRY/$FROM_IMAGE_BUILDER                                              AS fetcher-idmap

ARG           GIT_REPO=github.com/shadow-maint/shadow
ARG           GIT_VERSION=v4.8.1
ARG           GIT_COMMIT=2cc7da6058152ec0cd338d4e15d29bd7124ae3d7

RUN           git clone --recurse-submodules git://"$GIT_REPO" .; git checkout "$GIT_COMMIT"

# hadolint ignore=DL3009
RUN           --mount=type=secret,uid=100,id=CA \
              --mount=type=secret,uid=100,id=CERTIFICATE \
              --mount=type=secret,uid=100,id=KEY \
              --mount=type=secret,uid=100,id=GPG.gpg \
              --mount=type=secret,id=NETRC \
              --mount=type=secret,id=APT_SOURCES \
              --mount=type=secret,id=APT_CONFIG \
              apt-get update -qq; \
              apt-get --no-install-recommends install -qq \
                autopoint=0.21-4 \
                gettext=0.21-4 \
                libcap2-bin=1:2.44-1 \
                byacc=20140715-1+b1 \
                xsltproc=1.1.34-4; \
              for architecture in armel armhf arm64 ppc64el i386 s390x amd64; do \
                apt-get install -qq --no-install-recommends \
                  libcap-dev:"$architecture"=1:2.44-1 \
                  libcrypt-dev:"$architecture"=1:4.4.18-4; \
              done

FROM          --platform=$BUILDPLATFORM $FROM_REGISTRY/$FROM_IMAGE_BUILDER                                              AS fetcher-stargz

ARG           GIT_REPO=github.com/containerd/stargz-snapshotter
ARG           GIT_VERSION=v0.9.0
ARG           GIT_COMMIT=8e114bcc764a2f751341162a72e4f61f43adf3ae

ENV           WITH_BUILD_SOURCE="./cmd/containerd-stargz-grpc"
ENV           WITH_BUILD_OUTPUT="containerd-stargz-grpc"

ENV           ENABLE_STATIC=true
ENV           CGO_ENABLED=1

RUN           git clone --recurse-submodules git://"$GIT_REPO" .; git checkout "$GIT_COMMIT"
RUN           --mount=type=secret,id=CA \
              --mount=type=secret,id=NETRC \
              [[ "${GOFLAGS:-}" == *-mod=vendor* ]] || go mod download

###################################################################
# binfmt
###################################################################
FROM          --platform=$BUILDPLATFORM fetcher-binfmt                                                                  AS builder-binfmt

ARG           TARGETARCH
ARG           TARGETOS
ARG           TARGETVARIANT
ENV           GOOS=$TARGETOS
ENV           GOARCH=$TARGETARCH

ENV           CGO_CFLAGS="${CFLAGS:-} ${ENABLE_PIE:+-fPIE}"
ENV           GOFLAGS="-trimpath ${ENABLE_PIE:+-buildmode=pie} ${GOFLAGS:-}"

RUN           export GOARM="$(printf "%s" "$TARGETVARIANT" | tr -d v)"; \
              [ "${CGO_ENABLED:-}" != 1 ] || { \
                eval "$(dpkg-architecture -A "$(echo "$TARGETARCH$TARGETVARIANT" | sed -e "s/^armv6$/armel/" -e "s/^armv7$/armhf/" -e "s/^ppc64le$/ppc64el/" -e "s/^386$/i386/")")"; \
                export PKG_CONFIG="${DEB_TARGET_GNU_TYPE}-pkg-config"; \
                export AR="${DEB_TARGET_GNU_TYPE}-ar"; \
                export CC="${DEB_TARGET_GNU_TYPE}-gcc"; \
                export CXX="${DEB_TARGET_GNU_TYPE}-g++"; \
                [ ! "${ENABLE_STATIC:-}" ] || { \
                  [ ! "${WITH_CGO_NET:-}" ] || { \
                    ENABLE_STATIC=; \
                    LDFLAGS="${LDFLAGS:-} -static-libgcc -static-libstdc++"; \
                  }; \
                  [ "$GOARCH" == "amd64" ] || [ "$GOARCH" == "arm64" ] || [ "${ENABLE_PIE:-}" != true ] || ENABLE_STATIC=; \
                }; \
                WITH_LDFLAGS="${WITH_LDFLAGS:-} -linkmode=external -extld="$CC" -extldflags \"${LDFLAGS:-} ${ENABLE_STATIC:+-static}${ENABLE_PIE:+-pie}\""; \
                WITH_TAGS="${WITH_TAGS:-} cgo ${ENABLE_STATIC:+static static_build}"; \
              }; \
              go build -ldflags "-s -w -v ${WITH_LDFLAGS:-}" -tags "${WITH_TAGS:-} net${WITH_CGO_NET:+c}go osusergo" -o /dist/boot/bin/"$WITH_BUILD_OUTPUT" "$WITH_BUILD_SOURCE"

###################################################################
# Runc
###################################################################
FROM          --platform=$BUILDPLATFORM fetcher-runc                                                                    AS builder-runc

ARG           TARGETARCH
ARG           TARGETOS
ARG           TARGETVARIANT
ENV           GOOS=$TARGETOS
ENV           GOARCH=$TARGETARCH

ENV           CGO_CFLAGS="${CFLAGS:-} ${ENABLE_PIE:+-fPIE}"
ENV           GOFLAGS="-trimpath ${ENABLE_PIE:+-buildmode=pie} ${GOFLAGS:-}"

RUN           export GOARM="$(printf "%s" "$TARGETVARIANT" | tr -d v)"; \
              [ "${CGO_ENABLED:-}" != 1 ] || { \
                eval "$(dpkg-architecture -A "$(echo "$TARGETARCH$TARGETVARIANT" | sed -e "s/^armv6$/armel/" -e "s/^armv7$/armhf/" -e "s/^ppc64le$/ppc64el/" -e "s/^386$/i386/")")"; \
                export PKG_CONFIG="${DEB_TARGET_GNU_TYPE}-pkg-config"; \
                export AR="${DEB_TARGET_GNU_TYPE}-ar"; \
                export CC="${DEB_TARGET_GNU_TYPE}-gcc"; \
                export CXX="${DEB_TARGET_GNU_TYPE}-g++"; \
                [ ! "${ENABLE_STATIC:-}" ] || { \
                  [ ! "${WITH_CGO_NET:-}" ] || { \
                    ENABLE_STATIC=; \
                    LDFLAGS="${LDFLAGS:-} -static-libgcc -static-libstdc++"; \
                  }; \
                  [ "$GOARCH" == "amd64" ] || [ "$GOARCH" == "arm64" ] || [ "${ENABLE_PIE:-}" != true ] || ENABLE_STATIC=; \
                }; \
                WITH_LDFLAGS="${WITH_LDFLAGS:-} -linkmode=external -extld="$CC" -extldflags \"${LDFLAGS:-} ${ENABLE_STATIC:+-static}${ENABLE_PIE:+-pie}\""; \
                WITH_TAGS="${WITH_TAGS:-} cgo ${ENABLE_STATIC:+static static_build}"; \
              }; \
              go build -ldflags "-s -w -v ${WITH_LDFLAGS:-}" -tags "${WITH_TAGS:-} net${WITH_CGO_NET:+c}go osusergo" -o /dist/boot/bin/"$WITH_BUILD_OUTPUT" "$WITH_BUILD_SOURCE"

FROM          --platform=$BUILDPLATFORM fetcher-buildkit                                                                AS builder-buildkit

ARG           TARGETARCH
ARG           TARGETOS
ARG           TARGETVARIANT
ENV           GOOS=$TARGETOS
ENV           GOARCH=$TARGETARCH

ENV           CGO_CFLAGS="${CFLAGS:-} ${ENABLE_PIE:+-fPIE}"
ENV           GOFLAGS="-trimpath ${ENABLE_PIE:+-buildmode=pie} ${GOFLAGS:-}"

RUN           export GOARM="$(printf "%s" "$TARGETVARIANT" | tr -d v)"; \
              [ "${CGO_ENABLED:-}" != 1 ] || { \
                eval "$(dpkg-architecture -A "$(echo "$TARGETARCH$TARGETVARIANT" | sed -e "s/^armv6$/armel/" -e "s/^armv7$/armhf/" -e "s/^ppc64le$/ppc64el/" -e "s/^386$/i386/")")"; \
                export PKG_CONFIG="${DEB_TARGET_GNU_TYPE}-pkg-config"; \
                export AR="${DEB_TARGET_GNU_TYPE}-ar"; \
                export CC="${DEB_TARGET_GNU_TYPE}-gcc"; \
                export CXX="${DEB_TARGET_GNU_TYPE}-g++"; \
                [ ! "${ENABLE_STATIC:-}" ] || { \
                  [ ! "${WITH_CGO_NET:-}" ] || { \
                    ENABLE_STATIC=; \
                    LDFLAGS="${LDFLAGS:-} -static-libgcc -static-libstdc++"; \
                  }; \
                  [ "$GOARCH" == "amd64" ] || [ "$GOARCH" == "arm64" ] || [ "${ENABLE_PIE:-}" != true ] || ENABLE_STATIC=; \
                }; \
                WITH_LDFLAGS="${WITH_LDFLAGS:-} -linkmode=external -extld="$CC" -extldflags \"${LDFLAGS:-} ${ENABLE_STATIC:+-static}${ENABLE_PIE:+-pie}\""; \
                WITH_TAGS="${WITH_TAGS:-} cgo ${ENABLE_STATIC:+static static_build}"; \
              }; \
              go build -ldflags "-s -w -v ${WITH_LDFLAGS:-}" -tags "${WITH_TAGS:-} net${WITH_CGO_NET:+c}go osusergo" -o /dist/boot/bin/"$WITH_BUILD_OUTPUT" "$WITH_BUILD_SOURCE"

###################################################################
# Rootless
###################################################################
FROM          --platform=$BUILDPLATFORM fetcher-rootless                                                                AS builder-rootless

ARG           TARGETARCH
ARG           TARGETOS
ARG           TARGETVARIANT
ENV           GOOS=$TARGETOS
ENV           GOARCH=$TARGETARCH

ENV           CGO_CFLAGS="${CFLAGS:-} ${ENABLE_PIE:+-fPIE}"
ENV           GOFLAGS="-trimpath ${ENABLE_PIE:+-buildmode=pie} ${GOFLAGS:-}"

RUN           export GOARM="$(printf "%s" "$TARGETVARIANT" | tr -d v)"; \
              [ "${CGO_ENABLED:-}" != 1 ] || { \
                eval "$(dpkg-architecture -A "$(echo "$TARGETARCH$TARGETVARIANT" | sed -e "s/^armv6$/armel/" -e "s/^armv7$/armhf/" -e "s/^ppc64le$/ppc64el/" -e "s/^386$/i386/")")"; \
                export PKG_CONFIG="${DEB_TARGET_GNU_TYPE}-pkg-config"; \
                export AR="${DEB_TARGET_GNU_TYPE}-ar"; \
                export CC="${DEB_TARGET_GNU_TYPE}-gcc"; \
                export CXX="${DEB_TARGET_GNU_TYPE}-g++"; \
                [ ! "${ENABLE_STATIC:-}" ] || { \
                  [ ! "${WITH_CGO_NET:-}" ] || { \
                    ENABLE_STATIC=; \
                    LDFLAGS="${LDFLAGS:-} -static-libgcc -static-libstdc++"; \
                  }; \
                  [ "$GOARCH" == "amd64" ] || [ "$GOARCH" == "arm64" ] || [ "${ENABLE_PIE:-}" != true ] || ENABLE_STATIC=; \
                }; \
                WITH_LDFLAGS="${WITH_LDFLAGS:-} -linkmode=external -extld="$CC" -extldflags \"${LDFLAGS:-} ${ENABLE_STATIC:+-static}${ENABLE_PIE:+-pie}\""; \
                WITH_TAGS="${WITH_TAGS:-} cgo ${ENABLE_STATIC:+static static_build}"; \
              }; \
              go build -ldflags "-s -w -v ${WITH_LDFLAGS:-}" -tags "${WITH_TAGS:-} net${WITH_CGO_NET:+c}go osusergo" -o /dist/boot/bin/"$WITH_BUILD_OUTPUT" "$WITH_BUILD_SOURCE"

###################################################################
# newuid
###################################################################
# XXX make it static?
FROM          --platform=$BUILDPLATFORM fetcher-idmap                                                                   AS builder-idmap

RUN           eval "$(dpkg-architecture -A "$(echo "$TARGETARCH$TARGETVARIANT" | sed -e "s/^armv6$/armel/" -e "s/^armv7$/armhf/" -e "s/^ppc64le$/ppc64el/" -e "s/^386$/i386/")")"; \
              export PKG_CONFIG="${DEB_TARGET_GNU_TYPE}-pkg-config"; \
              export CC="${DEB_TARGET_GNU_TYPE}-gcc"; \
              ./autogen.sh --disable-nls --disable-man --without-audit --without-selinux --without-acl --without-attr --without-tcb --without-nscd --without-btrfs \
                --with-fcaps \
                && make -j "$(getconf _NPROCESSORS_ONLN)" \
                && mkdir -p /dist/boot/bin \
                && cp src/newuidmap src/newgidmap /dist/boot/bin
              # XXX MISSING? --host $(clang --print-target-triple) \

###################################################################
# Stargz
###################################################################
FROM          --platform=$BUILDPLATFORM fetcher-stargz                                                                  AS builder-stargz

ARG           TARGETARCH
ARG           TARGETOS
ARG           TARGETVARIANT
ENV           GOOS=$TARGETOS
ENV           GOARCH=$TARGETARCH

ENV           CGO_CFLAGS="${CFLAGS:-} ${ENABLE_PIE:+-fPIE}"
ENV           GOFLAGS="-trimpath ${ENABLE_PIE:+-buildmode=pie} ${GOFLAGS:-}"

RUN           export GOARM="$(printf "%s" "$TARGETVARIANT" | tr -d v)"; \
              [ "${CGO_ENABLED:-}" != 1 ] || { \
                eval "$(dpkg-architecture -A "$(echo "$TARGETARCH$TARGETVARIANT" | sed -e "s/^armv6$/armel/" -e "s/^armv7$/armhf/" -e "s/^ppc64le$/ppc64el/" -e "s/^386$/i386/")")"; \
                export PKG_CONFIG="${DEB_TARGET_GNU_TYPE}-pkg-config"; \
                export AR="${DEB_TARGET_GNU_TYPE}-ar"; \
                export CC="${DEB_TARGET_GNU_TYPE}-gcc"; \
                export CXX="${DEB_TARGET_GNU_TYPE}-g++"; \
                [ ! "${ENABLE_STATIC:-}" ] || { \
                  [ ! "${WITH_CGO_NET:-}" ] || { \
                    ENABLE_STATIC=; \
                    LDFLAGS="${LDFLAGS:-} -static-libgcc -static-libstdc++"; \
                  }; \
                  [ "$GOARCH" == "amd64" ] || [ "$GOARCH" == "arm64" ] || [ "${ENABLE_PIE:-}" != true ] || ENABLE_STATIC=; \
                }; \
                WITH_LDFLAGS="${WITH_LDFLAGS:-} -linkmode=external -extld="$CC" -extldflags \"${LDFLAGS:-} ${ENABLE_STATIC:+-static}${ENABLE_PIE:+-pie}\""; \
                WITH_TAGS="${WITH_TAGS:-} cgo ${ENABLE_STATIC:+static static_build}"; \
              }; \
              go build -ldflags "-s -w -v ${WITH_LDFLAGS:-}" -tags "${WITH_TAGS:-} net${WITH_CGO_NET:+c}go osusergo" -o /dist/boot/bin/"$WITH_BUILD_OUTPUT" "$WITH_BUILD_SOURCE"


###################################################################
# QEMU cross
###################################################################
FROM          --platform=$BUILDPLATFORM fetcher-qemu                                                                    AS builder-qemu

ARG           TARGETARCH
ARG           TARGETVARIANT

# ../target/m68k/translate.c triggers errors on maybe-uninitialized
# ppc and possibly armhf have issues with stringop-overflow
ENV           CFLAGS="$CFLAGS -Wno-maybe-uninitialized -Wno-stringop-overflow"

# XXXtemp - base image should ship that
ENV           CXXFLAGS="-Werror=format-security -Wall $OPTIMIZATION_OPTIONS $DEBUGGING_OPTIONS $PREPROCESSOR_OPTIONS $COMPILER_OPTIONS"
# XXXtemp

# Disabling fuse and vnc is deviating from
RUN           eval "$(dpkg-architecture -A "$(echo "$TARGETARCH$TARGETVARIANT" | sed -e "s/^armv6$/armel/" -e "s/^armv7$/armhf/" -e "s/^ppc64le$/ppc64el/" -e "s/^386$/i386/")")"; \
              export PKG_CONFIG="${DEB_TARGET_GNU_TYPE}-pkg-config"; \
              export AR="${DEB_TARGET_GNU_TYPE}-ar"; \
              export CC="${DEB_TARGET_GNU_TYPE}-gcc"; \
              export CXX="${DEB_TARGET_GNU_TYPE}-g++"; \
              ./configure \
                --enable-seccomp \
                --disable-fuse \
                --disable-vnc \
                --prefix=/dist/boot \
                --with-pkgversion="$GIT_VERSION" \
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
                --cross-prefix="${DEB_TARGET_GNU_TYPE}-"

RUN           make -j "$(getconf _NPROCESSORS_ONLN)"

RUN           make install

# Disabling target selection for now so we get EVERYTHING
#                --target-list="aarch64-linux-user arm-linux-user ppc64le-linux-user s390x-linux-user riscv64-linux-user i386-linux-user x86_64-linux-user"

# XXX FIXME and stick with https://wiki.qemu.org/Hosts/Linux:
# libfdt-dev libpixman-1-dev

  # libbz2-dev
  # libcap-dev libcurl4-gnutls-dev
  # libibverbs-dev libjpeg8-dev libnuma-dev
  # librbd-dev librdmacm-dev
  # libsasl2-dev libsnappy-dev libssh2-1-dev
  # libvde-dev libvdeplug-dev libxen-dev liblzo2-dev
  # valgrind xfslibs-dev
  # libnfs-dev


FROM          --platform=$BUILDPLATFORM $FROM_REGISTRY/$FROM_IMAGE_BUILDER                                              AS fetcher-ghost

ARG           GIT_REPO=github.com/ghostunnel/ghostunnel
ARG           GIT_VERSION=f71137b
ARG           GIT_COMMIT=f71137b46c6aab933c0cdb2e9797a95d30bfdb73

ENV           WITH_BUILD_SOURCE="."
ENV           WITH_BUILD_OUTPUT="ghostunnel"
ENV           WITH_LDFLAGS="-X main.version=${GIT_VERSION}"

RUN           git clone --recurse-submodules git://"$GIT_REPO" .; git checkout "$GIT_COMMIT"
RUN           --mount=type=secret,id=CA \
              --mount=type=secret,id=NETRC \
              [[ "${GOFLAGS:-}" == *-mod=vendor* ]] || go mod download

FROM          --platform=$BUILDPLATFORM fetcher-ghost                                                                   AS builder-ghost

ARG           TARGETARCH
ARG           TARGETOS
ARG           TARGETVARIANT
ENV           GOOS=$TARGETOS
ENV           GOARCH=$TARGETARCH

ENV           CGO_CFLAGS="${CFLAGS:-} ${ENABLE_PIE:+-fPIE}"
ENV           GOFLAGS="-trimpath ${ENABLE_PIE:+-buildmode=pie} ${GOFLAGS:-}"

RUN           export GOARM="$(printf "%s" "$TARGETVARIANT" | tr -d v)"; \
              [ "${CGO_ENABLED:-}" != 1 ] || { \
                eval "$(dpkg-architecture -A "$(echo "$TARGETARCH$TARGETVARIANT" | sed -e "s/^armv6$/armel/" -e "s/^armv7$/armhf/" -e "s/^ppc64le$/ppc64el/" -e "s/^386$/i386/")")"; \
                export PKG_CONFIG="${DEB_TARGET_GNU_TYPE}-pkg-config"; \
                export AR="${DEB_TARGET_GNU_TYPE}-ar"; \
                export CC="${DEB_TARGET_GNU_TYPE}-gcc"; \
                export CXX="${DEB_TARGET_GNU_TYPE}-g++"; \
                [ ! "${ENABLE_STATIC:-}" ] || { \
                  [ ! "${WITH_CGO_NET:-}" ] || { \
                    ENABLE_STATIC=; \
                    LDFLAGS="${LDFLAGS:-} -static-libgcc -static-libstdc++"; \
                  }; \
                  [ "$GOARCH" == "amd64" ] || [ "$GOARCH" == "arm64" ] || [ "${ENABLE_PIE:-}" != true ] || ENABLE_STATIC=; \
                }; \
                WITH_LDFLAGS="${WITH_LDFLAGS:-} -linkmode=external -extld="$CC" -extldflags \"${LDFLAGS:-} ${ENABLE_STATIC:+-static}${ENABLE_PIE:+-pie}\""; \
                WITH_TAGS="${WITH_TAGS:-} cgo ${ENABLE_STATIC:+static static_build}"; \
              }; \
              go build -ldflags "-s -w -v ${WITH_LDFLAGS:-}" -tags "${WITH_TAGS:-} net${WITH_CGO_NET:+c}go osusergo" -o /dist/boot/bin/"$WITH_BUILD_OUTPUT" "$WITH_BUILD_SOURCE"


#######################
# Builder assembly
#######################
FROM          --platform=$BUILDPLATFORM $FROM_REGISTRY/$FROM_IMAGE_AUDITOR                                              AS builder

COPY          --from=builder-binfmt         /dist /dist
COPY          --from=builder-rootless       /dist /dist

COPY          --from=builder-tools          /boot/bin/goello-server-ng /dist/boot/bin
COPY          --from=builder-tools-dev      /boot/bin/buildctl      /dist/boot/bin
COPY          --from=builder-tools          /boot/bin/caddy          /dist/boot/bin
# Not necessary for now
# RUN           setcap 'cap_net_bind_service+ep' /dist/boot/bin/caddy

# TMP remove
# COPY          --from=builder-fuse-overlay --chown=$BUILD_UID:root /dist /dist
# RUN           for i in /dist/boot/bin/*; do file "$i" | grep "statically linked" || { echo "$i is NOT static"; file "$i"; ldd "$i"; exit 1; }; done

COPY          --from=builder-idmap          /dist /dist
COPY          --from=builder-stargz         /dist /dist
COPY          --from=builder-qemu           /dist /dist

#COPY          --from=builder-containerd /dist/boot/bin /dist/boot/bin

COPY          --from=builder-buildkit       /dist /dist
COPY          --from=builder-runc           /dist /dist

COPY          --from=builder-ghost           /dist /dist
RUN           setcap 'cap_net_bind_service+ep' /dist/boot/bin/ghostunnel

RUN           chmod 555 /dist/boot/bin/*; \
              epoch="$(date --date "$BUILD_CREATED" +%s)"; \
              find /dist/boot -newermt "@$epoch" -exec touch --no-dereference --date="@$epoch" '{}' +;

#######################
# Runtime
#######################
FROM          $FROM_REGISTRY/$FROM_IMAGE_RUNTIME

USER          root

# Prepare dbus
RUN           mkdir -p /run/dbus; chown "$BUILD_UID":root /run/dbus; chmod 775 /run/dbus

# ca-certificates=20200601~deb10u1 is not necessary in itself
# Removing fuse for now - fuse-overlay is just too buggy
# fuse3=3.10.3-1 \
RUN           --mount=type=secret,uid=100,id=CA \
              --mount=type=secret,uid=100,id=CERTIFICATE \
              --mount=type=secret,uid=100,id=KEY \
              --mount=type=secret,uid=100,id=GPG.gpg \
              --mount=type=secret,id=NETRC \
              --mount=type=secret,id=APT_SOURCES \
              --mount=type=secret,id=APT_CONFIG \
              apt-get update -qq && apt-get install -qq --no-install-recommends \
                git=1:2.30.2-1 \
                pigz=2.6-1 \
                xz-utils=5.2.5-2 \
                jq=1.6-2.1 \
                libnss-mdns=0.14.1-2 && \
              apt-get -qq autoremove      && \
              apt-get -qq clean           && \
              rm -rf /var/lib/apt/lists/* && \
              rm -rf /tmp/*               && \
              rm -rf /var/tmp/*

RUN           echo dubo-dubon-duponey:100000:65536 | tee /etc/subuid | tee /etc/subgid

ENV           XDG_RUNTIME_DIR=/data
VOLUME        /run

COPY          --from=builder --chown=$BUILD_UID:root /dist /

RUN           chown root:root /boot/bin/newuidmap \
                && chown root:root /boot/bin/newgidmap \
                && chmod u+s /boot/bin/newuidmap \
                && chmod u+s /boot/bin/newgidmap

USER          dubo-dubon-duponey

# Current config below is full-blown regular caddy config, which is only partly useful here
# since caddy only role is to provide and renew TLS certificates

### Front server configuration
# Port to use
ENV           PORT_HTTPS=443
ENV           PORT_HTTP=80
EXPOSE        443
EXPOSE        80
# Log verbosity for
ENV           LOG_LEVEL="warn"
# Domain name to serve
ENV           DOMAIN="$NICK.local"
ENV           ADDITIONAL_DOMAINS=""
# Whether the server should behave as a proxy (disallows mTLS)
ENV           SERVER_NAME="DuboDubonDuponey/1.0 (Caddy/2) [$NICK]"
# Control wether tls is going to be "internal" (eg: self-signed), or alternatively an email address to enable letsencrypt - use "" to disable TLS entirely
ENV           TLS="internal"
# 1.2 or 1.3
ENV           TLS_MIN=1.3
# Issuer name to appear in certificates
#ENV           TLS_ISSUER="Dubo Dubon Duponey"
# Either disable_redirects or ignore_loaded_certs if one wants the redirects
ENV           TLS_AUTO=disable_redirects
# Either require_and_verify or verify_if_given, or "" to disable mTLS altogether
ENV           MTLS="require_and_verify"
# Root certificate to trust for mTLS
ENV           MTLS_TRUST="/certs/mtls_ca.crt"
# Realm for authentication - set to "" to disable authentication entirely
ENV           AUTH="My Precious Realm"
# Provide username and password here (call the container with the "hash" command to generate a properly encrypted password, otherwise, a random one will be generated)
ENV           AUTH_USERNAME="dubo-dubon-duponey"
ENV           AUTH_PASSWORD="cmVwbGFjZV9tZV93aXRoX3NvbWV0aGluZwo="
### mDNS broadcasting
# Type to advertise
ENV           MDNS_TYPE="_buildkit._tcp"
# Name is used as a short description for the service
ENV           MDNS_NAME="$NICK mDNS display name"
# The service will be annonced and reachable at $MDNS_HOST.local (set to empty string to disable mDNS announces entirely)
ENV           MDNS_HOST="$NICK"
# Also announce the service as a workstation (for example for the benefit of coreDNS mDNS)
ENV           MDNS_STATION=true
# Caddy certs will be stored here
VOLUME        /certs
# Caddy uses this
VOLUME        /tmp
# Used by the backend service
VOLUME        /data

# XXX problematic as caddy is picking up on this - moving to ghost ASAP
ENV           HEALTHCHECK_URL="http://127.0.0.1:$PORT"
HEALTHCHECK   --interval=120s --timeout=30s --start-period=10s --retries=1 CMD buildctl --addr "$HEALTHCHECK_URL" debug workers || exit 1
