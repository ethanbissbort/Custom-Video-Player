import AVFoundation
import Foundation

class SubtitleSelectionViewModel {
    // MARK: - Properties

    private let supportedLanguages: [AVMediaSelectionOption]

    private let subtitleOptions: [String]

    var selectedItemIndex: Int = 0

    var subtitleOptionsCount: Int {
        subtitleOptions.count
    }

    /// Returns the subtitle option string at a given index.
    func subtitleOption(_ index: Int) -> String {
        return subtitleOptions[index]
    }

    /// The selected subtitle track.
    var subtitleTrack: AVMediaSelectionOption? {
        selectedItemIndex == 0 ? nil : supportedLanguages[selectedItemIndex - 1]
    }

    // MARK: - Initialization

    /// Initializes the view model with supported subtitle languages.
    ///
    /// - Parameter supportedLanguages: Array of supported subtitle options.
    init(supportedLanguages: [AVMediaSelectionOption]) {
        self.supportedLanguages = supportedLanguages
        let offOption = CVPLocalized(
            "subtitles.off",
            value: "Off",
            comment: "Row that turns subtitles off in the subtitle sheet"
        )
        subtitleOptions = [offOption] + supportedLanguages.map(SubtitleSelectionViewModel.displayTitle(for:))
    }

    // MARK: - Selection

    /// Aligns the sheet's selection with a track that was chosen elsewhere.
    ///
    /// Used when the automatic closed-captioning selection picks a track on the user's behalf: the
    /// sheet must open on the row that is actually playing, not on "Off".
    ///
    /// - Parameter option: The selected track, or `nil` for "Off".
    func selectTrack(_ option: AVMediaSelectionOption?) {
        guard let option = option, let index = supportedLanguages.firstIndex(of: option) else {
            selectedItemIndex = 0
            return
        }
        // Index 0 is the "Off" row, so every track sits one position further down.
        selectedItemIndex = index + 1
    }

    // MARK: - Helpers

    /// Builds the row title for a subtitle track.
    ///
    /// Two accessibility decisions live here:
    /// * The display name is resolved against `Locale.current` rather than a hardcoded `en-EN`, so
    ///   a French user reads "Anglais" instead of "English".
    /// * Tracks that carry subtitles for the deaf and hard of hearing are suffixed with "(SDH)".
    ///   `AVPlayer.supportedSubtitleOptions` filters on `extendedLanguageTag` alone, which makes an
    ///   SDH track and a plain subtitle track for the same language indistinguishable — exactly the
    ///   two rows a user who needs SDH has to tell apart.
    ///
    /// - Parameter option: The track to describe.
    /// - Returns: The row title.
    private static func displayTitle(for option: AVMediaSelectionOption) -> String {
        let displayName = option.displayName(with: Locale.current)
        guard option.hasMediaCharacteristic(.describesMusicAndSoundForAccessibility) else {
            return displayName
        }
        return String(
            format: CVPLocalized(
                "subtitles.sdh",
                value: "%@ (SDH)",
                comment: "Subtitle row for a track carrying subtitles for the deaf and hard of hearing"
            ),
            displayName
        )
    }
}
