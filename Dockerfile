# syntax=docker/dockerfile:1
#
# BFSOS / StormFS ISO build container.
#
# Produces the same ISO that scripts/bfs-build-iso.sh produces on a bare-metal
# host, but with the host tools pinned: Debian packages for xorriso,
# squashfs-tools, mtools and both GRUB firmware platforms, so the builder's
# preflight cannot fail for a missing tool on the caller's machine.
#
# The builder must run as a regular user (it re-executes mount/chroot through
# sudo), so the image creates an unprivileged "builder" account with
# passwordless sudo and starts as that user.
#
# The build itself needs mount/chroot into the extracted live root, so the
# container has to run privileged:
#
#   docker build -t bfsos-iso .
#   docker run --rm --privileged -it \
#       -v "$PWD/out:/build/output" \
#       bfsos-iso
#
# Notes:
#   * The verified base archive is downloaded from SourceForge by default
#     (BFS_ISO_BASE_MODE=sourceforge); the builder clones its own tree from
#     GitHub for the ISO payload, so the copy in this image only supplies
#     VERSION, archives/base and the scripts themselves.
#   * Set BFS_ISO_BASE_MODE=local-path and mount an archive to build from a
#     base you already have, or BFS_ISO_BASE_MODE=auto to let the builder pick
#     archives/base from the image.
#   * chronyd runs inside the container because sync_host_time() dies when
#     neither chronyc nor timedatectl is present, and a container has no
#     systemd. chronyd keeps the clock honest, but it cannot accept clock
#     control commands (makestep) from a client inside the container, so the
#     image ships a small timedatectl shim that reports chrony's real sync
#     state. If chrony has no reference/stratum the shim answers "no" and the
#     build still stops.

FROM debian:trixie-slim

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# Tool set mirrors required_tools/tool_packages in scripts/bfs-build-iso.sh:
#   bash git sudo tar xz zstd rsync wget sha256sum find awk sed grep
#   mount umount chroot mksquashfs xorriso grub-mkrescue mformat
# plus the /usr/lib/grub/{i386-pc,x86_64-efi} module trees that preflight probes.
# scratchpkg's pkgbuild downloads sources with curl (not wget) and
# verifies them with gnupg.  Stage 1 builds the temporary toolchain with
# the host compiler, so the image must satisfy the LFS host system
# requirements: binutils, bison, bzip2, coreutils, diffutils, findutils,
# gawk, gcc, g++, gzip, m4, make, patch, perl, python3, sed, tar, texinfo
# and xz.  Missing any of them fails deep inside a package build hours in.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        coreutils \
        util-linux \
        findutils \
        sed \
        grep \
        gawk \
        git \
        sudo \
        tar \
        xz-utils \
        zstd \
        rsync \
        wget \
        curl \
        gnupg \
        diffutils \
        build-essential \
        g++ \
        binutils \
        gzip \
        bzip2 \
        perl \
        python3 \
        gettext \
        patch \
        m4 \
        bison \
        flex \
        texinfo \
        file \
        less \
        bsdutils \
        squashfs-tools \
        xorriso \
        mtools \
        grub-common \
        grub-pc-bin \
        grub-efi-amd64-bin \
        chrony \
 && rm -rf /var/lib/apt/lists/*

# Fail the image build, not the ISO build, if a GRUB platform goes missing.
RUN set -eux; \
    test -x /usr/bin/grub-mkrescue; \
    test -x /usr/bin/mformat; \
    test -x /usr/bin/mksquashfs; \
    test -x /usr/bin/xorriso; \
    test -d /usr/lib/grub/i386-pc; \
    test -d /usr/lib/grub/x86_64-efi; \
    test -x /usr/bin/curl; \
    test -x /usr/bin/gpg; \
    test -x /usr/bin/gcc; \
    test -x /usr/bin/make; \
    test -x /usr/bin/bison; \
    test -x /usr/bin/m4; \
    for tool in g++ as ld gzip bzip2 perl python3 msgfmt tar xz sed grep \
                awk find diff make patch bash; do \
        command -v "$tool" >/dev/null; \
    done

ARG BUILDER_UID=1000
ARG BUILDER_GID=1000

RUN set -eux; \
    if ! getent group "${BUILDER_GID}" >/dev/null; then \
        groupadd --gid "${BUILDER_GID}" builder; \
    fi; \
    if ! id -u builder >/dev/null 2>&1; then \
        useradd --create-home --uid "${BUILDER_UID}" \
            --gid "${BUILDER_GID}" --shell /bin/bash builder; \
    fi; \
    printf 'builder ALL=(ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/builder; \
    chmod 0440 /etc/sudoers.d/builder; \
    visudo --check --quiet

WORKDIR /build/StormFS-Linux
COPY --chown=builder:builder . .

# COPY sets ownership on the copied tree, but the WORKDIR directory itself stays
# root-owned, and bootstrap.sh writes logs/ and archives/ next to its own
# scripts.  Without this the builder cannot create /build/StormFS-Linux/logs.
RUN set -eux; \
    chown -R builder:builder /build/StormFS-Linux; \
    install -d -o builder -g builder \
        /build/StormFS-Linux/logs \
        /build/StormFS-Linux/logs/toolchain \
        /build/StormFS-Linux/logs/base \
        /build/StormFS-Linux/archives \
        /build/StormFS-Linux/archives/toolchain

# A Windows checkout can carry CRLF inside scratchpkg/ (a gitlink, so this
# repository's .gitattributes does not reach it).  A CRLF shebang turns every
# seeded tool into "/tmp/lfs-tools/bin/pkgbuild: cannot execute: required file
# not found" because the interpreter becomes "/bin/sh\r".  Normalise the text
# files the build executes and fail the image build if any survived.
RUN set -eux; \
    find . -type f \
        \( -name '*.sh' -o -name spkgbuild -o -name depends \
           -o -path './scratchpkg/*' -o -path './files/*' \) \
        -exec sh -c 'file --mime-type -b "$1" | grep -q "^text/" && sed -i "s/\r$//" "$1"' _ {} \; ; \
    for tool in scratchpkg/pkgbuild scratchpkg/pkgadd scratchpkg/pkgdel \
                scratchpkg/scratch scratchpkg/portsync files/spkgin; do \
        bash -n "$tool"; \
        ! grep -q $'\r' "$tool"; \
    done

# timedatectl stand-in: sync_host_time() needs a systemd bus answer for
# NTPSynchronized, which a container cannot provide.
COPY --chmod=0755 scripts/docker-timedatectl-shim.sh /usr/local/bin/timedatectl

# A Windows/CRLF checkout does not carry the executable bit through COPY.
RUN set -eux; \
    chmod 0755 scripts/bfs-build-iso.sh scripts/docker-iso-entrypoint.sh; \
    bash -n scripts/bfs-build-iso.sh; \
    bash -n scripts/docker-iso-entrypoint.sh

USER builder

ENV BFS_ISO_ASSUME_YES=yes \
    BFS_ISO_BASE_MODE=sourceforge \
    BFS_ISO_WORK_DIR=/var/tmp/bfsos-iso-builder \
    BFS_ISO_OUTPUT_DIR=/build/output

VOLUME ["/build/output"]

ENTRYPOINT ["/build/StormFS-Linux/scripts/docker-iso-entrypoint.sh"]
