import Foundation
import Metal
import MetricsCore

struct HardwareProbeVerification: Codable, Sendable {
    let accepted: Bool
    let failures: [String]
    let completedGPUCommands: Int
    let gpuExecutionSeconds: Double
    let observedGPUPercent: Double?
    let observedGPUModelWatts: Double?
    let validTemperatures, fanCount: Int
    let baselineResetVerified: Bool
}
private struct MetalWork: Sendable { let commands: Int; let seconds: Double; let validOutput: Bool }

func verifyHardware(_ sampler: MetricSampler) async -> HardwareProbeVerification {
    // The explicit probe flag runs only this bounded, local GPU workload. No other app is controlled.
    let work = Task.detached { () -> MetalWork in
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return MetalWork(commands: 0, seconds: 0, validOutput: false) }
        let source = """
        #include <metal_stdlib>
        using namespace metal;
        kernel void pulse(device float* data [[buffer(0)]], uint id [[thread_position_in_grid]]) {
            float x = data[id] + float(id % 31) * 0.00001f;
            for (uint j = 0; j < 2048; ++j) { x = sin(x) * 0.999f + 0.01f; }
            data[id] = x;
        }
        """
        guard let library = try? device.makeLibrary(source: source, options: nil), let function = library.makeFunction(name: "pulse"),
            let pipeline = try? device.makeComputePipelineState(function: function),
            let buffer = device.makeBuffer(length: 65536 * MemoryLayout<Float>.stride, options: .storageModeShared) else {
            return MetalWork(commands: 0, seconds: 0, validOutput: false)
        }
        let values = buffer.contents().bindMemory(to: Float.self, capacity: 65536)
        values.initialize(repeating: 0.001, count: 65536)
        let deadline = ProcessInfo.processInfo.systemUptime + 6
        var commands = 0, execution = 0.0
        while ProcessInfo.processInfo.systemUptime < deadline {
            let elapsed: Double? = autoreleasepool {
                guard let command = queue.makeCommandBuffer(), let encoder = command.makeComputeCommandEncoder() else { return nil }
                encoder.setComputePipelineState(pipeline); encoder.setBuffer(buffer, offset: 0, index: 0)
                encoder.dispatchThreads(MTLSize(width: 65536, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: min(256, pipeline.maxTotalThreadsPerThreadgroup), height: 1, depth: 1))
                encoder.endEncoding(); command.commit(); command.waitUntilCompleted()
                guard command.status == .completed else { return nil }
                return max(0, command.gpuEndTime - command.gpuStartTime)
            }
            guard let elapsed else { break }
            commands += 1; execution += elapsed
        }
        return MetalWork(commands: commands, seconds: execution, validOutput: values[0].isFinite && values[0] != 0.001)
    }
    try? await Task.sleep(for: .seconds(1))
    let first = await sampler.sample()
    try? await Task.sleep(for: .seconds(2))
    let loaded = await sampler.sample()
    let gpuWork = await work.value
    await sampler.resetBaselines()
    let reset = await sampler.sample()
    let resetVerified = reset.hardware?.gpuModelWatts == nil && reset.hardware?.cpuTemperatureAverage == nil && reset.cpu == nil
    var failures: [String] = []
    if gpuWork.commands == 0 || !gpuWork.validOutput || gpuWork.seconds <= 0 { failures.append("Controlled Metal workload did not complete") }
    if loaded.hardware?.singleGPUPercent == nil { failures.append("GPU driver reading unavailable during workload") }
    if loaded.hardware?.gpuModelWatts == nil { failures.append("Live GPU energy model unavailable during workload") }
    if !resetVerified { failures.append("Hardware reset must establish new energy/temperature baselines") }
    let temperatures = loaded.hardware?.sensors.filter { $0.kind == .cpu || $0.kind == .gpu }.count ?? 0
    let fans = loaded.hardware?.fans.count ?? 0
    return HardwareProbeVerification(accepted: failures.isEmpty, failures: failures, completedGPUCommands: gpuWork.commands,
        gpuExecutionSeconds: gpuWork.seconds, observedGPUPercent: loaded.hardware?.singleGPUPercent ?? first.hardware?.singleGPUPercent,
        observedGPUModelWatts: loaded.hardware?.gpuModelWatts, validTemperatures: temperatures, fanCount: fans, baselineResetVerified: resetVerified)
}
