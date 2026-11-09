# KDE 4.14 ports

This category contains the KDE Software Compilation 4.14 desktop stack. Qt 4
is installed under `/opt/qt4`; the KDE libraries and applications install under
`/usr` so they integrate with the rest of the system.

## Build order

1. `qt4`
2. `automoc4`
3. `phonon4`
4. `phonon-backend-gstreamer`
5. `attica4`
6. `soprano`
7. `strigi`
8. `shared-desktop-ontologies`
9. `akonadi`
10. `kdelibs`
11. `kdepimlibs`
12. `kactivities4`
13. `kde-runtime`
14. `kde-baseapps`
15. `oxygen-icons4`
16. `kde-base-artwork`
17. `kde-wallpapers`
18. `kde-workspace`
19. `kdeartwork`
20. `kdeplasma-addons4`
21. `kde4` (metapackage)

The `kde4` metapackage pulls in the complete list. KDE4-only packages use a
`4` suffix where the same name is also used by the KF5/KF6 collection in
`ports/plasma`.

## Toolchain compatibility

Qt 4.8.7 and KDE 4.14.3 predate the current GCC and CMake toolchains. The
recipes therefore build with `-std=gnu++98 -fpermissive` and pass
`CMAKE_POLICY_VERSION_MINIMUM=3.5` to CMake 4. `kdelibs` also patches KDE4's
CMake macros to use `$<TARGET_FILE>` instead of reading the `LOCATION` property
and to quote `if()` arguments that newer CMake treats as keywords.

Qt 4 is built with OpenSSL 4 support (`-openssl-linked`), using the
Debian/Arch OpenSSL 1.1 compatibility patch plus a small OpenSSL 4 update for
opaque ASN.1/X509 accessors, const-correct signatures, and removed protocol
methods. QtWebKit, QtDeclarative, and the bundled Phonon remain disabled. KDE
4 uses the separate `phonon4` package, and `kdelibs` disables its optional
direct OpenSSL, WebKit, QCA2, udisks, PolicyKit, aspell, and Enchant
integrations; its TLS paths use QtNetwork's OpenSSL support.

`phonon-backend-gstreamer` supplies the Qt 4 Phonon backend. `gst-plugins-base`
and `gst-plugins-good` provide the ALSA and PulseAudio output paths used by the
backend.

`kdepimlibs` retains its required GPGME dependency and builds the KDE 4 PIM
libraries used by the runtime and workspace. Its optional legacy KCal/Libical
path is disabled.
