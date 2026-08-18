# LFS Book for StormFS Linux

A comprehensive Linux From Scratch build guide for StormFS Linux. This book walks through building a complete x86_64 multilib Linux system from source using CRUX-style ports, pkgutils, and prt-get.

> **Version:** 0.9.0 (pre-release)
> **Target architecture:** x86_64 multilib (32-bit and 64-bit libraries)
> **Init system:** systemd
> **Package manager:** pkgutils / prt-get (CRUX-based)

## Table of Contents

1. [Introduction](chapters/01-introduction.md)
2. [Preparing the Host System](chapters/02-preparing-the-host-system.md)
3. [Building the Temporary Toolchain](chapters/03-building-the-temporary-toolchain.md)
4. [Building the Base System](chapters/04-building-the-base-system.md)
5. [Rebuilding with Final Toolchain](chapters/05-rebuilding-with-final-toolchain.md)
6. [Verifying the Base System](chapters/06-verifying-the-base-system.md)
7. [Creating the Rootfs Archive](chapters/07-creating-the-rootfs-archive.md)
8. [Basic System Configuration](chapters/08-basic-system-configuration.md)
9. [Linux Kernel](chapters/09-linux-kernel.md)
10. [Bootloader (GRUB)](chapters/10-bootloader.md)
11. [Package Management](chapters/11-package-management.md)
12. [System Initialization](chapters/12-system-initialization.md)
13. [Networking](chapters/13-networking.md)
14. [SSH Server](chapters/14-ssh-server.md)
15. [Base Utilities](chapters/15-base-utilities.md)
16. [Final System Adjustments](chapters/16-final-system-adjustments.md)

## About This Book

This book follows the BLFS (Beyond Linux From Scratch) style and provides detailed, step-by-step instructions for building StormFS Linux from source. Each chapter includes exact commands, configuration file contents, and explanations for every step.

## Conventions

- Commands that need to be run as root are prefixed with `#`
- Commands that can be run as a regular user are prefixed with `$`
- File contents are shown in fenced code blocks with the target path as a comment
- Important notes and warnings are highlighted in blockquotes
- Package versions are noted where significant
- Cross-references to other chapters are linked

## Prerequisites

- An x86_64 Linux host system (Gentoo LiveGUI recommended)
- 8 GB RAM minimum
- 50 GB free disk space
- Working internet connection for source downloads
- A non-root user with sudo privileges

## Quick Start

```sh
git clone --recurse-submodules https://github.com/bfitzgit23/StormFS-Linux.git
cd StormFS-Linux
./bootstrap.sh
```

Select option **1** from the interactive menu to begin the toolchain build, then follow the numbered stages sequentially.

## Contributing

To contribute to this book, please submit pull requests to the StormFS Linux repository.
