import Foundation
import Testing
@testable import AgentSpeed

@Suite("System menu bar spacing & compact unit")
struct SystemMenuBarSpacingTests {
    private final class MockStore: SystemMenuBarSpacingStore, @unchecked Sendable {
        var stored: SystemMenuBarSpacing
        var refreshCount = 0
        var failWrite = false
        var failRefresh = false

        init(initial: SystemMenuBarSpacing = .systemDefault) {
            stored = initial
        }

        func read() -> SystemMenuBarSpacing { stored }

        func write(_ value: SystemMenuBarSpacing) throws {
            if failWrite { throw SystemMenuBarSpacingError.synchronizeFailed }
            stored = value
        }

        func refreshMenuBar() throws {
            if failRefresh { throw SystemMenuBarSpacingError.refreshFailed(code: 1, detail: "No matching processes") }
            refreshCount += 1
        }
    }

    @Test func compactMenuBarUnitIsTpsAndNarrowerThanTokS() {
        #expect(StatusItemValue.compactTokenUnit == "tps")
        let tpsLayout = StatusItemLayout(mode: .glyphValue, showsUnit: true, unit: StatusItemValue.compactTokenUnit,
                                         valueWidth: StatusItemLayout.valueWidth(of: "0"), height: 24)
        let tokSLayout = StatusItemLayout(mode: .glyphValue, showsUnit: true, unit: "tok/s",
                                          valueWidth: StatusItemLayout.valueWidth(of: "0"), height: 24)
        #expect(tpsLayout.length < tokSLayout.length)
        #expect(tpsLayout.length <= 50)
    }

    @Test func systemDefaultMatchesPresetAndEffectiveValues() {
        let state = SystemMenuBarSpacing.systemDefault
        #expect(state.isSystemDefault)
        #expect(state.matchingPreset == .systemDefault)
        #expect(state.effectiveSpacing == 16)
        #expect(state.effectiveSelectionPadding == 12)
    }

    @Test func presetsAndCustomAsymmetricValuesMatchCorrectly() {
        #expect(SystemMenuBarSpacing(spacing: 8, selectionPadding: 8).matchingPreset == .balanced)
        #expect(SystemMenuBarSpacing(spacing: 6, selectionPadding: 6).matchingPreset == .compact)
        #expect(SystemMenuBarSpacing(spacing: 4, selectionPadding: 4).matchingPreset == .tight)
        #expect(SystemMenuBarSpacing(spacing: 6, selectionPadding: 8).matchingPreset == nil)
    }

    @Test func serviceClampsAppliesAndResetsWithoutTouchingHost() throws {
        let store = MockStore()
        let service = SystemMenuBarSpacingService(store: store)

        let applied = try service.apply(SystemMenuBarSpacing(spacing: -5, selectionPadding: 99))
        #expect(applied == SystemMenuBarSpacing(spacing: 0, selectionPadding: 20))
        #expect(store.refreshCount == 1)

        let reset = try service.resetToDefault()
        #expect(reset.isSystemDefault)
        #expect(store.stored == .systemDefault)
        #expect(store.refreshCount == 2)
    }

    @Test func servicePropagatesWriteAndRefreshErrorsExplicitly() {
        let writeFailStore = MockStore()
        writeFailStore.failWrite = true
        #expect(throws: SystemMenuBarSpacingError.synchronizeFailed) {
            try SystemMenuBarSpacingService(store: writeFailStore).apply(SystemMenuBarSpacingPreset.balanced.value)
        }
        #expect(writeFailStore.refreshCount == 0)

        let refreshFailStore = MockStore()
        refreshFailStore.failRefresh = true
        #expect(throws: SystemMenuBarSpacingError.refreshFailed(code: 1, detail: "No matching processes")) {
            try SystemMenuBarSpacingService(store: refreshFailStore).apply(SystemMenuBarSpacingPreset.compact.value)
        }
    }
}
