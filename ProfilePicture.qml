import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Commons as Commons

// The user's picture at the foot of the menu, a button like the ones across
// from it. Without a picture it is the first letter of their name on a disc in
// the theme's accent, so it changes along with the theme.
Rectangle {
  id: button

  // A picture file, shown when it loads.
  property string source: ""
  // Changes when the picture may have been replaced, so the new one shows.
  property int stamp: 0
  property string name: ""
  property real size: Math.round(Style.font.heading * 1.6)
  property bool active: false
  readonly property bool hovered: mouse.containsMouse
  readonly property bool pictured: picture.status === Image.Ready
  signal clicked()

  width: Math.round(Style.font.heading * 2.4)
  height: width
  radius: Style.cornerRadius
  color: mouse.containsMouse || button.active ? Style.hoverFill : "transparent"

  Rectangle {
    id: disc
    anchors.centerIn: parent
    width: button.size
    height: width
    radius: width / 2
    color: button.pictured ? "transparent" : Util.alpha(Commons.Color.accent, 0.2)
    border.color: Commons.Color.accent
    border.width: Style.normalBorderWidth

    Text {
      anchors.centerIn: parent
      visible: !button.pictured
      textFormat: Text.PlainText
      text: String(button.name || "").trim().charAt(0).toUpperCase()
      color: Commons.Color.accent
      font.family: Style.font.menuFamily
      font.pixelSize: Math.round(button.size * 0.55)
      font.weight: Font.DemiBold
    }
  }

  Image {
    id: picture
    anchors.fill: disc
    anchors.margins: disc.border.width
    visible: false
    source: button.source === "" ? "" : "file://" + button.source + "?v=" + button.stamp
    sourceSize.width: Math.ceil(width * Screen.devicePixelRatio)
    sourceSize.height: Math.ceil(height * Screen.devicePixelRatio)
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
    cache: false
    smooth: true
  }

  Item {
    id: mask
    anchors.fill: picture
    visible: false
    layer.enabled: true

    Rectangle {
      anchors.fill: parent
      radius: width / 2
      color: "black"
    }
  }

  MultiEffect {
    anchors.fill: picture
    visible: button.pictured
    source: picture
    maskEnabled: true
    maskSource: mask
    maskThresholdMin: 0.5
    maskSpreadAtMin: 1.0
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: button.clicked()
  }
}
