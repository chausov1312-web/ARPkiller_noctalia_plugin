import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Services.UI
import qs.Widgets

Item {
    id: root
    property var pluginApi: null
    property var mainInstance: pluginApi?.mainInstance

    property var geometryPlaceholder: panelContainer
    property real contentPreferredWidth: 580 * Style.uiScaleRatio
    property real contentPreferredHeight: Math.min(650, column.implicitHeight + Style.marginL * 2)
    property bool panelReady: true
    property bool allowAttach: true
    property bool continuousScan: false
    property var scanTimer: null

    anchors.fill: parent

    Rectangle {
        id: panelContainer
        anchors.fill: parent
        color: "transparent"

        ColumnLayout {
            id: column
            anchors.fill: parent
            anchors.margins: Style.marginL
            spacing: Style.marginM

            RowLayout {
                NIcon { icon: "zap"; pointSize: Style.fontSizeXL; color: Color.mError }
                NText { text: "ARP Killer"; pointSize: Style.fontSizeL; font.weight: Font.Bold }
                Item { Layout.fillWidth: true }
                NIconButton { icon: "x"; onClicked: pluginApi?.closePanel(pluginApi?.panelOpenScreen) }
            }

            RowLayout {
                NText { text: "Шлюз:"; pointSize: Style.fontSizeS }
                NTextInput {
                    id: gwIpInput
                    placeholderText: "IP шлюза"
                    text: mainInstance?.gatewayIp || ""
                    onEditingFinished: { if (text && gwMacInput.text) mainInstance?.setGateway(text, gwMacInput.text) }
                }
                NTextInput {
                    id: gwMacInput
                    placeholderText: "MAC шлюза"
                    text: mainInstance?.gatewayMac || ""
                    onEditingFinished: { if (gwIpInput.text && text) mainInstance?.setGateway(gwIpInput.text, text) }
                }
                NIconButton {
                    icon: "refresh-cw"
                    tooltipText: "Автоопределить шлюз"
                    onClicked: mainInstance?.autoDetectGateway()
                }
            }

            RowLayout {
                NButton { text: "Сканировать сеть"; onClicked: mainInstance?.scanNetwork() }
                NButton { text: "Остановить все атаки"; backgroundColor: Color.mError; onClicked: mainInstance?.stopAllAttacks() }
            }

            RowLayout {
                NToggle {
                    id: continuousToggle
                    label: "Непрерывное сканирование"
                    checked: continuousScan
                    onToggled: function(checked) {
                        continuousScan = checked
                        if (continuousScan && mainInstance) {
                            var interval = (mainInstance.scanIntervalSec || 30) * 1000
                            if (!scanTimer) {
                                scanTimer = Qt.createQmlObject("import QtQuick; Timer { interval: interval; repeat: true; onTriggered: mainInstance?.scanNetwork() }", root, "scanTimer")
                            } else {
                                scanTimer.interval = interval
                                scanTimer.start()
                            }
                        } else if (scanTimer) {
                            scanTimer.stop()
                        }
                    }
                }
                NText { text: "Интервал (сек):" }
                NSpinBox {
                    id: intervalSpin
                    from: 1; to: 300; stepSize: 1
                    value: mainInstance?.scanIntervalSec || 30
                    onValueChanged: {
                        if (mainInstance) mainInstance.scanIntervalSec = value
                        if (continuousScan && scanTimer) scanTimer.interval = value * 1000
                    }
                }
            }

            NDivider {}

            // Активные атаки
            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 120
                Layout.minimumHeight: 80
                spacing: Style.marginXS
                NText { text: "🔥 Активные атаки (" + (mainInstance?.attackedDevices?.length || 0) + ")"; pointSize: Style.fontSizeM; font.weight: Font.Bold }
                ListView {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    model: mainInstance?.attackedDevices || []
                    delegate: Rectangle {
                        width: ListView.view.width; height: 40
                        color: Qt.alpha(Color.mError, 0.15); radius: Style.radiusS
                        border.color: Color.mError; border.width: 1
                        RowLayout {
                            anchors.fill: parent; anchors.margins: Style.marginS
                            NIcon { icon: "zap"; pointSize: Style.fontSizeM; color: Color.mError }
                            NText { text: modelData.ip; color: Color.mError; font.weight: Font.Bold }
                            NText { text: modelData.mac; color: Color.mOnSurfaceVariant; Layout.fillWidth: true }
                            NIconButton { icon: "stop-circle"; tooltipText: "Остановить атаку"; onClicked: mainInstance?.stopAttack(modelData.ip) }
                        }
                    }
                    visible: (mainInstance?.attackedDevices?.length || 0) > 0
                }
            }

            NDivider {}

            // Обнаруженные устройства
            ColumnLayout {
                Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumHeight: 150
                spacing: Style.marginXS
                NText { text: "📡 Обнаруженные устройства (" + (mainInstance?.devices?.length || 0) + ")"; pointSize: Style.fontSizeM }
                ScrollView {
                    Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    ListView {
                        id: devicesListView
                        width: parent.width
                        model: mainInstance?.devices || []
                        delegate: Rectangle {
                            width: devicesListView.width; height: 36
                            color: modelData.attacked ? Qt.alpha(Color.mError, 0.2) : (index % 2 ? Qt.rgba(0,0,0,0.05) : "transparent")
                            RowLayout {
                                anchors.fill: parent; anchors.margins: Style.marginS
                                Rectangle { width: 10; height: 10; radius: 5; color: modelData.attacked ? Color.mError : Color.mSecondary }
                                NText { text: modelData.ip; Layout.preferredWidth: 120 }
                                NText { text: modelData.mac; Layout.fillWidth: true }
                                NIconButton {
                                    icon: modelData.attacked ? "stop-circle" : "play"
                                    tooltipText: modelData.attacked ? "Остановить атаку" : "Атаковать"
                                    onClicked: modelData.attacked ? mainInstance?.stopAttack(modelData.ip) : mainInstance?.startAttack(modelData.ip, modelData.mac)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Component.onCompleted: {
        if (mainInstance && mainInstance.selectedInterface) mainInstance.autoDetectGateway()
        Qt.callLater(function() {
            if (mainInstance && mainInstance.selectedInterface && mainInstance.gatewayIp) mainInstance.scanNetwork()
        }, 2000)
        if (continuousScan && mainInstance) {
            var interval = (mainInstance.scanIntervalSec || 30) * 1000
            scanTimer = Qt.createQmlObject("import QtQuick; Timer { interval: interval; repeat: true; onTriggered: mainInstance?.scanNetwork() }", root, "scanTimer")
        }
    }
}
