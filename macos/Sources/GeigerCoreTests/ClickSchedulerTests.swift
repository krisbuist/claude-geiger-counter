import GeigerCore

func clickSchedulerTests() {
    // idle: cosmic-ray clicks
    var s = ClickScheduler()
    expect(s.tick(frac: 0, now: 0, random: { 0.001 }), "cosmic ray fires below p=0.003")
    expect(!s.tick(frac: 0, now: 0.02, random: { 0.5 }), "no cosmic ray at p=0.5")

    // active: clicks follow exponential gaps
    s = ClickScheduler()
    expect(s.tick(frac: 0.5, now: 100, random: { 0.5 }), "first tick fires immediately")
    // cps = 0.5 + 0.25 * 30 = 8; gap = -ln(0.5)/8 ≈ 0.0866 s
    expect(!s.tick(frac: 0.5, now: 100.05, random: { 0.5 }), "before gap elapses: no click")
    expect(s.tick(frac: 0.5, now: 100.09, random: { 0.5 }), "after gap elapses: click")

    // minimum gap is 15 ms
    s = ClickScheduler()
    // near-zero draw gives near-zero exponential gap, clamped to 15 ms:
    // gap = -ln(1 - 0.000001) / 30.5 ≈ 3.3e-8 s → 0.015 s
    expect(s.tick(frac: 1.0, now: 50, random: { 0.000001 }), "saturated: first click fires")
    expect(!s.tick(frac: 1.0, now: 50.010, random: { 0.5 }), "within 15 ms: clamped, no click")
    expect(s.tick(frac: 1.0, now: 50.016, random: { 0.5 }), "after 15 ms: click")
}
