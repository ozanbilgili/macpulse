import SwiftUI
import MetricsCore

enum HardwareFormat {
    static func temperature(_ value: Double?) -> String { value.map { MetricFormat.number($0) + " °C" } ?? "—" }
    static func watts(_ value: Double?) -> String { value.map { MetricFormat.number($0, digits: 2) + " W" } ?? "—" }
    static func flow(_ value: Double?) -> String {
        guard let value else { return "—" }
        if value > 0 { return "↑ " + watts(value) }
        if value < 0 { return "↓ " + watts(-value) }
        return watts(0)
    }
}

struct HardwareView: View {
    let snapshot: HardwareSnapshot?
    let system: SystemMetrics
    let history: [MetricSnapshot]
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label("GPU & Energy", systemImage: "square.3.layers.3d").font(.system(size: 24, weight: .semibold, design: .rounded)).foregroundStyle(Palette.gpu)
                Spacer()
                Text("\(system.chip) · \(system.cores) cores").font(.caption).foregroundStyle(Palette.secondary)
            }
            if let snapshot {
                ForEach(snapshot.gpus) { gpu in
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .lastTextBaseline) {
                            Text("GPU usage").font(.headline)
                            Spacer()
                            Text(MetricFormat.percent(gpu.devicePercent)).font(.system(size: 44, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(Palette.gpu)
                        }
                        FactRow(facts: [StatFact(title: "Renderer", value: MetricFormat.percent(gpu.rendererPercent)), StatFact(title: "Tiler", value: MetricFormat.percent(gpu.tilerPercent)), StatFact(title: String(localized: "Driver memory in use"), value: MetricFormat.bytes(gpu.memoryInUse, binary: true)), StatFact(title: String(localized: "Allocated driver memory"), value: MetricFormat.bytes(gpu.memoryAllocated, binary: true))])
                        MetricChart(points: plotPoints(history) { $0.hardware?.gpus.first { $0.id == gpu.id }?.devicePercent }, color: Palette.gpu, ceiling: 100, detailed: true).frame(height: 190)
                        Text("These are the AGX driver's utilization counters; the driver's sampling window is unknown. Memory values are system memory allocated to GPU resources, not separate VRAM, and can't be added to the physical RAM total.")
                            .font(.caption).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                    }.padding(22).background(Palette.card, in: RoundedRectangle(cornerRadius: 18))
                }
                if snapshot.gpus.isEmpty { unavailable(snapshot.gpuStatus) }
                Text("Power and temperature").font(.title3.weight(.semibold))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 14) {
                    HardwareValue(title: "System power channel", value: HardwareFormat.watts(snapshot.systemWatts), caption: "SMC PSTR · reported value", color: Palette.accent)
                    HardwareValue(title: "GPU energy model", value: HardwareFormat.watts(snapshot.gpuModelWatts), caption: "IOReport · interval average", color: Palette.gpu)
                    HardwareValue(title: "Net battery flow", value: HardwareFormat.flow(snapshot.batteryNetWatts), caption: "↑ into battery · ↓ out of battery", color: Palette.battery)
                    HardwareValue(title: "CPU sensors · partial", value: HardwareFormat.temperature(snapshot.cpuTemperatureAverage), caption: "Verified sensor group only", color: Palette.cpu)
                    HardwareValue(title: "GPU sensor average", value: HardwareFormat.temperature(snapshot.gpuTemperatureAverage), caption: "Valid Tg sensors only", color: Palette.gpu)
                    HardwareValue(title: "macOS thermal state", value: system.thermalState, caption: "Operating system · not degrees", color: Palette.disk)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Label(snapshot.energyStatus, systemImage: "info.circle")
                    Text("GPU wattage is calculated from an energy model; it isn't a hardware power meter. The system power channel and battery flow have different scopes; they aren't added together or presented as power drawn from the outlet. CPU/ANE wattage and per-app energy aren't measured in this version.")
                    Text(snapshot.batteryFlowStatus + (snapshot.batteryUpdatedAt.map { " · " + String(localized: "Source updated \($0.formatted(date: .omitted, time: .standard))") } ?? ""))
                }.font(.caption).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top, spacing: 14) {
                    HardwarePlot(title: "GPU energy model · W", points: plotPoints(history) { $0.hardware?.gpuModelWatts }, color: Palette.gpu)
                    HardwarePlot(title: "System power channel · W", points: plotPoints(history) { $0.hardware?.systemWatts }, color: Palette.accent)
                }
                HStack {
                    Text("Sensor readings").font(.title3.weight(.semibold))
                    Spacer()
                    Text("\(snapshot.sensors.count) valid · \(snapshot.invalidSensors) invalid · \(snapshot.sensorFailures) unreadable").font(.caption).foregroundStyle(Palette.secondary)
                }
                Text(snapshot.sensorStatus + (snapshot.sensorsTruncated ? " · " + String(localized: "Partial list") : "") + " · " + snapshot.date.formatted(date: .omitted, time: .standard))
                    .font(.caption).foregroundStyle(Palette.secondary)
                if snapshot.sensors.isEmpty { unavailable(String(localized: "Sensor data can't be verified; fan speed and temperature aren't assumed to be zero.")) }
                else {
                    VStack(spacing: 0) {
                        ForEach(snapshot.sensors) { sensor in
                            HStack {
                                Image(systemName: sensor.kind == .fan ? "fan" : sensor.kind == .systemPower ? "bolt" : "thermometer.medium").frame(width: 24).foregroundStyle(sensor.kind == .gpu ? Palette.gpu : Palette.secondary)
                                Text(sensor.id).font(.system(.body, design: .monospaced)).frame(width: 70, alignment: .leading)
                                Text(sensor.kind == .fan ? "Fan · actual RPM" : sensor.kind == .systemPower ? "System power channel" : sensor.kind == .gpu ? "GPU sensor group" : "CPU sensor group").foregroundStyle(Palette.secondary)
                                Spacer()
                                Text(sensor.kind == .fan ? MetricFormat.number(sensor.value, digits: 0) + " rpm" : sensor.kind == .systemPower ? HardwareFormat.watts(sensor.value) : HardwareFormat.temperature(sensor.value)).monospacedDigit()
                            }.font(.system(size: 12)).padding(12)
                            Divider()
                        }
                    }.background(Palette.card, in: RoundedRectangle(cornerRadius: 14))
                }
                Text("SMC sensor names and mappings aren't documented; the average covers only the group read validly on this device and isn't the exact temperature of every core. The Tp group, which can't be verified on macOS 27+, is excluded; CPU temperature is the partial Te group. Temperature appears after two valid consecutive readings. Missing or invalid data isn't averaged. Fans are read only. GPU/SMC/IOReport access can vary by device or macOS version; no privileged helper is installed.")
                    .font(.caption).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                Text("The detailed sensor list lives only in memory. Charts cover the last 90 hardware samples; the 30-day history isn't extended with these metrics.")
                    .font(.caption).foregroundStyle(Palette.secondary)
            } else { unavailable(String(localized: "Waiting for hardware measurements")) }
        }
    }
    private func unavailable(_ text: String) -> some View {
        Label(text, systemImage: "info.circle").font(.callout).foregroundStyle(Palette.secondary)
            .padding(22).frame(maxWidth: .infinity, alignment: .leading).background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
    }
}
private struct HardwareValue: View {
    let title: LocalizedStringKey
    let value: String
    let caption: LocalizedStringKey
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(color)
            Text(value).font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(caption).font(.caption).foregroundStyle(Palette.secondary).lineLimit(1)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Palette.card, in: RoundedRectangle(cornerRadius: 15))
    }
}
private struct HardwarePlot: View {
    let title: LocalizedStringKey
    let points: [PlotPoint]
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(color)
            MetricChart(points: points, color: color, detailed: true).frame(height: 150)
        }.padding(18).frame(maxWidth: .infinity).background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
    }
}
