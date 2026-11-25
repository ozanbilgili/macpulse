import Foundation
import TelemetryBridge

// Confined to MetricSampler's actor. Retains subscriptions and closes all handles at destruction.
private final class HardwareConnection: @unchecked Sendable {
    let pointer: OpaquePointer?
    init() { pointer = mp_hardware_open() }
    deinit { mp_hardware_close(pointer) }
}
struct HardwareSampler {
    private var connection: HardwareConnection?
    private var validator = SensorValidator()
    private var energy = GPUModelTracker()
    mutating func reset() { validator.reset(); energy.reset(); connection = nil }
    mutating func sample() -> HardwareSnapshot {
        let begin = ProcessInfo.processInfo.systemUptime
        if connection == nil { connection = HardwareConnection() }
        var rawGPU = [mp_gpu](repeating: mp_gpu(), count: 8), gpuCount: Int32 = 0
        let gpuResult = rawGPU.withUnsafeMutableBufferPointer { mp_read_gpu($0.baseAddress, Int32($0.count), &gpuCount) }
        let gpus = rawGPU.prefix(Int(gpuCount)).map { value in
            GPUReading(id: value.registry_id,
                devicePercent: value.valid_mask & 1 != 0 ? HardwareMath.percentage(value.device_percent) : nil,
                rendererPercent: value.valid_mask & 2 != 0 ? HardwareMath.percentage(value.renderer_percent) : nil,
                tilerPercent: value.valid_mask & 4 != 0 ? HardwareMath.percentage(value.tiler_percent) : nil,
                memoryInUse: value.valid_mask & 8 != 0 ? value.memory_in_use : nil,
                memoryAllocated: value.valid_mask & 16 != 0 ? value.memory_allocated : nil)
        }.sorted { $0.id < $1.id }
        var rawSensors = [mp_sensor](repeating: mp_sensor(), count: 128)
        var sensorCount: Int32 = 0, failed: Int32 = 0, truncated: Int32 = 0
        let sensorResult = rawSensors.withUnsafeMutableBufferPointer { mp_read_sensors(connection?.pointer, $0.baseAddress, Int32($0.count), &sensorCount, &failed, &truncated) }
        var invalid = 0
        let candidates = rawSensors.prefix(Int(sensorCount)).compactMap { raw -> SensorReading? in
            let kind: SensorKind
            switch raw.kind { case 1: kind = .cpu; case 2: kind = .gpu; case 3: kind = .fan; case 4: kind = .systemPower; default: return nil }
            var raw = raw
            let key = withUnsafePointer(to: &raw.key) { $0.withMemoryRebound(to: CChar.self, capacity: 5) { String(cString: $0) } }
            guard HardwareMath.trustedTemperatureKey(key, kind: kind, osMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion) else { invalid += 1; return nil }
            let type = withUnsafePointer(to: &raw.type) { $0.withMemoryRebound(to: CChar.self, capacity: 5) { String(cString: $0) } }
            let bytes = withUnsafeBytes(of: raw.bytes) { Array($0.prefix(Int(raw.size))) }
            guard let number = HardwareMath.decodeSensor(type: type, bytes: bytes), HardwareMath.validSensor(number, kind: kind) else { invalid += 1; return nil }
            return SensorReading(id: key, kind: kind, value: number)
        }
        let sensors = validator.validate(candidates).sorted { $0.id < $1.id }
        func average(_ kind: SensorKind) -> Double? {
            let values = sensors.filter { $0.kind == kind }.map(\.value)
            return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }

        var rawEnergy = [mp_energy](repeating: mp_energy(), count: 16), energyCount: Int32 = 0
        let energyBegin = ProcessInfo.processInfo.systemUptime
        let energyResult = rawEnergy.withUnsafeMutableBufferPointer { mp_read_energy(connection?.pointer, $0.baseAddress, Int32($0.count), &energyCount) }
        let energyNow = (energyBegin + ProcessInfo.processInfo.systemUptime) / 2
        let gpuEnergy = rawEnergy.prefix(Int(energyCount)).filter { raw in
            var raw = raw
            return withUnsafePointer(to: &raw.name) { $0.withMemoryRebound(to: CChar.self, capacity: 64) { String(cString: $0) } } == "GPU Energy"
        }
        var gpuWatts: Double?
        var energyStatus = String(localized: "GPU energy channel unavailable")
        if energyResult == 0, gpuEnergy.count == 1, var raw = gpuEnergy.first {
            let unit = withUnsafePointer(to: &raw.unit) { $0.withMemoryRebound(to: CChar.self, capacity: 8) { String(cString: $0) } }.trimmingCharacters(in: .whitespaces)
            let busy = gpus.count == 1 ? gpus[0].devicePercent.map { $0 > 0 } : nil
            gpuWatts = energy.observe(driver: raw.driver_id, channel: raw.channel_id, counter: raw.value, unit: unit, uptime: energyNow, busy: busy)
            energyStatus = energy.status
        } else { energy.reset() }
        if ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 {
            energyStatus += String(localized: " · CPU energy model can't be verified on macOS 27+")
        } else { energyStatus += String(localized: " · CPU energy model not accepted in this version") }

        var battery = mp_battery_flow()
        let batteryResult = mp_read_battery_flow(&battery)
        let now = Date()
        let updated = battery.updated_seconds > 0 ? Date(timeIntervalSince1970: Double(battery.updated_seconds)) : nil
        let batteryWatts = batteryResult == 0 && battery.current_valid != 0 ? HardwareMath.batteryWatts(
            millivolts: battery.millivolts, milliamps: battery.milliamps, installed: battery.installed != 0,
            onAC: battery.on_ac != 0, charging: battery.charging != 0, updated: updated, now: now) : nil
        return HardwareSnapshot(date: now, gpus: gpus, sensors: sensors,
            cpuTemperatureAverage: average(.cpu), gpuTemperatureAverage: average(.gpu),
            systemWatts: sensors.first { $0.kind == .systemPower }?.value, gpuModelWatts: gpuWatts,
            batteryNetWatts: batteryWatts, batteryUpdatedAt: updated, sensorFailures: Int(failed), invalidSensors: invalid,
            sensorsTruncated: truncated != 0,
            gpuStatus: gpuResult == 0 ? String(localized: "AGX driver counters") : (gpus.isEmpty ? String(localized: "This GPU driver isn't supported") : String(localized: "Partial GPU list")),
            sensorStatus: sensorResult == 0 ? (sensors.isEmpty ? String(localized: "Waiting for sensor verification") : String(localized: "SMC · only sensors with valid readings") + (ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 ? String(localized: " · CPU Te group partial; Tp excluded") : "")) : String(localized: "SMC sensors unavailable"),
            energyStatus: energyStatus,
            batteryFlowStatus: batteryWatts == nil ? String(localized: "Battery flow missing, stale or inconsistent") : String(localized: "Net battery flow · not adapter consumption"),
            collectionMilliseconds: (ProcessInfo.processInfo.systemUptime - begin) * 1000)
    }
}
