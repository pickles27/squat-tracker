import Foundation

enum StrengthMath {
    /// Rounds to the nearest loadable increment (e.g. 2.5 kg).
    static func round(_ weight: Double, to increment: Double) -> Double {
        guard increment > 0 else { return clean(max(0, weight)) }
        return clean(max(0, (weight / increment).rounded() * increment))
    }

    /// Strips floating-point noise (76.37500000001 → 76.375).
    static func clean(_ value: Double) -> Double {
        (value * 1000).rounded() / 1000
    }

    /// Wendler's estimate: weight × reps × 0.0333 + weight.
    static func estimatedOneRepMax(weight: Double, reps: Int) -> Double {
        guard weight > 0, reps > 0 else { return 0 }
        if reps == 1 { return weight }
        return clean(weight * Double(reps) * 0.0333 + weight)
    }
}

struct PlateLoadout: Hashable, Sendable {
    var bar: Double
    /// Plates for one side, heaviest first.
    var perSide: [Double]
    /// Weight per side that can't be made with the available plates.
    var remainder: Double
}

enum PlateCalculator {
    static func loadout(for total: Double, unit: WeightUnit) -> PlateLoadout? {
        loadout(for: total, bar: unit.barWeight, plates: unit.plates)
    }

    static func loadout(for total: Double, bar: Double, plates: [Double]) -> PlateLoadout? {
        guard total >= bar - 0.001 else { return nil }
        var remaining = (total - bar) / 2
        var perSide: [Double] = []
        for plate in plates.sorted(by: >) where plate > 0 {
            while remaining >= plate - 0.001 {
                perSide.append(plate)
                remaining -= plate
            }
        }
        return PlateLoadout(bar: bar, perSide: perSide, remainder: StrengthMath.clean(max(0, remaining)))
    }
}
