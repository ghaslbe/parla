import Foundation

/// Shorthand for a localized string from the app's Localizable.strings tables
/// (en / de). Used for strings that reach the UI as `String` rather than as a
/// SwiftUI `LocalizedStringKey` literal (enum labels, AppKit menu titles, …).
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}
