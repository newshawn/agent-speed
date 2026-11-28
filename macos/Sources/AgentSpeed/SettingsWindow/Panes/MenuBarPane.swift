import SwiftUI

struct MenuBarPane: View {
    let model: AppModel

    var body: some View {
        @Bindable var settings = model.settings
        let l10n = model.l10n
        Form {
            Section {
                MenuBarPreview(model: model)
            }

            Section {
                Picker(l10n("settings.bar.mode"), selection: $settings.barMode) {
                    ForEach(BarDisplayMode.allCases) { mode in
                        Text(l10n(mode.titleKey)).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)

                SettingToggle(title: l10n("settings.bar.colored"), isOn: $settings.barColoredGlyph)
                    .disabled(!settings.barMode.showsGlyph)

                SettingToggle(title: l10n("settings.bar.unit"), isOn: $settings.barShowsUnit)
                    .disabled(!settings.barMode.showsValue)

                SliderRow(
                    title: fontSizeLabel(for: l10n.language),
                    value: Binding(
                        get: { settings.barFontSize },
                        set: { settings.barFontSize = AppSettings.snapBarFontSize($0) }
                    ),
                    range: AppSettings.barFontSizeRange,
                    step: AppSettings.barFontSizeStep,
                    valueText: formatPointSize(settings.barFontSize)
                ) {
                    SliderEndDot(size: 5, opacity: 0.45)
                } maximumLabel: {
                    SliderEndDot(size: 10, opacity: 0.85)
                }

                SegmentedRow(
                    title: fontWeightLabel(for: l10n.language),
                    selection: $settings.barFontWeight,
                    segmentWidth: 68,
                    count: BarFontWeight.allCases.count
                ) {
                    ForEach(BarFontWeight.allCases) { weight in
                        Text(weightTitle(weight, language: l10n.language)).tag(weight)
                    }
                }

                BarTrafficPicker(model: model)
                    .disabled(settings.barMode == .glyph)

                BarIntelligenceToggle(model: model)
            }

            Section {
                BarValuePicker(model: model)
            } footer: {
                SectionFootnote(l10n("settings.liveUnit.hint"))
            }
        }
        .settingsForm()
    }

    private func formatPointSize(_ size: Double) -> String {
        let rounded = (size * 10).rounded() / 10
        return rounded.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(rounded)) pt"
            : String(format: "%.1f pt", rounded)
    }

    private func fontSizeLabel(for language: AppLanguage) -> String {
        switch language {
        case .zhHans: "字体大小"
        case .zhHant: "字體大小"
        case .ja: "フォントサイズ"
        case .en: "Font size"
        }
    }

    private func fontWeightLabel(for language: AppLanguage) -> String {
        switch language {
        case .zhHans: "字体粗细"
        case .zhHant: "字體粗細"
        case .ja: "フォントの太さ"
        case .en: "Font weight"
        }
    }

    private func weightTitle(_ weight: BarFontWeight, language: AppLanguage) -> String {
        switch (weight, language) {
        case (.regular, .zhHans): "常规"
        case (.regular, .zhHant): "常規"
        case (.regular, .ja): "標準"
        case (.regular, .en): "Regular"
        case (.medium, .zhHans): "中等"
        case (.medium, .zhHant): "中等"
        case (.medium, .ja): "中"
        case (.medium, .en): "Medium"
        case (.semibold, .zhHans): "半粗"
        case (.semibold, .zhHant): "半粗"
        case (.semibold, .ja): "中太"
        case (.semibold, .en): "Semibold"
        case (.bold, .zhHans): "粗体"
        case (.bold, .zhHant): "粗體"
        case (.bold, .ja): "太字"
        case (.bold, .en): "Bold"
        }
    }
}

/// The menu bar's live value (DESIGN 3, 9): tok/s, money, or tok/s with the money rate after it.
private struct BarValuePicker: View {
    let model: AppModel

    private enum Choice: Hashable { case tokens, cost, both }

    var body: some View {
        let l10n = model.l10n
        let settings = model.settings
        let choice = Binding<Choice>(
            get: { settings.liveUnit == .cost ? .cost : settings.barSecondary ? .both : .tokens },
            set: { choice in
                settings.liveUnit = choice == .cost ? .cost : .tokens
                settings.barSecondary = choice == .both
            }
        )
        SegmentedRow(title: l10n("settings.liveUnit"), selection: choice, segmentWidth: 110, count: 3) {
            Text(l10n("settings.liveUnit.tokens")).tag(Choice.tokens)
            Text(l10n("settings.liveUnit.cost", model.cost.symbol)).tag(Choice.cost)
            Text(l10n("settings.liveUnit.both")).tag(Choice.both)
        }
    }
}
