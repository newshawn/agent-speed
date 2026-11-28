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
                    title: barScaleLabel(for: l10n.language),
                    value: Binding(
                        get: { settings.barScale },
                        set: { settings.barScale = AppSettings.snapBarScale($0) }
                    ),
                    range: AppSettings.barScaleRange,
                    step: AppSettings.barScaleStep,
                    valueText: "\(Int((settings.barScale * 100).rounded()))%"
                ) {
                    SliderEndDot(size: 5, opacity: 0.45)
                } maximumLabel: {
                    SliderEndDot(size: 10, opacity: 0.85)
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

    private func barScaleLabel(for language: AppLanguage) -> String {
        switch language {
        case .zhHans: "菜单栏缩放"
        case .zhHant: "選單列縮放"
        case .ja: "メニューバー拡大率"
        case .en: "Menu bar scale"
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
