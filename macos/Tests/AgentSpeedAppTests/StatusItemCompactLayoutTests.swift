import Foundation
import Testing
@testable import AgentSpeed

@Suite("Compact menu bar layout")
@MainActor
struct StatusItemCompactLayoutTests {
    @Test func compactMenuBarUnitIsTpsAndNarrowerThanTokS() {
        #expect(StatusItemValue.compactTokenUnit == "tps")
        let minWidth = StatusItemLayout.minimumTokenValueWidth
        let tpsLayout = StatusItemLayout(mode: .glyphValue, showsUnit: true, unit: StatusItemValue.compactTokenUnit,
                                         valueWidth: minWidth, height: 24)
        let tokSLayout = StatusItemLayout(mode: .glyphValue, showsUnit: true, unit: "tok/s",
                                          valueWidth: minWidth, height: 24)
        #expect(tpsLayout.length < tokSLayout.length)
    }

    @Test func oneToThreeDigitTokenSpeedsKeepFixedWidthAndDoNotJitter() {
        let minWidth = StatusItemLayout.minimumTokenValueWidth
        let samples = ["0", "4.5", "9.9", "45", "120", "999"]
        let lengths = samples.map { text in
            let width = max(minWidth, StatusItemLayout.valueWidth(of: text))
            return StatusItemLayout(mode: .glyphValue, showsUnit: true, unit: StatusItemValue.compactTokenUnit,
                                    valueWidth: width, height: 24).length
        }
        #expect(Set(lengths).count == 1)

        // Four-digit compact strings (e.g. 1.20k) still expand cleanly beyond the 3-digit floor.
        let peakWidth = max(minWidth, StatusItemLayout.valueWidth(of: "1.20k"))
        let peakLayout = StatusItemLayout(mode: .glyphValue, showsUnit: true, unit: StatusItemValue.compactTokenUnit,
                                          valueWidth: peakWidth, height: 24)
        #expect(peakLayout.length >= (lengths.first ?? 0))

        // Glyph-only mode never reserves value width.
        let glyphOnly = StatusItemLayout(mode: .glyph, showsUnit: true, unit: StatusItemValue.compactTokenUnit,
                                         valueWidth: minWidth, height: 24)
        #expect(glyphOnly.valueWidth == 0)
        #expect(glyphOnly.length < (lengths.first ?? 0))
    }
}
