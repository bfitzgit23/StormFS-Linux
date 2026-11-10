# KDE 4.14 ports

This category contains the KDE Software Compilation 4.14 desktop stack. Qt 4
is installed under `/opt/qt4`; the KDE libraries and applications install under
`/usr` so they integrate with the rest of the system.

## Build order

1. `libical1` (1.0.1, installed under `/opt/libical`)
2. `qt4`
3. `qjson` (0.8.1, the last Qt 4 release)
4. `automoc4`
5. `phonon4`
6. `phonon-backend-gstreamer`
7. `attica4`
8. `soprano`
9. `strigi`
10. `shared-desktop-ontologies`
11. `akonadi4`
12. `kdelibs`
13. `kdepimlibs`
14. `kactivities4`
15. `kde-runtime`
16. `kde-baseapps`
17. `oxygen-icons4`
18. `kde-base-artwork`
19. `kde-wallpapers`
20. `kde-workspace`
21. `kdeartwork`
22. `kdeplasma-addons4`
23. `kde4` (metapackage)

The `kde4` metapackage pulls in the complete list. KDE4-only packages use a
`4` suffix where the same name is also used by the KF5/KF6 collection in
`ports/plasma`.

## Toolchain compatibility

Qt 4.8.7 and KDE 4.14.3 predate the current GCC and CMake toolchains. The
recipes therefore build with `-std=gnu++98 -fpermissive` and pass
`CMAKE_POLICY_VERSION_MINIMUM=3.5` to CMake 4. `kdepimlibs` is the exception:
its sources pull in the tree's C++11-only Boost headers, so it builds with
`-std=gnu++11`. `kdelibs` also patches KDE4's
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
libraries used by the runtime and workspace. It links the `libical1` port pinned
at 1.0.1 under `/opt/libical`, because kcalcore/kcal use the libical 1.0 API
(`icalcomponent_as_ical_string_r`, `icaltimetype.is_utc`,
`icalrecurrencetype_clear`) that libical 3 and later removed. The system
`libical` package stays at 4.x for everything else.

`kdepimlibs` also requires QJSON, which the `qjson` port provides (QJson 0.8.1 is
the last Qt 4 release). Its CMakeLists marks the package `TYPE REQUIRED` and
ends with `feature_summary(FATAL_ON_MISSING_REQUIRED_PACKAGES)`, so configure
aborts in that summary if the library is missing or its find is disabled. The
port installs `QJson.pc`, `libqjson.so` and `include/qjson/*.h` but not the
upstream `QJSONConfig.cmake`, because kdepimlibs' `FindQJSON.cmake` takes the
config-mode branch when that file resolves and then demands a `QJSON_CONFIG`
variable the config never defines; the pkg-config fallback is the branch that
actually works. The other KDE 4 recipes still pass
`-DCMAKE_DISABLE_FIND_PACKAGE_QJSON=TRUE` because they treat QJSON as optional.

gpgme 2.0 removed the trustlist API outright (`gpgme_op_trustlist_start`,
`_next`, `_end`, `gpgme_trust_item_t`), yet gpgme++ still compiles against it.
The recipe generates `gpgme2-trustlist-compat.h` and force-includes it, which
restores the deleted names as stubs that return `GPG_ERR_NOT_IMPLEMENTED` --
the same result gpgme has produced for those calls since 1.14.

Two further patches are the ones Arch's `kdepimlibs4` package carried for KDE
bug 338658: they make `ItemSync` merge on RID by default and keep GID as an
explicit opt-in, so a resource no longer aborts with "multiple merge
candidates" when GIDs collide. Both apply to 4.14.3 with small offsets.
