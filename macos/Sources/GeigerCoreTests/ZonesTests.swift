import GeigerCore

func zonesTests() {
    // zone thresholds
    expectEqual(ZoneLevel.forRate(0), .background, "rate 0 is background")
    expectEqual(ZoneLevel.forRate(1_999), .background, "rate 1999 is background")
    expectEqual(ZoneLevel.forRate(2_000), .elevated, "rate 2000 is elevated")
    expectEqual(ZoneLevel.forRate(20_000), .hot, "rate 20000 is hot")
    expectEqual(ZoneLevel.forRate(60_000), .critical, "rate 60000 is critical")
    expectEqual(ZoneLevel.forRate(200_000), .meltdown, "rate 200000 is meltdown")
    expectEqual(ZoneLevel.forRate(500_000), .meltdown, "rate 500000 is meltdown")

    // zone labels
    expectEqual(ZoneLevel.background.label, "BACKGROUND", "background label")
    expectEqual(ZoneLevel.meltdown.label, "MELTDOWN", "meltdown label")

    // gauge fraction at or below floor is zero
    expectEqual(gaugeFraction(rate: 0), 0, "gauge at rate 0")
    expectEqual(gaugeFraction(rate: 60), 0, "gauge at floor")

    // log scale: halfway in log space between 60 and 300_000 = sqrt(60 * 300_000) ≈ 4242.64
    expectEqual(gaugeFraction(rate: 4242.64), 0.5, accuracy: 0.001, "gauge log midpoint")

    // saturates at one
    expectEqual(gaugeFraction(rate: 300_000), 1, accuracy: 0.0001, "gauge at ceiling")
    expectEqual(gaugeFraction(rate: 10_000_000), 1, "gauge beyond ceiling")
}
