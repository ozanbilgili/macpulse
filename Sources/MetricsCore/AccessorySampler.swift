import Foundation
import TelemetryBridge

struct BluetoothSampler {
    private var previousUptime: Double?
    private var previous: BluetoothSnapshot?
    mutating func reset() { previousUptime = nil; previous = nil }
    mutating func sample(uptime: Double) -> BluetoothSnapshot {
        if let previousUptime, uptime >= previousUptime, uptime - previousUptime < 30, let previous { return previous }
        let start = ProcessInfo.processInfo.systemUptime
        var bytes = [CChar](repeating: 0, count: 1_048_576), length: UInt32 = 0
        let code = bytes.withUnsafeMutableBufferPointer { mp_read_bluetooth_profile($0.baseAddress, UInt32($0.count), &length) }
        let date = Date(), ms = (ProcessInfo.processInfo.systemUptime - start) * 1000
        let result: BluetoothSnapshot
        if code == 0, Int(length) < bytes.count,
            let parsed = try? BluetoothProfileParser.parse(bytes.withUnsafeBytes { Data($0.prefix(Int(length))) }, date: date, milliseconds: ms) { result = parsed }
        else {
            let status = code == 1 ? "Bluetooth okuması zaman aşımına uğradı" : code == 2 ? "Bluetooth envanteri boyut sınırını aştı" : "Bluetooth envanteri okunamadı"
            result = BluetoothSnapshot(date: date, power: .unknown, accessories: [], status: status,
                available: false, truncated: code == 2, discardedOfflineBatteryCount: 0, collectionMilliseconds: ms)
        }
        previousUptime = uptime; previous = result
        return result
    }
}
struct AudioSampler {
    func sample() -> AudioSnapshot {
        let start = ProcessInfo.processInfo.systemUptime
        var entries = [mp_audio_device](repeating: mp_audio_device(), count: 128), count: Int32 = 0, info = mp_audio_info()
        let code = entries.withUnsafeMutableBufferPointer { mp_read_audio($0.baseAddress, Int32($0.count), &count, &info) }
        var readings: [AudioDeviceReading] = []
        if code == 0 {
            for var d in entries.prefix(max(0, min(Int(count), entries.count))) {
                func has(_ mask: UInt32) -> Bool { d.valid_mask & mask != 0 }
                let name = withUnsafePointer(to: &d.name) { $0.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) } }
                readings.append(AudioDeviceReading(id: d.id, name: AccessoryMath.safeName(name, fallback: "Ses cihazı"),
                    transport: has(32) ? Self.transport(d.transport) : "Bilinmiyor",
                    inputChannels: has(4) ? Int(d.input_channels) : nil, outputChannels: has(8) ? Int(d.output_channels) : nil,
                    running: has(2) ? d.running != 0 : nil, sampleRate: has(16) ? AccessoryMath.sampleRate(d.sample_rate) : nil,
                    inputVolume: has(64) ? AccessoryMath.scalar(d.input_volume) : nil, outputVolume: has(128) ? AccessoryMath.scalar(d.output_volume) : nil,
                    inputMuted: has(256) ? d.input_mute != 0 : nil, outputMuted: has(512) ? d.output_mute != 0 : nil))
            }
        }
        func found(_ id: UInt32) -> UInt32? { id != 0 && readings.contains(where: { $0.id == id }) ? id : nil }
        return AudioSnapshot(date: Date(), devices: readings.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending },
            defaultInput: found(info.default_input), defaultOutput: found(info.default_output), defaultSystemOutput: found(info.default_system_output),
            available: code == 0, failures: code == 0 ? Int(info.failures) : 1, truncated: info.truncated != 0,
            collectionMilliseconds: (ProcessInfo.processInfo.systemUptime - start) * 1000)
    }
    private static func transport(_ code: UInt32) -> String {
        let bytes: [UInt8] = [UInt8(truncatingIfNeeded: code >> 24), UInt8(truncatingIfNeeded: code >> 16), UInt8(truncatingIfNeeded: code >> 8), UInt8(truncatingIfNeeded: code)]
        let name = String(bytes: bytes, encoding: .ascii) ?? ""
        switch name {
        case "bltn": return "Dahili"
        case "usb ": return "USB"
        case "blue", "blea": return "Bluetooth"
        case "virt": return "Sanal"
        case "grup": return "Birleşik"
        case "hdmi", "dprt": return "Ekran / HDMI"
        case "airp": return "AirPlay"
        case "thun": return "Thunderbolt"
        case "fwre": return "FireWire"
        case "pci ": return "PCI"
        default: return "Diğer"
        }
    }
}
