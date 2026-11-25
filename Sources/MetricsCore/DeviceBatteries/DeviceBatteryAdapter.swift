import Foundation

public enum DeviceBatteryAdapter {
    /// Reuses the existing Bluetooth sampler. Its timestamp is never advanced by
    /// a UI tick; macOS reports cached sensor values, not a guaranteed sensor date.
    public static func bluetooth(_ snapshot: BluetoothSnapshot?, now: Date = Date()) -> BatterySnapshot {
        guard let snapshot, snapshot.available, snapshot.fresh(at: now) else { return .init(devices: [], successfulSources: []) }
        var devices: [BatteryDevice] = []
        for accessory in snapshot.accessories {
            let connected = accessory.connection == .connected
            // Successful inventory marks known absent devices offline in the ledger.
            // Never create a "last measurement" card for an unseen offline peripheral.
            guard connected else { continue }
            let main = accessory.reportedBatteries.first { $0.component == "main" }?.percent
                ?? accessory.reportedBatteries.filter { ["left", "right"].contains($0.component) }.map(\.percent).min()
            let level = accessory.batteryLimitation == nil && connected ? main : nil
            devices.append(.init(id: accessory.id, name: accessory.name, level: level, isCharging: accessory.reportedCharging ?? false, isConnected: connected, source: .bluetooth,
                                 measuredAt: level == nil ? nil : snapshot.date, lastSeenAt: connected ? snapshot.date : nil,
                                 connection: .bluetooth, telemetry: .macOSBluetooth))
            if connected, let box = accessory.reportedBatteries.first(where: { $0.component == "case" }) {
                devices.append(.init(id: accessory.id + ":case", name: accessory.name + " Case", level: box.percent, isCharging: box.charging ?? false,
                                     source: .bluetooth, measuredAt: snapshot.date, lastSeenAt: snapshot.date,
                                     connection: .bluetooth, telemetry: .macOSBluetooth))
            }
        }
        return .init(devices: devices, successfulSources: [.bluetooth])
    }
}
