import QtQuick
import qs.Commons
import qs.Commons as Commons

// A small label naming a button, shown while the pointer rests on it.
Rectangle {
  id: tip

  property bool shown: false
  property string text: ""

  visible: shown
  width: label.implicitWidth + Style.spacing.controlPaddingX * 2
  height: label.implicitHeight + Style.spacing.xs * 2
  radius: Style.cornerRadius
  color: Commons.Color.popups.background
  border.color: Commons.Color.popups.border
  border.width: Style.normalBorderWidth
  z: 20

  Text {
    id: label
    anchors.centerIn: parent
    textFormat: Text.PlainText
    text: tip.text
    color: Commons.Color.popups.text
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
  }
}
