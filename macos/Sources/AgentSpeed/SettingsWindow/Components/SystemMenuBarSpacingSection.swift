import SwiftUI

/// Interactive control section in Settings → Menu Bar for adjusting global macOS menu bar icon spacing
/// (`NSStatusItemSpacing` and `NSStatusItemSelectionPadding`).
struct SystemMenuBarSpacingSection: View {
    let model: AppModel
    private let service = SystemMenuBarSpacingService()

    @State private var saved: SystemMenuBarSpacing = .systemDefault
    @State private var draftSpacing: Double = Double(SystemMenuBarSpacing.defaultSpacing)
    @State private var draftPadding: Double = Double(SystemMenuBarSpacing.defaultSelectionPadding)
    @State private var draftIsDefault = true
    @State private var isApplying = false
    @State private var feedback: Feedback?

    private struct Feedback: Equatable {
        let text: String
        let isError: Bool
    }

    private var draftValue: SystemMenuBarSpacing {
        if draftIsDefault { return .systemDefault }
        return SystemMenuBarSpacing(
            spacing: SystemMenuBarSpacing.clamp(Int(draftSpacing.rounded())),
            selectionPadding: SystemMenuBarSpacing.clamp(Int(draftPadding.rounded()))
        )
    }

    private var hasUnsavedChanges: Bool { draftValue != saved }

    private var copy: Copy { Copy(language: model.l10n.language) }

    var body: some View {
        Section {
            LabeledContent {
                ValueText(statusLabel(for: saved))
            } label: {
                RowTitle(copy.sectionTitle)
            }

            LabeledContent {
                HStack(spacing: 6) {
                    ForEach(SystemMenuBarSpacingPreset.allCases) { preset in
                        presetButton(preset)
                    }
                }
            } label: {
                RowTitle(copy.presetLabel)
            }

            SliderRow(
                title: copy.spacingLabel,
                value: integerBinding($draftSpacing),
                range: Double(SystemMenuBarSpacing.range.lowerBound)...Double(SystemMenuBarSpacing.range.upperBound),
                step: 1,
                valueText: "\(Int(draftSpacing.rounded())) pt"
            ) {
                SliderEndDot(size: 5, opacity: 0.45)
            } maximumLabel: {
                SliderEndDot(size: 10, opacity: 0.85)
            }

            SliderRow(
                title: copy.paddingLabel,
                value: integerBinding($draftPadding),
                range: Double(SystemMenuBarSpacing.range.lowerBound)...Double(SystemMenuBarSpacing.range.upperBound),
                step: 1,
                valueText: "\(Int(draftPadding.rounded())) pt"
            ) {
                SliderEndDot(size: 5, opacity: 0.45)
            } maximumLabel: {
                SliderEndDot(size: 10, opacity: 0.85)
            }

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button(copy.resetButton) {
                    apply(.systemDefault)
                }
                .disabled(isApplying || (saved.isSystemDefault && draftIsDefault))

                if hasUnsavedChanges {
                    Button(copy.applyButton) {
                        apply(draftValue)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isApplying)
                } else {
                    Button(copy.applyButton) {
                        apply(draftValue)
                    }
                    .disabled(isApplying)
                }
            }

            if let feedback {
                Notice(
                    text: feedback.text,
                    symbol: feedback.isError ? "exclamationmark.triangle" : "checkmark.circle",
                    tint: feedback.isError ? .orange : .secondary
                )
            }
        } footer: {
            SectionFootnote(copy.footnote)
        }
        .onAppear {
            loadCurrent()
        }
    }

    @ViewBuilder
    private func presetButton(_ preset: SystemMenuBarSpacingPreset) -> some View {
        let selected = draftValue.matchingPreset == preset
        if selected {
            Button(copy.presetTitle(preset)) { selectPreset(preset) }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isApplying)
        } else {
            Button(copy.presetTitle(preset)) { selectPreset(preset) }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isApplying)
        }
    }

    private func integerBinding(_ target: Binding<Double>) -> Binding<Double> {
        Binding(
            get: { target.wrappedValue },
            set: { newValue in
                let clamped = Double(SystemMenuBarSpacing.clamp(Int(newValue.rounded())))
                if clamped != target.wrappedValue || draftIsDefault {
                    target.wrappedValue = clamped
                    draftIsDefault = false
                }
            }
        )
    }

    private func selectPreset(_ preset: SystemMenuBarSpacingPreset) {
        let value = preset.value
        draftIsDefault = value.isSystemDefault
        draftSpacing = Double(value.effectiveSpacing)
        draftPadding = Double(value.effectiveSelectionPadding)
    }

    private func loadCurrent() {
        let current = service.current()
        saved = current
        draftIsDefault = current.isSystemDefault
        draftSpacing = Double(current.effectiveSpacing)
        draftPadding = Double(current.effectiveSelectionPadding)
    }

    private func apply(_ target: SystemMenuBarSpacing) {
        isApplying = true
        feedback = nil
        let service = self.service
        let copy = self.copy
        Task.detached(priority: .userInitiated) {
            do {
                let updated = try service.apply(target)
                await MainActor.run {
                    saved = updated
                    draftIsDefault = updated.isSystemDefault
                    draftSpacing = Double(updated.effectiveSpacing)
                    draftPadding = Double(updated.effectiveSelectionPadding)
                    isApplying = false
                    feedback = Feedback(
                        text: updated.isSystemDefault ? copy.resetSucceeded : copy.applySucceeded(updated),
                        isError: false
                    )
                }
            } catch {
                await MainActor.run {
                    isApplying = false
                    feedback = Feedback(text: copy.failureMessage(error), isError: true)
                }
            }
        }
    }

    private func statusLabel(for value: SystemMenuBarSpacing) -> String {
        if value.isSystemDefault { return copy.defaultStatus }
        return "\(value.effectiveSpacing) / \(value.effectiveSelectionPadding) pt"
    }
}

private struct Copy: Sendable {
    let language: AppLanguage

    var sectionTitle: String {
        switch language {
        case .zhHans: "系统菜单栏间距"
        case .zhHant: "系統選單列間距"
        case .ja: "システムメニューバーの間隔"
        case .en: "System Menu Bar Spacing"
        }
    }

    var presetLabel: String {
        switch language {
        case .zhHans: "快捷档位"
        case .zhHant: "快捷檔位"
        case .ja: "プリセット"
        case .en: "Presets"
        }
    }

    var spacingLabel: String {
        switch language {
        case .zhHans: "图标间距"
        case .zhHant: "圖示間距"
        case .ja: "アイコン間隔"
        case .en: "Icon spacing"
        }
    }

    var paddingLabel: String {
        switch language {
        case .zhHans: "点击底框留白"
        case .zhHant: "點擊底框留白"
        case .ja: "選択枠の余白"
        case .en: "Selection padding"
        }
    }

    var applyButton: String {
        switch language {
        case .zhHans: "应用并刷新"
        case .zhHant: "套用並重新整理"
        case .ja: "適用して更新"
        case .en: "Apply & Refresh"
        }
    }

    var resetButton: String {
        switch language {
        case .zhHans: "恢复系统默认"
        case .zhHant: "恢復系統預設"
        case .ja: "システム既定に戻す"
        case .en: "Reset to Default"
        }
    }

    var defaultStatus: String {
        switch language {
        case .zhHans: "系统默认（约 16 / 12 pt）"
        case .zhHant: "系統預設（約 16 / 12 pt）"
        case .ja: "システム既定（約 16 / 12 pt）"
        case .en: "System default (~16 / 12 pt)"
        }
    }

    var resetSucceeded: String {
        switch language {
        case .zhHans: "已恢复系统默认间距并刷新控制中心。"
        case .zhHant: "已恢復系統預設間距並重新整理控制中心。"
        case .ja: "システム既定の間隔に戻し、コントロールセンターを更新しました。"
        case .en: "Restored system default spacing and refreshed Control Center."
        }
    }

    var footnote: String {
        switch language {
        case .zhHans: "调整 macOS 全局菜单栏图标间隔与点击高亮留白。点击“应用并刷新”后系统图标立即生效；已运行的第三方菜单栏应用需重启对应应用或注销重登后全量对齐。"
        case .zhHant: "調整 macOS 全域選單列圖示間隔與點擊高光留白。點擊「套用並重新整理」後系統圖示立即生效；已執行的第三方選單列應用需重新啟動或登出再登入後完全對齊。"
        case .ja: "macOS 全体のメニューバー間隔と選択枠の余白を調整します。「適用して更新」でシステムアイコンは即時反映されます。起動済みの他社製アプリは再起動または再ログインで反映されます。"
        case .en: "Adjusts macOS global menu bar icon spacing and click highlight padding. System extras update immediately on Apply; already-running third-party menu bar apps update after relaunching or logging out and back in."
        }
    }

    func presetTitle(_ preset: SystemMenuBarSpacingPreset) -> String {
        switch preset {
        case .systemDefault:
            switch language {
            case .zhHans: "默认"
            case .zhHant: "預設"
            case .ja: "既定"
            case .en: "Default"
            }
        case .balanced: "8 / 8"
        case .compact: "6 / 6"
        case .tight: "4 / 4"
        }
    }

    func applySucceeded(_ value: SystemMenuBarSpacing) -> String {
        let pair = "\(value.effectiveSpacing) / \(value.effectiveSelectionPadding) pt"
        return switch language {
        case .zhHans: "已应用 \(pair) 并刷新控制中心。"
        case .zhHant: "已套用 \(pair) 並重新整理控制中心。"
        case .ja: "\(pair) を適用し、コントロールセンターを更新しました。"
        case .en: "Applied \(pair) and refreshed Control Center."
        }
    }

    func failureMessage(_ error: Error) -> String {
        switch language {
        case .zhHans: "应用失败：\(error.localizedDescription)"
        case .zhHant: "套用失敗：\(error.localizedDescription)"
        case .ja: "適用に失敗しました：\(error.localizedDescription)"
        case .en: "Failed to apply: \(error.localizedDescription)"
        }
    }
}
