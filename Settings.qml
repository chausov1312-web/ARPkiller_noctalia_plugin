import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets
import Quickshell.Io

ColumnLayout {
    id: root
    property var pluginApi: null
    property var cfg: pluginApi?.pluginSettings || ({})
    property var defaults: pluginApi?.manifest?.metadata?.defaultSettings || ({})

    property string valueInterface: cfg.interface ?? ""
    property int valueScanInterval: cfg.scanIntervalSec ?? 30
    property bool valueAutoRestore: cfg.autoRestore ?? true
    property string valueGatewayIp: cfg.gatewayIp ?? ""
    property string valueGatewayMac: cfg.gatewayMac ?? ""
    property string valueAttackType: cfg.attackType ?? "mitm"
    property string valueCustomCommand: cfg.customCommand ?? "sudo arpspoof -i {INTERFACE} -t {VICTIM_IP} {GATEWAY_IP}"
    property string valueBarIcon: cfg.barIcon ?? "zap"
    property int valueBarWidth: cfg.barWidth ?? 40

    property var interfacesList: []
    property var iconsList: [
        "zap", "activity", "network", "shield", "wifi", "cloud",
        "alert", "eye", "lock", "cpu", "server", "home"
    ]

    spacing: Style.marginL

    Process {
        id: ifaceProc
        command: ["sh", "-c", "ip link show | grep -E '^[0-9]+: (en|eth|wlan|wl)' | cut -d: -f2 | sed 's/ //g'"]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) { if (line.trim() !== "") root.interfacesList.push(line.trim()) }
        }
        onExited: function() {
            var model = []
            for (var i = 0; i < root.interfacesList.length; i++)
                model.push({ key: root.interfacesList[i], name: root.interfacesList[i] })
            ifaceCombo.model = model
            if (valueInterface && model.some(m => m.key === valueInterface))
                ifaceCombo.currentKey = valueInterface
        }
    }

    NHeader { label: "Сетевой интерфейс" }
    NComboBox {
        id: ifaceCombo
        Layout.fillWidth: true
        currentKey: valueInterface
        model: []
        onSelected: function(key) { valueInterface = key; saveSettings() }
    }

    NDivider { Layout.fillWidth: true }

    NHeader { label: "Шлюз по умолчанию" }
    RowLayout {
        Layout.fillWidth: true
        NTextInput {
            id: gwIpInput
            placeholderText: "IP шлюза"
            text: valueGatewayIp
            onEditingFinished: { valueGatewayIp = text; saveSettings() }
        }
        NTextInput {
            id: gwMacInput
            placeholderText: "MAC шлюза"
            text: valueGatewayMac
            onEditingFinished: { valueGatewayMac = text; saveSettings() }
        }
    }

    NDivider { Layout.fillWidth: true }

    NHeader { label: "Тип атаки" }
    NComboBox {
        id: attackTypeCombo
        Layout.fillWidth: true
        currentKey: valueAttackType
        model: [
            { key: "mitm", name: "MITM – перехват трафика (IP forwarding)" },
            { key: "kill", name: "KILL – полное отключение интернета" },
            { key: "custom", name: "Пользовательская команда" }
        ]
        onSelected: function(key) { valueAttackType = key; saveSettings() }
    }

    // Custom command block – visible only when custom attack type is selected
    ColumnLayout {
        visible: valueAttackType === "custom"
        Layout.fillWidth: true
        NHeader { label: "Пользовательская команда" }
        NText {
            text: "Доступные переменные: {INTERFACE}, {VICTIM_IP}, {VICTIM_MAC}, {GATEWAY_IP}, {GATEWAY_MAC}"
            pointSize: Style.fontSizeXS
            color: Color.mSecondary
            wrapMode: Text.WordWrap
        }
        NTextInput {
            id: cmdInput
            Layout.fillWidth: true
            text: valueCustomCommand
            onEditingFinished: { valueCustomCommand = text; saveSettings() }
        }
    }

    NDivider { Layout.fillWidth: true }

    NHeader { label: "Внешний вид иконки на панели" }
    RowLayout {
        Layout.fillWidth: true
        NText { text: "Иконка:"; Layout.preferredWidth: 60 }
        NComboBox {
            id: iconCombo
            Layout.fillWidth: true
            currentKey: valueBarIcon
            model: {
                var arr = []
                for (var i = 0; i < root.iconsList.length; i++)
                    arr.push({ key: root.iconsList[i], name: root.iconsList[i] })
                return arr
            }
            onSelected: function(key) { valueBarIcon = key; saveSettings() }
        }
    }
    RowLayout {
        Layout.fillWidth: true
        NText { text: "Ширина кнопки (px):"; Layout.preferredWidth: 120 }
        NSlider {
            id: widthSlider
            from: 28; to: 80; stepSize: 2
            value: valueBarWidth
            onMoved: { valueBarWidth = Math.round(value); saveSettings() }
        }
        NText { text: valueBarWidth + " px" }
    }

    NDivider { Layout.fillWidth: true }

    NHeader { label: "Сканирование" }
    RowLayout {
        Layout.fillWidth: true
        NText { text: "Интервал сканирования (сек):" }
        NSlider {
            from: 10; to: 300; stepSize: 5
            value: valueScanInterval
            onMoved: { valueScanInterval = Math.round(value); saveSettings() }
        }
        NText { text: valueScanInterval + " с" }
    }

    NHeader { label: "Атака" }
    NToggle {
        Layout.fillWidth: true
        label: "Автовосстановление ARP при остановке"
        checked: valueAutoRestore
        onToggled: function(checked) { valueAutoRestore = checked; saveSettings() }
    }

    function saveSettings() {
        if (!pluginApi) return
        pluginApi.pluginSettings.interface = valueInterface
        pluginApi.pluginSettings.scanIntervalSec = valueScanInterval
        pluginApi.pluginSettings.autoRestore = valueAutoRestore
        pluginApi.pluginSettings.gatewayIp = valueGatewayIp
        pluginApi.pluginSettings.gatewayMac = valueGatewayMac
        pluginApi.pluginSettings.attackType = valueAttackType
        pluginApi.pluginSettings.customCommand = valueCustomCommand
        pluginApi.pluginSettings.barIcon = valueBarIcon
        pluginApi.pluginSettings.barWidth = valueBarWidth
        pluginApi.saveSettings()

        if (pluginApi.mainInstance) {
            pluginApi.mainInstance.selectedInterface = valueInterface
            pluginApi.mainInstance.scanIntervalSec = valueScanInterval
            pluginApi.mainInstance.autoRestore = valueAutoRestore
            pluginApi.mainInstance.gatewayIp = valueGatewayIp
            pluginApi.mainInstance.gatewayMac = valueGatewayMac
            pluginApi.mainInstance.attackType = valueAttackType
            pluginApi.mainInstance.customCommand = valueCustomCommand
        }
    }

    Component.onCompleted: { ifaceProc.running = true }
}
