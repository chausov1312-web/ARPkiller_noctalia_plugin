import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.UI
import qs.Widgets

Item {
    id: root
    property var pluginApi: null
    property var mainInstance: pluginApi?.mainInstance

    property ShellScreen screen: null
    property string widgetId: ""
    property string section: ""
    property int sectionWidgetIndex: -1
    property int sectionWidgetsCount: 0

    readonly property string barPosition: Settings.getBarPositionForScreen(screen?.name ?? "")
    readonly property bool isVertical: barPosition === "left" || barPosition === "right"
    readonly property real capsuleHeight: Style.getCapsuleHeightForScreen(screen?.name ?? "")

    property int attackedCount: mainInstance?.attackedDevices?.length || 0
    property string barIcon: pluginApi?.pluginSettings?.barIcon ?? "zap"
    property int barWidth: pluginApi?.pluginSettings?.barWidth ?? 40

    readonly property real contentWidth: barWidth * Style.uiScaleRatio
    readonly property real contentHeight: capsuleHeight

    implicitWidth: contentWidth
    implicitHeight: contentHeight

    Rectangle {
        id: capsule
        x: Style.pixelAlignCenter(parent.width, width)
        y: Style.pixelAlignCenter(parent.height, height)
        width: parent.width
        height: parent.height
        radius: Style.radiusL
        color: attackedCount > 0 ? Color.mError : Style.capsuleColor
        border.color: Style.capsuleBorderColor
        border.width: Style.capsuleBorderWidth

        states: State {
            name: "hovered"
            when: mouseArea.containsMouse
            PropertyChanges { target: capsule; opacity: 0.85 }
        }
        transitions: Transition {
            PropertyAnimation { property: "opacity"; duration: 100 }
        }

        RowLayout {
            anchors.centerIn: parent
            spacing: Style.marginXS
            NIcon {
                icon: barIcon
                pointSize: root.contentHeight * 0.45
                color: attackedCount > 0 ? "white" : Color.mOnSurface
            }
            NText {
                text: attackedCount > 0 ? attackedCount.toString() : ""
                pointSize: root.contentHeight * 0.35
                color: attackedCount > 0 ? "white" : Color.mOnSurface
                visible: attackedCount > 0
            }
        }

        MouseArea {
            id: mouseArea
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor

            onClicked: (mouse) => {
                if (mouse.button === Qt.LeftButton)
                    pluginApi?.openPanel(root.screen, root)
                else if (mouse.button === Qt.RightButton)
                    PanelService.showContextMenu(contextMenu, root, screen)
            }
        }
    }

    NPopupContextMenu {
        id: contextMenu
        model: [
            { "label": "Open panel", "action": "open" },
            { "label": "Settings", "action": "settings" }
        ]
        onTriggered: function(action) {
            contextMenu.close()
            PanelService.closeContextMenu(screen)
            if (action === "open")
                pluginApi.openPanel(root.screen, root)
            else
                BarService.openPluginSettings(root.screen, pluginApi.manifest)
        }
    }
}
