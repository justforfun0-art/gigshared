import SwiftUI
import Combine

/// In-app language override that mirrors Android's LanguageManager: the user
/// picks a language in Profile, we persist it, and the whole app re-renders in
/// that language regardless of the device's system language.
///
/// iOS has no first-class "force this language at runtime" switch, so we load
/// the chosen `.lproj` bundle ourselves and resolve every UI string through it
/// via the global `L(_:)` helper. Changing `language` bumps `@Published`, which
/// (because RootView observes the shared manager as an `@StateObject`) rebuilds
/// the view tree with the new bundle. We also publish the matching SwiftUI
/// `Locale` so number/date formatting follows suit.
final class LocaleManager: ObservableObject {
    static let shared = LocaleManager()

    /// Supported languages, in the same order and with the same native labels
    /// as Android's picker (LanguageTogglePill / settings).
    enum Language: String, CaseIterable, Identifiable {
        case en, hi, ta, te, kn
        var id: String { rawValue }

        /// Name shown in the picker, written in its own script (Android parity).
        var nativeName: String {
            switch self {
            case .en: return "English"
            case .hi: return "हिंदी"
            case .ta: return "தமிழ்"
            case .te: return "తెలుగు"
            case .kn: return "ಕನ್ನಡ"
            }
        }

        /// English name for the secondary line in the picker.
        var englishName: String {
            switch self {
            case .en: return "English"
            case .hi: return "Hindi"
            case .ta: return "Tamil"
            case .te: return "Telugu"
            case .kn: return "Kannada"
            }
        }
    }

    private static let storageKey = "gighour.language"

    @Published private(set) var language: Language {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Self.storageKey)
            bundle = Self.bundle(for: language)
        }
    }

    /// SwiftUI locale to inject into the environment for formatting.
    var locale: Locale { Locale(identifier: language.rawValue) }

    /// The `.lproj` bundle backing the current language (falls back to main).
    private(set) var bundle: Bundle

    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.storageKey)
        // Default to the device language if it's one we support, else English.
        let initial: Language
        if let saved, let lang = Language(rawValue: saved) {
            initial = lang
        } else if let sys = Locale.preferredLanguages.first?.prefix(2),
                  let lang = Language(rawValue: String(sys)) {
            initial = lang
        } else {
            initial = .en
        }
        self.language = initial
        self.bundle = Self.bundle(for: initial)
    }

    func setLanguage(_ language: Language) {
        guard language != self.language else { return }
        self.language = language
    }

    /// Resolve a localized string for `key` through the current language bundle.
    func string(_ key: String, comment: String = "") -> String {
        bundle.localizedString(forKey: key, value: key, table: nil)
    }

    private static func bundle(for language: Language) -> Bundle {
        guard let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
              let b = Bundle(path: path) else {
            return .main
        }
        return b
    }
}

/// Global shorthand to localize a key through the in-app language override.
/// Use everywhere instead of bare string literals, e.g. `Text(L("earnings"))`.
func L(_ key: String) -> String {
    LocaleManager.shared.string(key)
}

/// Localize with positional `%@` / `%d` arguments (e.g. `L("applied_on", date)`).
func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: LocaleManager.shared.string(key), arguments: args)
}
