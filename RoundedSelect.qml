import QtQuick
import QtQuick.Controls as QQC
import QtQuick.Layouts
import qs.Commons as Commons
import qs.Ui as Ui

ColumnLayout {
  id: control

  required property string label
  required property string value
  required property var options
  signal changed(string value)

  spacing: Commons.Style.space(4)

  Text {
    textFormat: Text.PlainText
    text: control.label
    color: Commons.Color.popups.text
    font.family: Commons.Style.font.family
    font.pixelSize: Commons.Style.font.caption
  }

  QQC.ComboBox {
    id: selector
    Layout.fillWidth: true
    Layout.minimumWidth: 0
    model: control.options
    textRole: "label"
    valueRole: "value"
    currentIndex: control.options.findIndex(option => option.value === control.value)
    font.family: Commons.Style.font.family
    font.pixelSize: Commons.Style.font.bodySmall
    implicitHeight: Commons.Style.space(34)
    leftPadding: Commons.Style.space(10)
    rightPadding: Commons.Style.space(28)
    Accessible.name: control.label
    onActivated: control.changed(currentValue)

    background: Ui.BorderSurface {
      radius: height / 2
      color: Commons.Style.controlFill(selector.activeFocus, selector.hovered,
        Commons.Color.popups.text, Commons.Color.accent)
      borderSpec: Commons.Border.controlSpec(selector.activeFocus ? "focus"
        : (selector.hovered ? "hover-cursor" : "normal"), Commons.Color.popups.text, Commons.Color.accent)
    }

    contentItem: Text {
      textFormat: Text.PlainText
      text: selector.displayText
      color: Commons.Color.popups.text
      font: selector.font
      verticalAlignment: Text.AlignVCenter
      elide: Text.ElideRight
    }

    indicator: Text {
      x: selector.mirrored ? Commons.Style.space(8) : selector.width - width - Commons.Style.space(8)
      y: (selector.height - height) / 2
      textFormat: Text.PlainText
      text: "⌄"
      color: Commons.Color.popups.text
      font: selector.font
    }

    delegate: QQC.ItemDelegate {
      id: optionRow
      required property var modelData
      required property int index
      width: ListView.view ? ListView.view.width : selector.width
      height: Commons.Style.spacing.controlHeight
      highlighted: selector.highlightedIndex === index

      background: Rectangle {
        radius: Commons.Style.space(8)
        color: optionRow.highlighted ? Commons.Style.selectedFillFor(Commons.Color.popups.text, Commons.Color.accent)
                                  : "transparent"
      }
      contentItem: Text {
        textFormat: Text.PlainText
        text: optionRow.modelData.label
        color: Commons.Color.popups.text
        font: selector.font
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
      }
    }

    popup: QQC.Popup {
      y: selector.height + Commons.Style.space(4)
      width: selector.width
      padding: Commons.Style.space(4)
      implicitHeight: Math.min(contentItem.implicitHeight, Commons.Style.space(240)) + topPadding + bottomPadding
      background: Ui.BorderSurface {
        radius: Commons.Style.space(14)
        color: Commons.Color.popups.background
        borderSpec: Commons.Border.surfaceSpec("popups", "border", Commons.Color.popups.border, 1)
      }
      contentItem: ListView {
        clip: true
        implicitHeight: contentHeight
        model: selector.popup.visible ? selector.delegateModel : null
        currentIndex: selector.highlightedIndex
      }
    }
  }
}
