import Testing
@testable import MetricsCore

@Test func cpuNormalizesAcrossAllCores() throws {
    let before = CPUTicks(user: 100, system: 200, idle: 300, nice: 5)
    let after = CPUTicks(user: 130, system: 220, idle: 345, nice: 10)
    let usage = try #require(CPUUsage.between(before, after))
    #expect(usage.user == 35)
    #expect(usage.system == 20)
    #expect(usage.idle == 45)
    #expect(usage.used == 55)
}

@Test func cpuCounterWrapKeepsSmallDelta() throws {
    let before = CPUTicks(user: .max - 4, system: 0, idle: 10)
    let after = CPUTicks(user: 5, system: 0, idle: 20)
    let usage = try #require(CPUUsage.between(before, after))
    #expect(usage.used == 50)
}

@Test func unchangedTicksAreUnavailable() {
    let ticks = CPUTicks(user: 1, system: 2, idle: 3)
    #expect(CPUUsage.between(ticks, ticks) == nil)
}

@Test func ratesUseActualElapsedTime() throws {
    let delta = try #require(TransferDelta.between(.init(incoming: 10, outgoing: 5), .init(incoming: 2010, outgoing: 1005), seconds: 4))
    #expect(delta.incomingRate == 500)
    #expect(delta.outgoingRate == 250)
    #expect(delta.incomingBytes == 2000)
}

@Test(arguments: [0.0, -1.0, Double.infinity, Double.nan]) func invalidIntervalsProduceNoRate(seconds: Double) {
    #expect(TransferDelta.between(.init(incoming: 1, outgoing: 1), .init(incoming: 2, outgoing: 2), seconds: seconds) == nil)
}

@Test func resetCountersProduceNoSpike() {
    #expect(TransferDelta.between(.init(incoming: 1000, outgoing: 1000), .init(incoming: 10, outgoing: 10), seconds: 2) == nil)
}

@Test func replacedNetworkAdapterDoesNotInheritCounters() {
    let old = ["en0": TransferCounters(incoming: 500_000, outgoing: 250_000)]
    let current = ["en5": TransferCounters(incoming: 9_000_000, outgoing: 8_000_000)]
    #expect(CounterMath.deltas(previous: old, current: current, seconds: 2).isEmpty)
}

@Test func existingAdapterKeepsRateWhenAnotherAppears() throws {
    let old = ["en0": TransferCounters(incoming: 100, outgoing: 50)]
    let current = ["en0": TransferCounters(incoming: 2100, outgoing: 1050), "en5": TransferCounters(incoming: 900_000, outgoing: 400_000)]
    let deltas = CounterMath.deltas(previous: old, current: current, seconds: 2)
    #expect(deltas.count == 1)
    let kept = try #require(deltas["en0"])
    #expect(kept.incomingRate == 1000)
    #expect(kept.outgoingRate == 500)
}

@Test func physicalDriveReplacementWithSameCountGetsFreshBaseline() {
    let old: [UInt64: TransferCounters] = [10: .init(incoming: 500, outgoing: 500)]
    let current: [UInt64: TransferCounters] = [20: .init(incoming: 900_000, outgoing: 400_000)]
    #expect(old.count == current.count)
    #expect(CounterMath.deltas(previous: old, current: current, seconds: 2).isEmpty)
}

@Test func resumeEstablishesNewBaselineWithoutCountingPausedTraffic() async {
    let sampler = MetricSampler()
    _ = await sampler.sample()
    await sampler.resetBaselines()
    let resumed = await sampler.sample()
    #expect(resumed.cpu == nil)
    #expect(resumed.disk?.io == nil)
    #expect(resumed.network?.incomingRate == nil || resumed.network?.interfaces.isEmpty == true)
    #expect(resumed.network?.sessionReceived == 0)
    #expect(resumed.network?.sessionSent == 0)
}
