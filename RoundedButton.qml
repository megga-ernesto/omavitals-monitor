import QtQuick
import QtQuick.Controls as QQC
import qs.Commons as Commons
import qs.Ui as Ui

Ui.Button {
  id: control

  property string hint: ""
  radius: Commons.Style.space(8)

  HoverHandler { id: hover }

  QQC.ToolTip {
    visible: control.hint !== "" && hover.hovered
    delay: 400
    padding: Commons.Style.space(7)
    background: Ui.BorderSurface {
      radius: Commons.Style.space(8)
      color: Commons.Color.tooltip.background
      borderSpec: Commons.Border.surfaceSpec("tooltip", "border", Commons.Color.tooltip.border, 1)
    }
    contentItem: Text {
      textFormat: Text.PlainText
      text: control.hint
      color: Commons.Color.tooltip.text
      font.family: control.fontFamily
      font.pixelSize: Commons.Style.font.bodySmall
    }
  }
}
