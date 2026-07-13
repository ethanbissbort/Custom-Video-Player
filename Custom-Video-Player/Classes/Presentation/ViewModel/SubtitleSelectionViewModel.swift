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
        subtitleOptions = ["Off"] + supportedLanguages.map {
            $0.displayName(with: Locale(identifier: "en-EN"))
        }
    }
}
