import QtQuick
import qs.Commons
import qs.Commons as Commons

// A square footer button with one glyph, like the start menu's power button.
Rectangle {
  id: button

  property string glyph: ""
  property string label: ""
  property bool active: false
  signal clicked()

  width: Math.round(Style.font.heading * 2.4)
  height: width
  radius: Style.cornerRadius
  color: mouse.containsMouse || button.active ? Style.hoverFill : "transparent"

  Text {
    anchors.centerIn: parent
    textFormat: Text.PlainText
    text: button.glyph
    color: Commons.Color.menu.text
    font.family: Style.font.family
    font.pixelSize: Style.font.heading
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: button.clicked()
  }

  ToolTipText {
    shown: mouse.containsMouse && button.label !== ""
    text: button.label
    anchors.bottom: parent.top
    anchors.bottomMargin: Style.spacing.sm
    anchors.horizontalCenter: parent.horizontalCenter
  }
}
