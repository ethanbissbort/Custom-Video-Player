import Foundation
import CoreGraphics

/// Constants for A-B Loop functionality
public enum ABLoopConstants {
    // MARK: - Default Values

    /// Default frame rate when video frame rate cannot be determined.
    /// `public` because it is used as the default argument value for public
    /// `TimePoint` initializers, and Swift requires such defaults to be at least
    /// as accessible as the API that exposes them.
    public static let defaultFrameRate: Double = 30.0

    /// Maximum frames per second (used for validation)
    static let maxFrameRate: Double = 120.0

    // MARK: - Storage Keys

    /// UserDefaults key for storing loop data
    static let storageKey = "com.customvideoplayer.abloops"

    // MARK: - UI Constants

    enum UI {
        /// Container view width for AB loop dialog
        static let containerWidth: CGFloat = 600

        /// Container view height for AB loop list
        static let containerHeight: CGFloat = 500

        /// Creation dialog width
        static let creationDialogWidth: CGFloat = 500

        /// Segment playlist creation dialog width
        ///
        /// Wider than `creationDialogWidth` because the start and end timecode inputs sit
        /// side by side to leave vertical room for the segment list.
        static let segmentPlaylistDialogWidth: CGFloat = 600

        /// Segment playlist creation dialog height
        static let segmentPlaylistDialogHeight: CGFloat = 640

        /// Table view cell height
        static let cellHeight: CGFloat = 60

        /// Active indicator size
        static let activeIndicatorSize: CGFloat = 8

        /// Button height
        static let buttonHeight: CGFloat = 44

        /// Small button height
        static let smallButtonHeight: CGFloat = 36

        /// Timecode input field width
        static let timecodeFieldWidth: CGFloat = 50

        /// Timecode input field height
        static let timecodeFieldHeight: CGFloat = 40

        /// Corner radius for buttons and inputs
        static let cornerRadius: CGFloat = 8

        /// Small corner radius
        static let smallCornerRadius: CGFloat = 4
    }

    // MARK: - Validation

    enum Validation {
        /// Maximum hours value
        static let maxHours = 23

        /// Maximum minutes value
        static let maxMinutes = 59

        /// Maximum seconds value
        static let maxSeconds = 59

        /// Maximum timecode input length
        static let maxInputLength = 2
    }

    // MARK: - Strings

    enum Strings {
        // Titles
        static let abLoopTitle = "A-B Loop & Segments"
        static let createLoopTitle = "Create A-B Loop"
        static let createSegmentPlaylistTitle = "Create Segment Playlist"

        // Buttons
        static let createNewLoop = "+ Create New A-B Loop"
        static let createSegmentPlaylist = "+ Create Segment Playlist"
        static let stopLoop = "Stop Loop"
        static let cancel = "Cancel"
        static let createLoop = "Create Loop"
        static let setToCurrentTime = "Set to Current Time"
        static let addSegment = "+ Add Segment"
        static let savePlaylist = "Save Playlist"
        static let okAction = "OK"

        // Labels
        static let loopNameLabel = "Loop Name (optional)"
        static let loopNamePlaceholder = "Enter loop name"
        static let pointALabel = "Point A (Start)"
        static let pointBLabel = "Point B (End)"
        static let timecodeFormat = "HH:MM:SS:FF"
        static let playlistNameLabel = "Playlist Name (optional)"
        static let playlistNamePlaceholder = "Enter playlist name"
        static let loopPlaylistLabel = "Loop Playlist"
        static let segmentStartLabel = "Segment Start"
        static let segmentEndLabel = "Segment End"
        static let segmentsHeader = "Segments"
        static let noSegmentsYet = "No segments yet — add one above."

        // Segments
        static let abLoopsSegment = "A-B Loops"
        static let segmentPlaylistsSegment = "Segment Playlists"

        // Errors
        static let invalidInputTitle = "Invalid Input"
        static let invalidInputMessage = "Please enter valid timecodes for both Point A and Point B."
        static let invalidRangeTitle = "Invalid Range"
        static let invalidRangeMessage = "Point B must be after Point A."
        static let invalidSegmentMessage = "Please enter valid timecodes for both the segment start and end."
        static let invalidPlaylistTitle = "Invalid Playlist"
        static let emptyPlaylistMessage = "Add at least one segment before saving the playlist."
        static let durationExceededTitle = "Beyond Video End"
        static let durationExceededMessage = "That time point is past the end of the video."

        // Defaults
        static let defaultLoopName = "A-B Loop"
        static let defaultPlaylistName = "Segment Playlist"

        /// Display name for a segment, formatted with its 1-based position.
        static let segmentNameFormat = "Segment %d"
    }

    // MARK: - Animation

    enum Animation {
        /// Standard animation duration
        static let duration: TimeInterval = 0.3

        /// Quick animation duration
        static let quickDuration: TimeInterval = 0.25

        /// Keyboard animation offset divisor
        static let keyboardOffsetDivisor: CGFloat = 4
    }
}
