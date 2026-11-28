import Foundation
import Testing
@testable import AgentSpeed

@Suite("Compact stacked menu bar layout")
@MainActor
struct StatusItemCompactLayoutTests {
    @Test func stackedTpsLayoutIsCompactAndNarrowerThanInlineTokS() {
        #expect(StatusItemValue.compactTokenUnit == "TPS")
        let stacked = StatusItemLayout(mode: .glyphValue, showsUnit: true, unit: StatusItemValue.compactTokenUnit,
                                       valueWidth: StatusItemLayout.stackedValueWidth(of: "69"), height: 24)
        let inlineTokS = StatusItemLayout(mode: .glyphValue, showsUnit: true, unit: "tok/s",
                                          valueWidth: StatusItemLayout.valueWidth(of: "69"), height: 24)
        #expect(stacked.usesStackedUnit)
        #expect(!inlineTokS.usesStackedUnit)
        #expect(stacked.length < inlineTokS.length)
        #expect(stacked.length <= 54)
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

    @Test func customFontSizeAndWeightScaleMonotonicallyWithDefaultMatchingTickTick() {
        let small = StatusItemLayout(mode: .glyphValue, showsUnit: true, unit: StatusItemValue.compactTokenUnit,
                                     valueWidth: StatusItemLayout.stackedValueWidth(of: "69", fontSize: 9.0, weight: .regular),
                                     height: 24, fontSize: 9.0, fontWeight: .regular)
        let tickTickDefault = StatusItemLayout(mode: .glyphValue, showsUnit: true, unit: StatusItemValue.compactTokenUnit,
                                               valueWidth: StatusItemLayout.stackedValueWidth(of: "69", fontSize: 13.5, weight: .bold),
                                               height: 24, fontSize: 13.5, fontWeight: .bold)
        let large = StatusItemLayout(mode: .glyphValue, showsUnit: true, unit: StatusItemValue.compactTokenUnit,
                                     valueWidth: StatusItemLayout.stackedValueWidth(of: "69", fontSize: 15.0, weight: .bold),
                                     height: 24, fontSize: 15.0, fontWeight: .bold)
        #expect(small.length < tickTickDefault.length)
        #expect(tickTickDefault.length < large.length)
        #expect(tickTickDefault.resolvedGlyphDiameter == 15.5)
        #expect(tickTickDefault.resolvedGlyphLineWidth == 2.25)

        let lockedAtBold = ["0", "6.4", "69", "128", "999"].map { text in
            StatusItemLayout(mode: .glyphValue, showsUnit: true, unit: StatusItemValue.compactTokenUnit,
                             valueWidth: StatusItemLayout.stackedValueWidth(of: text, fontSize: 13.5, weight: .bold),
                             height: 24, fontSize: 13.5, fontWeight: .bold).length
        }
        #expect(Set(lockedAtBold).count == 1)
    }
}
