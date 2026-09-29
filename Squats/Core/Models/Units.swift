import Foundation

enum WeightUnit: String, Codable, CaseIterable, Identifiable, Sendable {
    case kg
    case lb

    var id: String { rawValue }
    var symbol: String { rawValue }
    var name: String { self == .kg ? "Kilograms" : "Pounds" }

    /// Wendler's recommended training-max bump per cycle for lower-body lifts.
    var defaultCycleIncrement: Double { self == .kg ? 5 : 10 }
    var defaultRounding: Double { self == .kg ? 2.5 : 5 }
    var roundingOptions: [Double] { self == .kg ? [0.5, 1, 1.25, 2.5, 5] : [1, 2.5, 5, 10] }
    var incrementOptions: [Double] { self == .kg ? [2.5, 5, 10] : [5, 10, 20] }
    var barWeight: Double { self == .kg ? 20 : 45 }
    var plates: [Double] { self == .kg ? [25, 20, 15, 10, 5, 2.5, 1.25] : [45, 35, 25, 10, 5, 2.5] }
    /// Step used by the +/- weight controls.
    var weightStep: Double { self == .kg ? 2.5 : 5 }
}

enum WeightFormat {
    /// Locale-independent number with trailing zeros trimmed: "102.5", "100", "1.25".
    static func plain(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        var text = String(format: "%.2f", rounded)
        while text.hasSuffix("0") { text.removeLast() }
        return text
    }

    /// Localized number for display.
    static func display(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    static func display(_ value: Double, unit: WeightUnit) -> String {
        "\(display(value)) \(unit.symbol)"
    }
}
