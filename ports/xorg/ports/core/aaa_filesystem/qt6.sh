# Begin /etc/profile.d/qt6.sh

QT6DIR=/opt/qt6

pathappend $QT6DIR/bin           PATH
pathappend $QT6DIR/lib/pkgconfig PKG_CONFIG_PATH

export QT6DIR

# End /etc/profile.d/qt6.sh
# Begin Qt6 changes for KF6

pathappend /usr/lib/plugins            QT_PLUGIN_PATH
pathappend $QT6DIR/plugins             QT_PLUGIN_PATH
pathappend $QT6DIR/qml                 QML2_IMPORT_PATH

# End Qt6 changes for KF6
