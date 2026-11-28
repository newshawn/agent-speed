import Foundation
import Testing
@testable import AgentSpeed

@Suite("Compact stacked menu bar layout")
@MainActor
struct StatusItemCompactLayoutTests {
    @Test func stackedTpsLayoutIsCompactAndSignificantlyNarrowerThanInlineTokS() {
        #expect(StatusItemValue.compactTokenUnit == "TPS")
        let stacked = StatusItemLayout(mode: .glyphValue, showsUnit: true, unit: StatusItemValue.compactTokenUnit,
                                       valueWidth: StatusItemLayout.stackedValueWidth(of: "69"), height: 24)
        let inlineTokS = StatusItemLayout(mode: .glyphValue, showsUnit: true, unit: "tok/s",
                                          valueWidth: StatusItemLayout.valueWidth(of: "69"), height: 24)
        #expect(stacked.usesStackedUnit)
        #expect(!inlineTokS.usesStackedUnit)
        #expect(stacked.length < inlineTokS.length)
        #expect(stacked.length <= 45)
    }

    @Test func oneToThreeDigitTokenSpeedsKeepFixedStackedWidthAndDoNotJitter() {
        let samples = ["0", "4.5", "9.9", "45", "69", "128", "999"]
        let lengths = samples.map { text in
            StatusItemLayout(mode: .glyphValue, showsUnit: true, unit: StatusItemValue.compactTokenUnit,
                             valueWidth: StatusItemLayout.stackedValueWidth(of: text), height: 24).length
        }
        #expect(Set(lengths).count == 1)

        // Four-digit compact strings (e.g. 1.20k) expand smoothly beyond the 3-digit stacked column.
        let peak = StatusItemLayout(mode: .glyphValue, showsUnit: true, unit: StatusItemValue.compactTokenUnit,
                                    valueWidth: StatusItemLayout.stackedValueWidth(of: "1.20k"), height: 24)
        #expect(peak.length > (lengths.first ?? 0))

        // Glyph-only mode never reserves value width.
        let glyphOnly = StatusItemLayout(mode: .glyph, showsUnit: true, unit: StatusItemValue.compactTokenUnit,
                                         valueWidth: StatusItemLayout.minimumStackedTokenWidth, height: 24)
        #expect(glyphOnly.valueWidth == 0)
        #expect(!glyphOnly.usesStackedUnit)
        #expect(glyphOnly.length < (lengths.first ?? 0))
    }

    @Test func barScaleAdjustsStackedWidthMonotonicallyWhileKeepingZeroTo999Locked() {
        let small = StatusItemLayout(mode: .glyphValue, showsUnit: true, unit: StatusItemValue.compactTokenUnit,
                                     valueWidth: StatusItemLayout.stackedValueWidth(of: "69", scale: 0.9), height: 24, scale: 0.9)
        let defaultScale = StatusItemLayout(mode: .glyphValue, showsUnit: true, unit: StatusItemValue.compactTokenUnit,
                                            valueWidth: StatusItemLayout.stackedValueWidth(of: "69", scale: 1.2), height: 24, scale: 1.2)
        let large = StatusItemLayout(mode: .glyphValue, showsUnit: true, unit: StatusItemValue.compactTokenUnit,
                                     valueWidth: StatusItemLayout.stackedValueWidth(of: "69", scale: 1.35), height: 24, scale: 1.35)
        #expect(small.length < defaultScale.length)
        #expect(defaultScale.length < large.length)

        let lockedAtDefault = ["0", "6.4", "69", "128", "999"].map { text in
            StatusItemLayout(mode: .glyphValue, showsUnit: true, unit: StatusItemValue.compactTokenUnit,
                             valueWidth: StatusItemLayout.stackedValueWidth(of: text, scale: 1.2), height: 24, scale: 1.2).length
        }
        #expect(Set(lockedAtDefault).count == 1)
    }
}
