import Foundation

/// Which physical key triggers dictation. Raw value = CGKeyCode of the modifier.
enum TriggerKey: Int, CaseIterable, Identifiable {
    case rightOption = 61
    case rightCommand = 54
    case rightControl = 62
    case fn = 63          // the globe / fn key

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .rightOption:  return "Right ⌥ Option"
        case .rightCommand: return "Right ⌘ Command"
        case .rightControl: return "Right ⌃ Control"
        case .fn:           return "fn / 🌐 Globe"
        }
    }
}

enum InsertMethod: String, CaseIterable, Identifiable {
    case unicode   // post text directly as synthetic key events (keeps clipboard)
    case paste     // set pasteboard + ⌘V, then restore

    var id: String { rawValue }
    var label: String {
        switch self {
        case .unicode: return "Type directly (keeps clipboard)"
        case .paste:   return "Paste via ⌘V"
        }
    }
}

enum ProviderKind: String, CaseIterable, Identifiable {
    case appleSpeech
    case localWhisper
    case openAICompatible

    var id: String { rawValue }
    var label: String {
        switch self {
        case .appleSpeech:      return "Apple on-device (macOS 26+)"
        case .localWhisper:     return "Local whisper.cpp (built-in)"
        case .openAICompatible: return "OpenAI-compatible server"
        }
    }
}

/// App-wide configuration, persisted in UserDefaults.
/// NOTE: the API key lives in UserDefaults for now; moving it to the Keychain
/// is tracked as a follow-up.
final class AppSettings {
    static let shared = AppSettings()
    private let d = UserDefaults.standard

    private enum K {
        static let trigger = "trigger"
        static let holdToTalk = "holdToTalk"
        static let insertMethod = "insertMethod"
        static let provider = "provider"
        static let endpoint = "endpoint"
        static let apiKey = "apiKey"
        static let model = "model"
        static let language = "language"
        static let localModelPath = "localModelPath"
    }

    init() {
        d.register(defaults: [
            K.trigger: TriggerKey.rightOption.rawValue,
            K.holdToTalk: true,
            K.insertMethod: InsertMethod.unicode.rawValue,
            K.provider: ProviderKind.appleSpeech.rawValue,
            K.endpoint: "http://127.0.0.1:8080/v1",
            K.apiKey: "",
            K.model: "whisper-1",
            K.language: "",   // empty = auto-detect
        ])
    }

    var trigger: TriggerKey {
        get { TriggerKey(rawValue: d.integer(forKey: K.trigger)) ?? .rightOption }
        set { d.set(newValue.rawValue, forKey: K.trigger) }
    }

    /// true = push-to-talk (record while held); false = press once to toggle.
    var holdToTalk: Bool {
        get { d.bool(forKey: K.holdToTalk) }
        set { d.set(newValue, forKey: K.holdToTalk) }
    }

    var insertMethod: InsertMethod {
        get { InsertMethod(rawValue: d.string(forKey: K.insertMethod) ?? "") ?? .unicode }
        set { d.set(newValue.rawValue, forKey: K.insertMethod) }
    }

    var provider: ProviderKind {
        get { ProviderKind(rawValue: d.string(forKey: K.provider) ?? "") ?? .openAICompatible }
        set { d.set(newValue.rawValue, forKey: K.provider) }
    }

    var endpoint: String {
        get { d.string(forKey: K.endpoint) ?? "" }
        set { d.set(newValue, forKey: K.endpoint) }
    }

    var apiKey: String {
        get { d.string(forKey: K.apiKey) ?? "" }
        set { d.set(newValue, forKey: K.apiKey) }
    }

    var model: String {
        get { d.string(forKey: K.model) ?? "whisper-1" }
        set { d.set(newValue, forKey: K.model) }
    }

    /// ISO-639-1 code or empty for auto-detect.
    var language: String {
        get { d.string(forKey: K.language) ?? "" }
        set { d.set(newValue, forKey: K.language) }
    }

    var localModelPath: String {
        get { d.string(forKey: K.localModelPath) ?? "" }
        set { d.set(newValue, forKey: K.localModelPath) }
    }
}
