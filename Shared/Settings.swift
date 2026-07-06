import Foundation

/// Preference keys shared between the app and the Finder Sync extension
/// through the app-group defaults suite.
enum MTSettings {
    static let suiteName = "Y5K2497B6G.com.metinaksu.metools"

    // Finder context-menu features (read by the extension).
    static let cutPasteMenu = "feature.cutPasteMenu"
    static let newTextFile = "feature.newTextFile"

    // Keyboard features (handled by the app's event tap).
    static let returnOpens = "feature.returnOpens"
    static let f2Rename = "feature.f2Rename"
    static let ctrlCCopies = "feature.ctrlCCopies"
    static let ctrlVPastes = "feature.ctrlVPastes"
    static let ctrlXCuts = "feature.ctrlXCuts"
    static let ctrlZUndoes = "feature.ctrlZUndoes"
    static let backspaceDeletes = "feature.backspaceDeletes"

    static let allKeyboardKeys = [returnOpens, f2Rename, ctrlCCopies, ctrlVPastes, ctrlXCuts, ctrlZUndoes, backspaceDeletes]

    static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    /// First-launch defaults: every feature enabled.
    static func registerDefaults() {
        let allOn = [cutPasteMenu, newTextFile, returnOpens, f2Rename,
                     ctrlCCopies, ctrlVPastes, ctrlXCuts, ctrlZUndoes, backspaceDeletes]
            .reduce(into: [String: Any]()) { $0[$1] = true }
        defaults.register(defaults: allOn)
    }

    static var anyKeyboardFeatureEnabled: Bool {
        allKeyboardKeys.contains { defaults.bool(forKey: $0) }
    }
}
