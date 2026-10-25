import QtQuick
import qs.Commons
import qs.Commons as Commons

// One row of a popup menu: a glyph, a label, and a click.
Rectangle {
  id: row

  property string text: ""
  property string glyph: ""
  property bool highlighted: false
  signal triggered()

  width: parent ? parent.width : 0
  height: visible ? Style.spacing.popupRowHeight : 0
  radius: Style.cornerRadius
  color: rowMouse.containsMouse || row.highlighted ? Style.hoverFill : "transparent"

  Text {
    id: glyphText
    visible: row.glyph !== ""
    anchors.verticalCenter: parent.verticalCenter
    anchors.left: parent.left
    anchors.leftMargin: Style.spacing.controlPaddingX
    width: visible ? Math.round(Style.font.body * 1.5) : 0
    textFormat: Text.PlainText
    text: row.glyph
    color: Commons.Color.popups.text
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }

  Text {
    anchors.verticalCenter: parent.verticalCenter
    anchors.left: glyphText.visible ? glyphText.right : parent.left
    anchors.leftMargin: glyphText.visible ? Style.spacing.sm : Style.spacing.controlPaddingX
    anchors.right: parent.right
    anchors.rightMargin: Style.spacing.controlPaddingX
    textFormat: Text.PlainText
    text: row.text
    color: Commons.Color.popups.text
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    elide: Text.ElideRight
  }

  MouseArea {
    id: rowMouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: row.triggered()
  }
}
