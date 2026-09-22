# Begin /etc/profile.d/kf6.sh

KF6_PREFIX=/opt/kf6
export KF6_PREFIX

if [ -d "$KF6_PREFIX" ]; then
    [ -d "$KF6_PREFIX/bin" ] && pathappend "$KF6_PREFIX/bin" PATH
    [ -d "$KF6_PREFIX/lib/pkgconfig" ] && pathappend "$KF6_PREFIX/lib/pkgconfig" PKG_CONFIG_PATH

    [ -d "$KF6_PREFIX/etc/xdg" ] && pathappend "$KF6_PREFIX/etc/xdg" XDG_CONFIG_DIRS
    [ -d "$KF6_PREFIX/share" ] && pathappend "$KF6_PREFIX/share" XDG_DATA_DIRS

    [ -d "$KF6_PREFIX/lib/plugins" ] && pathappend "$KF6_PREFIX/lib/plugins" QT_PLUGIN_PATH
    [ -d "$KF6_PREFIX/lib/plugins/kcms" ] && pathappend "$KF6_PREFIX/lib/plugins/kcms" QT_PLUGIN_PATH
    [ -d "$KF6_PREFIX/lib/qml" ] && pathappend "$KF6_PREFIX/lib/qml" QML2_IMPORT_PATH

    _python_site="$(python3 -c 'import sys; print(f"python{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null)"
    [ -n "$_python_site" ] && [ -d "$KF6_PREFIX/lib/$_python_site/site-packages" ] && \
        pathappend "$KF6_PREFIX/lib/$_python_site/site-packages" PYTHONPATH
    unset _python_site

    [ -d "$KF6_PREFIX/include" ] && pathappend "$KF6_PREFIX/include" CPLUS_INCLUDE_PATH
fi
# End /etc/profile.d/kf6.sh
