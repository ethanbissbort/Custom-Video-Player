import Foundation

/// Returns a localized string from the library's own resource bundle.
///
/// `NSLocalizedString` defaults to `Bundle.main`, which is the *host app's* bundle — a library's
/// strings live in its resource bundle instead, so every lookup has to name that bundle
/// explicitly. `CustomVideoPlayer.resourceBundle` resolves it for both distribution channels
/// (`Bundle.module` under SwiftPM, the `ResourcesBundle` under CocoaPods).
///
/// - Parameters:
///   - key: The key in `Localizable.strings`.
///   - value: The English text to fall back to when the key is missing. Keeping the English copy
///     at the call site means an untranslated build still shows real words rather than a raw key.
///   - comment: Translator-facing context.
/// - Returns: The localized string.
func CVPLocalized(_ key: String, value: String, comment: String = "") -> String {
    NSLocalizedString(
        key,
        tableName: nil,
        bundle: CustomVideoPlayer.resourceBundle,
        value: value,
        comment: comment
    )
}
