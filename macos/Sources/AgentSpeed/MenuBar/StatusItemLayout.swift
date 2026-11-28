import AppKit

/// Geometry of the menu bar item (DESIGN section 3): `[gauge] [value] [unit]`, hugging its content. Every value is a
/// whole point so the ring and the text baseline land on device pixels at any backing scale.
struct StatusItemLayout: Equatable {
    static let valueSize: CGFloat = 13
    static let unitSize: CGFloat = 10
    static let stackedValueSize: CGFloat = 10.5
    static let stackedUnitSize: CGFloat = 7
    static let stackedUnitKern: CGFloat = 0.35
    static let stackedLineGap: CGFloat = 2
    /// About 1.2 × the value's cap height (DESIGN section 3).
    static let glyphDiameter: CGFloat = 13
    static let glyphLineWidth: CGFloat = 1.75
    /// Minimal inset at both ends; macOS already applies outer spacing and selection padding around status items.
    static let padding: CGFloat = 2
    /// Space between the ring and the value (the digits' side bearing adds about a point).
    static let glyphGap: CGFloat = 3
    static let unitGap: CGFloat = 2

    let showsGlyph: Bool
    let showsValue: Bool
    /// The unit label, or nil when hidden.
    let unit: String?
    /// Room reserved for the value; at least the drawn text, briefly wider while a shorter value proves itself.
    let valueWidth: CGFloat
    let unitWidth: CGFloat
    let height: CGFloat
    /// The money block's width (gap included); 0 without it.
    var secondaryWidth: CGFloat = 0
    /// The network block's width (gap included); 0 without it.
    var trafficWidth: CGFloat = 0
    /// The intelligence block's width (gap included), after the network block; 0 without it.
    var intelligenceWidth: CGFloat = 0
    /// Both readout blocks (DESIGN 10): fixed widths, so the item never changes width with their values.
    var readoutWidth: CGFloat { trafficWidth + intelligenceWidth }

    init(mode: BarDisplayMode, showsUnit: Bool, unit: String, valueWidth: CGFloat, height: CGFloat) {
        showsGlyph = mode.showsGlyph
        showsValue = mode.showsValue
        let resolvedUnit = mode.showsValue && showsUnit && !unit.isEmpty ? unit : nil
        let stacked = resolvedUnit == StatusItemValue.compactTokenUnit
        self.unit = resolvedUnit
        self.valueWidth = showsValue ? (stacked ? max(valueWidth, Self.minimumStackedTokenWidth) : valueWidth) : 0
        unitWidth = resolvedUnit.map {
            stacked ? Self.width(of: $0, font: Self.stackedUnitFont, kern: Self.stackedUnitKern)
                    : Self.width(of: $0, font: Self.unitFont)
        } ?? 0
        self.height = height
    }

    @MainActor
    init(model: AppModel, unit: String? = nil, valueWidth: CGFloat) {
        self.init(
            mode: model.settings.barMode,
            showsUnit: model.settings.barShowsUnit,
            unit: unit ?? StatusItemValue.compactTokenUnit,
            valueWidth: valueWidth,
            height: Self.barHeight
        )
    }

    /// Height of the status bar button the content is drawn in.
    @MainActor
    static var barHeight: CGFloat { max(22, NSStatusBar.system.thickness.rounded()) }

    static var valueFont: NSFont { .monospacedDigitSystemFont(ofSize: valueSize, weight: .regular) }
    static var unitFont: NSFont { .systemFont(ofSize: unitSize, weight: .medium) }
    static var stackedValueFont: NSFont { .monospacedDigitSystemFont(ofSize: stackedValueSize, weight: .semibold) }
    static var stackedUnitFont: NSFont { .systemFont(ofSize: stackedUnitSize, weight: .semibold) }

    /// Drawn width of a formatted value. Digits are tabular, so it only changes with the digit count or format.
    static func valueWidth(of text: String) -> CGFloat {
        width(of: text, font: valueFont)
    }

    static func stackedValueWidth(of text: String) -> CGFloat {
        width(of: text, font: stackedValueFont)
    }

    /// Fixed 3-digit column width for stacked token speed + `TPS` so 0–999 transitions never shift neighbors.
    static var minimumStackedTokenWidth: CGFloat {
        max(
            stackedValueWidth(of: "888"),
            width(of: StatusItemValue.compactTokenUnit, font: stackedUnitFont, kern: stackedUnitKern)
        )
    }

    /// Whether the unit sits underneath the value in a compact 2-line iStat-style column.
    var usesStackedUnit: Bool {
        showsValue && unit == StatusItemValue.compactTokenUnit
    }

    /// Total status item length.
    var length: CGFloat {
        var width = Self.padding * 2
        if showsGlyph { width += Self.glyphDiameter }
        if showsGlyph && showsValue { width += Self.glyphGap }
        if showsValue { width += valueWidth }
        if unit != nil && !usesStackedUnit { width += Self.unitGap + unitWidth }
        return width + secondaryWidth + readoutWidth
    }

    /// Left edge of the money block (its gap starts here).
    var secondaryX: CGFloat { length - Self.padding - readoutWidth - secondaryWidth }

    /// Left edge of the readout blocks (the network block's gap starts here).
    var readoutX: CGFloat { length - Self.padding - readoutWidth }

    /// Left edge of the intelligence block (its gap starts here), after the network block.
    var intelligenceX: CGFloat { length - Self.padding - intelligenceWidth }

    /// Ring center, optically centered on the digits (their cap height) next to it, or on the bar alone.
    var glyphCenter: CGPoint {
        let y = (showsValue && !usesStackedUnit) ? baseline - Self.valueFont.capHeight / 2 : height / 2
        return CGPoint(x: Self.padding + Self.glyphDiameter / 2, y: (y * 2).rounded() / 2)
    }

    /// Left edge of the value.
    var valueX: CGFloat {
        Self.padding + (showsGlyph ? Self.glyphDiameter + Self.glyphGap : 0)
    }

    /// Text baseline measured from the top. Native menu bar titles sit half a point above true cap-height centering.
    var baseline: CGFloat {
        (height / 2 + Self.valueFont.capHeight / 2 - 0.5).rounded()
    }

    private static func width(of string: String, font: NSFont, kern: CGFloat = 0) -> CGFloat {
        var attrs: [NSAttributedString.Key: Any] = [.font: font]
        if kern != 0 { attrs[.kern] = kern }
        return (string as NSString).size(withAttributes: attrs).width.rounded(.up)
    }
}

/// Lets the value's reserved width grow at once but shrink only after a shorter width has held for 6 s, so the
/// item never flickers and its neighbors never jump on every update.
struct StatusItemWidthGovernor {
    static let shrinkDelay: TimeInterval = 6

    private(set) var width: CGFloat = 0
    private var shrinkSince: TimeInterval?
    private var shrinkTarget: CGFloat = 0

    /// Feeds the width the current value needs; returns true when the reserved width changed.
    mutating func update(needed: CGFloat, now: TimeInterval) -> Bool {
        if needed >= width {
            shrinkSince = nil
            guard needed > width else { return false }
            width = needed
            return true
        }
        if let since = shrinkSince {
            shrinkTarget = max(shrinkTarget, needed)
            guard now - since >= Self.shrinkDelay else { return false }
            width = shrinkTarget
            shrinkSince = nil
            return true
        }
        shrinkSince = now
        shrinkTarget = needed
        return false
    }

    /// When a pending shrink becomes due.
    var shrinkDeadline: TimeInterval? { shrinkSince.map { $0 + Self.shrinkDelay } }
}
