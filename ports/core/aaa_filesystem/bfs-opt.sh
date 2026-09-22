# BFSOS canonical environment for optional toolchains installed under /opt.
# Keep one base-owned filename so upgrades from older leaf-owned qt5.sh,
# qt6.sh and rustc.sh files do not create package-ownership collisions.

if [ -d /opt/qt5 ]; then
    QT5DIR=/opt/qt5
    export QT5DIR
    [ -d "$QT5DIR/bin" ] && pathappend "$QT5DIR/bin" PATH
    [ -d "$QT5DIR/lib/pkgconfig" ] && pathappend "$QT5DIR/lib/pkgconfig" PKG_CONFIG_PATH
fi

if [ -d /opt/qt6 ]; then
    QT6DIR=/opt/qt6
    export QT6DIR
    [ -d "$QT6DIR/bin" ] && pathappend "$QT6DIR/bin" PATH
    [ -d "$QT6DIR/lib/pkgconfig" ] && pathappend "$QT6DIR/lib/pkgconfig" PKG_CONFIG_PATH
fi

if [ -d /opt/rustc ]; then
    pathprepend /opt/rustc/bin PATH
    [ -d /opt/rustc/share/man ] && pathappend /opt/rustc/share/man MANPATH
fi
