import Foundation

public enum ZoneLevel: CaseIterable {
    case background, elevated, hot, critical, meltdown

    public var label: String {
        switch self {
        case .background: return "BACKGROUND"
        case .elevated: return "ELEVATED"
        case .hot: return "HOT"
        case .critical: return "CRITICAL"
        case .meltdown: return "MELTDOWN"
        }
    }

    /// Minimum tokens/min for this zone.
    public var threshold: Double {
        switch self {
        case .background: return 0
        case .elevated: return 2_000
        case .hot: return 20_000
        case .critical: return 60_000
        case .meltdown: return 200_000
        }
    }

    public static func forRate(_ rate: Double) -> ZoneLevel {
        var result: ZoneLevel = .background
        for zone in allCases where rate >= zone.threshold { result = zone }
        return result
    }
}

/// tokens/min where the gauge starts moving.
public let rateFloor: Double = 60
/// tokens/min that pins the needle.
public let rateCeil: Double = 300_000

/// 0...1 position on a log scale between rateFloor and rateCeil.
public func gaugeFraction(rate: Double) -> Double {
    guard rate > rateFloor else { return 0 }
    let f = log(rate / rateFloor) / log(rateCeil / rateFloor)
    return min(1, f)
}
