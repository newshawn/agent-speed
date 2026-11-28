import CoreFoundation
import Foundation

/// Global macOS menu bar icon spacing stored in the current-host global preferences domain
/// (`NSStatusItemSpacing` and `NSStatusItemSelectionPadding`).
struct SystemMenuBarSpacing: Equatable, Sendable {
    static let spacingKey = "NSStatusItemSpacing"
    static let selectionPaddingKey = "NSStatusItemSelectionPadding"

    static let defaultSpacing = 16
    static let defaultSelectionPadding = 12
    static let range: ClosedRange<Int> = 0...20

    var spacing: Int?
    var selectionPadding: Int?

    static let systemDefault = SystemMenuBarSpacing(spacing: nil, selectionPadding: nil)

    var isSystemDefault: Bool { spacing == nil && selectionPadding == nil }

    var effectiveSpacing: Int { Self.clamp(spacing ?? Self.defaultSpacing) }
    var effectiveSelectionPadding: Int { Self.clamp(selectionPadding ?? Self.defaultSelectionPadding) }

    var clamped: SystemMenuBarSpacing {
        SystemMenuBarSpacing(
            spacing: spacing.map(Self.clamp),
            selectionPadding: selectionPadding.map(Self.clamp)
        )
    }

    var matchingPreset: SystemMenuBarSpacingPreset? {
        if isSystemDefault { return .systemDefault }
        return SystemMenuBarSpacingPreset.allCases.first { preset in
            preset != .systemDefault && preset.value == self
        }
    }

    static func clamp(_ value: Int) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

enum SystemMenuBarSpacingPreset: String, CaseIterable, Identifiable, Sendable {
    case systemDefault
    case balanced
    case compact
    case tight

    var id: String { rawValue }

    var value: SystemMenuBarSpacing {
        switch self {
        case .systemDefault: .systemDefault
        case .balanced: SystemMenuBarSpacing(spacing: 8, selectionPadding: 8)
        case .compact: SystemMenuBarSpacing(spacing: 6, selectionPadding: 6)
        case .tight: SystemMenuBarSpacing(spacing: 4, selectionPadding: 4)
        }
    }
}

enum SystemMenuBarSpacingError: Error, Equatable, Sendable {
    case synchronizeFailed
    case refreshFailed(code: Int32, detail: String)
}

protocol SystemMenuBarSpacingStore: Sendable {
    func read() -> SystemMenuBarSpacing
    func write(_ value: SystemMenuBarSpacing) throws
    func refreshMenuBar() throws
}

struct SystemMenuBarSpacingService: Sendable {
    let store: any SystemMenuBarSpacingStore

    init(store: any SystemMenuBarSpacingStore = CFSystemMenuBarSpacingStore.shared) {
        self.store = store
    }

    func current() -> SystemMenuBarSpacing {
        store.read()
    }

    func apply(_ value: SystemMenuBarSpacing) throws -> SystemMenuBarSpacing {
        let normalized = value.isSystemDefault ? .systemDefault : value.clamped
        try store.write(normalized)
        try store.refreshMenuBar()
        return store.read()
    }

    func resetToDefault() throws -> SystemMenuBarSpacing {
        try apply(.systemDefault)
    }
}

struct CFSystemMenuBarSpacingStore: SystemMenuBarSpacingStore {
    static let shared = CFSystemMenuBarSpacingStore()

    func read() -> SystemMenuBarSpacing {
        CFPreferencesSynchronize(
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
        return SystemMenuBarSpacing(
            spacing: readInt(forKey: SystemMenuBarSpacing.spacingKey),
            selectionPadding: readInt(forKey: SystemMenuBarSpacing.selectionPaddingKey)
        )
    }

    func write(_ value: SystemMenuBarSpacing) throws {
        setInt(value.spacing, forKey: SystemMenuBarSpacing.spacingKey)
        setInt(value.selectionPadding, forKey: SystemMenuBarSpacing.selectionPaddingKey)
        guard CFPreferencesSynchronize(
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        ) else {
            throw SystemMenuBarSpacingError.synchronizeFailed
        }
    }

    func refreshMenuBar() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["ControlCenter"]
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = stderr.fileHandleForReading.readDataToEndOfFile()
            let detail = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw SystemMenuBarSpacingError.refreshFailed(code: process.terminationStatus, detail: detail)
        }
    }

    private func readInt(forKey key: String) -> Int? {
        guard let raw = CFPreferencesCopyValue(
            key as CFString,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        ) else {
            return nil
        }
        if let number = raw as? NSNumber { return number.intValue }
        if let text = raw as? String { return Int(text) }
        return nil
    }

    private func setInt(_ value: Int?, forKey key: String) {
        let cfValue: CFPropertyList? = value.map { NSNumber(value: SystemMenuBarSpacing.clamp($0)) }
        CFPreferencesSetValue(
            key as CFString,
            cfValue,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
    }
}
