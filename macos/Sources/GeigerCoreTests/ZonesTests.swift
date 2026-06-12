import GeigerCore

func zonesTests() {
    // zone thresholds
    expectEqual(ZoneLevel.forRate(0), .background, "rate 0 is background")
    expectEqual(ZoneLevel.forRate(999), .background, "rate 999 is background")
    expectEqual(ZoneLevel.forRate(1_000), .elevated, "rate 1000 is elevated")
    expectEqual(ZoneLevel.forRate(8_000), .hot, "rate 8000 is hot")
    expectEqual(ZoneLevel.forRate(30_000), .critical, "rate 30000 is critical")
    expectEqual(ZoneLevel.forRate(80_000), .meltdown, "rate 80000 is meltdown")
    expectEqual(ZoneLevel.forRate(500_000), .meltdown, "rate 500000 is meltdown")

    // zone labels
    expectEqual(ZoneLevel.background.label, "BACKGROUND", "background label")
    expectEqual(ZoneLevel.meltdown.label, "MELTDOWN", "meltdown label")

    // gauge fraction at or below floor is zero
    expectEqual(gaugeFraction(rate: 0), 0, "gauge at rate 0")
    expectEqual(gaugeFraction(rate: 60), 0, "gauge at floor")

    // log scale: halfway in log space between 60 and 120_000 = sqrt(60 * 120_000) ≈ 2683.28
    expectEqual(gaugeFraction(rate: 2683.28), 0.5, accuracy: 0.001, "gauge log midpoint")

    // saturates at one
    expectEqual(gaugeFraction(rate: 120_000), 1, accuracy: 0.0001, "gauge at ceiling")
    expectEqual(gaugeFraction(rate: 10_000_000), 1, "gauge beyond ceiling")
}
