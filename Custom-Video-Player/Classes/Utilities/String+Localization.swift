import Foundation

/// Localization lookup for strings shipped inside the library's resource bundle.
///
/// `NSLocalizedString` defaults to `Bundle.main`, which is the *host app's* bundle — a library's
/// own strings live in its resource bundle instead, so every lookup has to name that bundle
/// explicitly. `CustomVideoPlayer.resourceBundle` resolves it for both distribution channels
/// (`Bundle.module` under SwiftPM, the `ResourcesBundle` under CocoaPods).
enum LocalizedString {

    /// Returns the localized string for `key`, falling back to `value` when no translation exists.
    ///
    /// - Parameters:
    ///   - key: The key in `Localizable.strings`.
    ///   - value: The English text to use when the key is missing. Keeping the English copy at the
    ///     call site means an untranslated build still shows real words rather than a raw key.
    ///   - comment: Translator-facing context.
    /// - Returns: The localized string.
    static func callAsFunction(_ key: String, value: String, comment: String) -> String {
        NSLocalizedString(
            key,
            tableName: nil,
            bundle: CustomVideoPlayer.resourceBundle,
            value: value,
            comment: comment
        )
    }
}

/// Shorthand so call sites read close to `NSLocalizedString`.
///
/// - Parameters:
///   - key: The key in `Localizable.strings`.
///   - value: The English fallback text.
///   - comment: Translator-facing context.
/// - Returns: The localized string.
func CVPLocalized(_ key: String, value: String, comment: String = "") -> String {
    LocalizedString(key, value: value, comment: comment)
}
