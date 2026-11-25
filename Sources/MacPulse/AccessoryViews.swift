import SwiftUI
import MetricsCore

struct BluetoothView: View {
    let snapshot: BluetoothSnapshot?
    let paused: Bool
    @State private var onlyConnected = false
    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Label("Bluetooth", systemImage: "antenna.radiowaves.left.and.right").font(.title2.weight(.semibold)).foregroundStyle(Palette.memory)
                    Spacer()
                    Toggle("Connected only", isOn: $onlyConnected).toggleStyle(.switch).font(.caption)
                }
                if let snapshot {
                    let fresh = snapshot.fresh(at: context.date)
                    let time = snapshot.date.formatted(date: .omitted, time: .standard)
                    let connected = snapshot.accessories.filter { snapshot.connection($0, at: context.date) == .connected }
                    HStack(spacing: 14) {
                        AccessoryFact(title: "Bluetooth status", value: fresh && snapshot.available ? power(snapshot.power) : String(localized: "Unknown"), caption: "macOS inventory report", color: Palette.memory)
                        AccessoryFact(title: "Connected accessories", value: fresh && snapshot.available ? "\(connected.count)" : "—", caption: "Connection scan", color: Palette.accent)
                        AccessoryFact(title: "Inventory", value: snapshot.available ? "\(snapshot.accessories.count)" : "—", caption: snapshot.truncated ? "Partial list" : "Connected and paired devices", color: Palette.secondary)
                    }
                    HStack {
                        Text(snapshot.status).font(.caption)
                        Spacer()
                        Text(paused ? "Paused · \(time)" : fresh ? "Last query · \(time)" : "Query is stale · \(time)").font(.caption).monospacedDigit()
                    }.foregroundStyle(Palette.secondary)
                    let rows = onlyConnected ? connected : snapshot.accessories
                    if rows.isEmpty {
                        Text(snapshot.available ? onlyConnected ? "No connected accessories." : "No accessories in the Bluetooth inventory." : "Bluetooth data unavailable. The result is unknown; an old inventory isn't shown as live.")
                            .foregroundStyle(Palette.secondary).padding(22).frame(maxWidth: .infinity, alignment: .leading).background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
                    }
                    ForEach(rows) { device in
                        let state = snapshot.connection(device, at: context.date)
                        let batteries = snapshot.batteries(device, at: context.date, paused: paused)
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Image(systemName: icon(device.kind)).font(.title2).foregroundStyle(Palette.memory).frame(width: 34)
                                VStack(alignment: .leading, spacing: 4) { Text(device.name).font(.headline); Text(device.kind).font(.caption).foregroundStyle(Palette.secondary) }
                                Spacer()
                                Text(state == .connected ? "Connected" : state == .disconnected ? "Not connected" : "Status unknown")
                                    .font(.caption.weight(.medium)).foregroundStyle(state == .connected ? Palette.accent : Palette.secondary)
                                    .padding(.horizontal, 10).padding(.vertical, 6).background(Palette.elevated, in: Capsule())
                            }
                            if batteries.isEmpty {
                                HStack { Text("Battery").foregroundStyle(Palette.secondary); Spacer(); Text("—").font(.title3).monospacedDigit() }
                                Text(paused ? String(localized: "Monitoring paused.") : state == .disconnected ? String(localized: "Stored battery values aren't shown for disconnected devices.") : state == .unknown ? String(localized: "Current connection can't be verified.") : device.batteryLimitation ?? String(localized: "This accessory doesn't report its battery."))
                                    .font(.caption).foregroundStyle(Palette.secondary)
                            } else {
                                HStack(spacing: 22) {
                                    ForEach(batteries, id: \.component) { battery in
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(battery.label).font(.caption).foregroundStyle(Palette.secondary)
                                            Text(LocalizedFormat.percent(battery.percent)).font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(Palette.battery)
                                        }
                                    }
                                }
                                Text("Reported battery · macOS record · sensor update time unknown")
                                    .font(.caption).foregroundStyle(Palette.secondary)
                            }
                        }.padding(20).background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
                    }
                    Text("Battery percentages are records reported by macOS; the time of this query is not the sensor's measurement time. Batteries are hidden for disconnected devices, records older than 45 seconds, and while paused. Logitech's generic battery record isn't trusted; this version doesn't query HID++. No scanning, pairing, connecting or disconnecting is done. No separate live battery source is added for iPhone/iPad, Watch or Pencil.")
                        .font(.caption).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                } else { ProgressView("Waiting for Bluetooth inventory") }
            }
        }
    }
    private func power(_ value: BluetoothPower) -> String { value == .on ? String(localized: "On") : value == .off ? String(localized: "Off") : String(localized: "Unknown") }
    private func icon(_ kind: String) -> String {
        let name = kind.lowercased()
        if name.contains("keyboard") { return "keyboard" }
        if name.contains("mouse") { return "computermouse" }
        if name.contains("head") || name.contains("audio") { return "headphones" }
        return "antenna.radiowaves.left.and.right"
    }
}

struct AudioDevicesView: View {
    let snapshot: AudioSnapshot?
    private enum Direction: Hashable { case all, input, output }
    @State private var filter = Direction.all
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label("Audio devices", systemImage: "speaker.wave.2").font(.title2.weight(.semibold)).foregroundStyle(Palette.network)
                Spacer()
                Picker("Device direction", selection: $filter) { Text("All").tag(Direction.all); Text("Input").tag(Direction.input); Text("Output").tag(Direction.output) }.pickerStyle(.segmented).frame(width: 230)
            }
            if let snapshot {
                HStack(spacing: 14) {
                    AccessoryFact(title: "Default input", value: snapshot.input?.name ?? "—", caption: "Microphone / input device", color: Palette.network)
                    AccessoryFact(title: "Default output", value: snapshot.output?.name ?? "—", caption: "App sounds", color: Palette.accent)
                    AccessoryFact(title: "System sounds", value: snapshot.systemOutput?.name ?? "—", caption: "Alert sound output", color: Palette.secondary)
                }
                HStack {
                    Text(!snapshot.available ? String(localized: "Core Audio inventory unavailable") : String(localized: "\(snapshot.devices.count) devices · \(snapshot.failures) missing / changed fields") + (snapshot.truncated ? " · " + String(localized: "Partial list") : "")).font(.caption)
                    Spacer()
                    Text("Last query \(snapshot.date.formatted(date: .omitted, time: .standard))").font(.caption).monospacedDigit()
                }.foregroundStyle(Palette.secondary)
                let devices = snapshot.devices.filter { filter == .all || (filter == .input ? ($0.inputChannels ?? 0) > 0 : ($0.outputChannels ?? 0) > 0) }
                if devices.isEmpty { Text("No audio devices in this scope.").foregroundStyle(Palette.secondary).padding(22) }
                ForEach(devices) { device in
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: (device.outputChannels ?? 0) > 0 ? "speaker.wave.2" : "mic").font(.title2).foregroundStyle(Palette.network).frame(width: 32)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(device.name).font(.headline)
                                Text(device.transport + " · " + (device.sampleRate.map { MetricFormat.number($0 / 1000, digits: 1) + " kHz" } ?? String(localized: "Sample rate unknown"))).font(.caption).foregroundStyle(Palette.secondary)
                            }
                            Spacer()
                            if device.id == snapshot.defaultInput { badge("Default input") }
                            if device.id == snapshot.defaultOutput { badge("Default output") }
                        }
                        FactRow(facts: [StatFact(title: String(localized: "Input channels"), value: device.inputChannels.map(String.init) ?? "—"),
                            StatFact(title: String(localized: "Output channels"), value: device.outputChannels.map(String.init) ?? "—"),
                            StatFact(title: String(localized: "Input level"), value: device.inputVolume.map { MetricFormat.percent($0) } ?? "—"),
                            StatFact(title: String(localized: "Output level"), value: device.outputVolume.map { MetricFormat.percent($0) } ?? "—")])
                        HStack(spacing: 22) {
                            Text("Input muted: \(flag(device.inputMuted))")
                            Text("Output muted: \(flag(device.outputMuted))")
                            Spacer()
                            Text(device.running.map { $0 ? String(localized: "Device I/O running") : String(localized: "Device I/O idle") } ?? String(localized: "I/O status unknown"))
                        }.font(.caption).foregroundStyle(Palette.secondary)
                    }.padding(20).background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
                }
                Text("Devices are queried read-only through Core Audio. Levels are the driver's main channel control; — appears when there is none. Running I/O doesn't mean audible sound or that a specific app is playing audio. Microphone or system audio recording, audio samples, device switching, volume control and a per-app mixer are not part of this version. The inventory is kept in memory only.")
                    .font(.caption).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
            } else { ProgressView("Waiting for audio devices") }
        }
    }
    private func flag(_ value: Bool?) -> String { value.map { $0 ? String(localized: "Yes") : String(localized: "No") } ?? "—" }
    private func badge(_ text: LocalizedStringKey) -> some View { Text(text).font(.caption2.weight(.medium)).foregroundStyle(Palette.accent).padding(7).background(Palette.elevated, in: Capsule()) }
}
private struct AccessoryFact: View {
    let title: LocalizedStringKey
    let value: String
    let caption: LocalizedStringKey
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(color)
            Text(value).font(.system(size: 21, weight: .semibold, design: .rounded)).lineLimit(2).frame(minHeight: 52, alignment: .leading)
            Text(caption).font(.caption).foregroundStyle(Palette.secondary)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
    }
}
