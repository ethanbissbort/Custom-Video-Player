import Foundation
import AVFoundation

/// Error types for A-B loop operations
enum ABLoopError: LocalizedError {
    case invalidTimecode(String)
    case invalidRange(String)
    case invalidFrameRate(Double)
    case invalidDuration
    case persistenceError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidTimecode(let message):
            return message
        case .invalidRange(let message):
            return message
        case .invalidFrameRate(let rate):
            return "Invalid frame rate: \(rate). Frame rate must be between 1 and \(ABLoopConstants.maxFrameRate)."
        case .invalidDuration:
            return "Invalid duration. End time must be after start time."
        case .persistenceError(let error):
            return "Failed to save data: \(error.localizedDescription)"
        }
    }
}

/// Result type for validation operations
enum ValidationResult {
    case success
    case failure(String)

    var isValid: Bool {
        if case .success = self {
            return true
        }
        return false
    }

    var errorMessage: String? {
        if case .failure(let message) = self {
            return message
        }
        return nil
    }
}

/// Utility class for validating A-B loop inputs
enum ABLoopValidation {
    // MARK: - Timecode Validation

    /// Validates a timecode string format
    ///
    /// - Parameter timecode: String in format "HH:MM:SS:FF"
    /// - Returns: ValidationResult indicating success or failure
    static func validateTimecodeFormat(_ timecode: String) -> ValidationResult {
        let components = timecode.split(separator: ":").map { String($0) }

        guard components.count == 4 else {
            return .failure("Timecode must have 4 components (HH:MM:SS:FF)")
        }

        guard components.allSatisfy({ $0.count <= ABLoopConstants.Validation.maxInputLength }) else {
            return .failure("Each timecode component must be at most 2 digits")
        }

        return .success
    }

    /// Validates individual timecode components
    ///
    /// - Parameters:
    ///   - hours: Hours value
    ///   - minutes: Minutes value
    ///   - seconds: Seconds value
    ///   - frames: Frames value
    ///   - frameRate: Video frame rate
    /// - Returns: ValidationResult indicating success or failure
    static func validateTimecodeComponents(
        hours: Int,
        minutes: Int,
        seconds: Int,
        frames: Int,
        frameRate: Double
    ) -> ValidationResult {
        guard hours >= 0 else {
            return .failure("Hours must be non-negative")
        }

        guard minutes >= 0, minutes < 60 else {
            return .failure("Minutes must be between 0 and 59")
        }

        guard seconds >= 0, seconds < 60 else {
            return .failure("Seconds must be between 0 and 59")
        }

        guard frames >= 0, frames < Int(frameRate) else {
            return .failure("Frames must be between 0 and \(Int(frameRate) - 1)")
        }

        return .success
    }

    // MARK: - Frame Rate Validation

    /// Validates a frame rate value
    ///
    /// - Parameter frameRate: Frame rate to validate
    /// - Returns: ValidationResult indicating success or failure
    static func validateFrameRate(_ frameRate: Double) -> ValidationResult {
        guard frameRate > 0, frameRate <= ABLoopConstants.maxFrameRate else {
            return .failure("Frame rate must be between 1 and \(ABLoopConstants.maxFrameRate)")
        }
        return .success
    }

    // MARK: - Loop Validation

    /// Validates that point B is after point A
    ///
    /// - Parameters:
    ///   - pointA: Start point
    ///   - pointB: End point
    /// - Returns: ValidationResult indicating success or failure
    static func validateLoopRange(pointA: TimePoint, pointB: TimePoint) -> ValidationResult {
        let timeA = pointA.toCMTime()
        let timeB = pointB.toCMTime()

        guard timeB > timeA else {
            return .failure(ABLoopConstants.Strings.invalidRangeMessage)
        }

        return .success
    }

    /// Validates that a time point is within video duration
    ///
    /// - Parameters:
    ///   - timePoint: Time point to validate
    ///   - duration: Video duration
    /// - Returns: ValidationResult indicating success or failure
    static func validateTimePointWithinDuration(
        _ timePoint: TimePoint,
        duration: CMTime
    ) -> ValidationResult {
        let time = timePoint.toCMTime()

        guard time <= duration else {
            return .failure("Time point exceeds video duration")
        }

        return .success
    }

    // MARK: - Segment Playlist Validation

    /// Validates a segment playlist
    ///
    /// - Parameter playlist: Segment playlist to validate
    /// - Returns: ValidationResult indicating success or failure
    static func validateSegmentPlaylist(_ playlist: SegmentPlaylist) -> ValidationResult {
        guard !playlist.segments.isEmpty else {
            return .failure("Segment playlist must contain at least one segment")
        }

        // Validate each segment
        for segment in playlist.segments {
            let result = validateLoopRange(pointA: segment.startPoint, pointB: segment.endPoint)
            if case .failure(let message) = result {
                return .failure("Invalid segment: \(message)")
            }
        }

        // Validate segment ordering
        let sortedSegments = playlist.segments.sorted { $0.order < $1.order }
        for (index, segment) in sortedSegments.enumerated() {
            guard segment.order == index else {
                return .failure("Segment ordering is invalid")
            }
        }

        return .success
    }

    // MARK: - Input Sanitization

    /// Sanitizes a timecode input string
    ///
    /// - Parameter input: Raw input string
    /// - Returns: Sanitized string containing only valid characters
    static func sanitizeTimecodeInput(_ input: String) -> String {
        let allowedCharacters = CharacterSet(charactersIn: "0123456789:")
        return input.components(separatedBy: allowedCharacters.inverted).joined()
    }

    /// Pads a timecode component with leading zeros
    ///
    /// - Parameter component: Component string to pad
    /// - Returns: Padded string (2 digits)
    static func padTimecodeComponent(_ component: String) -> String {
        guard !component.isEmpty else { return "00" }
        if component.count == 1 {
            return "0" + component
        }
        return component
    }
}
