import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    id: root
    property int slide: 0
    property var images: [
        "StormFS-Wallpaper-01-Horizon.jpg",
        "StormFS-Wallpaper-02-Lightning.jpg",
        "StormFS-Wallpaper-03-Circuit.jpg",
        "StormFS-Wallpaper-04-Aurora.jpg",
        "StormFS-Wallpaper-05-Hex.jpg",
        "StormFS-Wallpaper-06-Orbit.jpg"
    ]
    Timer { interval: 5000; repeat: true; running: true; onTriggered: root.slide = (root.slide + 1) % root.images.length }
    Image { anchors.fill: parent; source: root.images[root.slide]; fillMode: Image.PreserveAspectCrop; asynchronous: true }
    Rectangle { anchors.fill: parent; color: "#9907111f" }
    Column { anchors.centerIn: parent; spacing: 10
        Label { text: "StormFS Linux"; color: "#dbeafe"; font.pixelSize: 30; font.bold: true }
        Label { text: "Open choice. Source built. Ready for the storm."; color: "#67e8f9"; font.pixelSize: 15 }
    }
}
