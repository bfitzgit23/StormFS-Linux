# Begin /etc/profile.d/kf6.sh

export KF6_PREFIX=/opt/kf6

pathappend $KF6_PREFIX/bin              PATH
pathappend $KF6_PREFIX/lib/pkgconfig    PKG_CONFIG_PATH

pathappend $KF6_PREFIX/etc/xdg          XDG_CONFIG_DIRS
pathappend $KF6_PREFIX/share            XDG_DATA_DIRS

pathappend $KF6_PREFIX/lib/plugins      QT_PLUGIN_PATH
pathappend $KF6_PREFIX/lib/plugins/kcms QT_PLUGIN_PATH

pathappend $KF6_PREFIX/lib/qml          QML2_IMPORT_PATH

pathappend $KF6_PREFIX/lib/python3.12/site-packages PYTHONPATH

pathappend $KF6_PREFIX/include          CPLUS_INCLUDE_PATH
# End /etc/profile.d/kf6.sh
