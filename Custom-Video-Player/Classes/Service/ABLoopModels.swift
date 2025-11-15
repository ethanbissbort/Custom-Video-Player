import Foundation
import AVFoundation

/// Represents a precise time point in a video with frame-level accuracy
public struct TimePoint: Codable, Equatable {
    let hours: Int
    let minutes: Int
    let seconds: Int
    let frames: Int
    let frameRate: Double

    /// Initializes a TimePoint with individual components
    ///
    /// - Parameters:
    ///   - hours: Hours component
    ///   - minutes: Minutes component
    ///   - seconds: Seconds component
    ///   - frames: Frame number (0-based)
    ///   - frameRate: Frame rate of the video (e.g., 29.97, 30, 24, etc.)
    public init(hours: Int = 0, minutes: Int = 0, seconds: Int = 0, frames: Int = 0, frameRate: Double = 30.0) {
        self.hours = hours
        self.minutes = minutes
        self.seconds = seconds
        self.frames = frames
        self.frameRate = frameRate
    }

    /// Initializes a TimePoint from a CMTime
    ///
    /// - Parameters:
    ///   - cmTime: The CMTime to convert
    ///   - frameRate: Frame rate of the video
    public init(from cmTime: CMTime, frameRate: Double = 30.0) {
        let totalSeconds = CMTimeGetSeconds(cmTime)
        let hours = Int(totalSeconds) / 3600
        let minutes = (Int(totalSeconds) % 3600) / 60
        let seconds = Int(totalSeconds) % 60
        let fractionalSeconds = totalSeconds - floor(totalSeconds)
        let frames = Int(fractionalSeconds * frameRate)

        self.hours = hours
        self.minutes = minutes
        self.seconds = seconds
        self.frames = frames
        self.frameRate = frameRate
    }

    /// Converts this TimePoint to a CMTime
    ///
    /// - Returns: CMTime representation
    public func toCMTime() -> CMTime {
        let totalSeconds = Double(hours * 3600 + minutes * 60 + seconds) + (Double(frames) / frameRate)
        return CMTime(seconds: totalSeconds, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
    }

    /// Returns a formatted string representation of the time
    ///
    /// - Returns: String in format "HH:MM:SS:FF"
    public func toString() -> String {
        return String(format: "%02d:%02d:%02d:%02d", hours, minutes, seconds, frames)
    }

    /// Parses a timecode string into a TimePoint
    ///
    /// - Parameters:
    ///   - string: String in format "HH:MM:SS:FF"
    ///   - frameRate: Frame rate of the video
    /// - Returns: TimePoint if parsing succeeds, nil otherwise
    public static func parse(_ string: String, frameRate: Double = 30.0) -> TimePoint? {
        let components = string.split(separator: ":").map { String($0) }
        guard components.count == 4,
              let hours = Int(components[0]),
              let minutes = Int(components[1]),
              let seconds = Int(components[2]),
              let frames = Int(components[3]),
              hours >= 0, minutes >= 0, minutes < 60,
              seconds >= 0, seconds < 60,
              frames >= 0, frames < Int(frameRate) else {
            return nil
        }
        return TimePoint(hours: hours, minutes: minutes, seconds: seconds, frames: frames, frameRate: frameRate)
    }
}

/// Represents a single A-B loop point
public struct ABLoop: Codable, Equatable, Identifiable {
    public let id: UUID
    let pointA: TimePoint
    let pointB: TimePoint
    let name: String?

    /// Initializes an ABLoop
    ///
    /// - Parameters:
    ///   - id: Unique identifier
    ///   - pointA: Start point of the loop
    ///   - pointB: End point of the loop
    ///   - name: Optional name for the loop
    public init(id: UUID = UUID(), pointA: TimePoint, pointB: TimePoint, name: String? = nil) {
        self.id = id
        self.pointA = pointA
        self.pointB = pointB
        self.name = name
    }

    /// Returns the duration of the loop
    ///
    /// - Returns: CMTime representing the duration
    public func duration() -> CMTime {
        let startTime = pointA.toCMTime()
        let endTime = pointB.toCMTime()
        return CMTimeSubtract(endTime, startTime)
    }

    /// Checks if a given time is within this loop
    ///
    /// - Parameter time: CMTime to check
    /// - Returns: true if the time is within the loop bounds
    public func contains(_ time: CMTime) -> Bool {
        let startTime = pointA.toCMTime()
        let endTime = pointB.toCMTime()
        return time >= startTime && time <= endTime
    }
}

/// Represents a segment in a segment playlist
public struct PlaybackSegment: Codable, Equatable, Identifiable {
    public let id: UUID
    let startPoint: TimePoint
    let endPoint: TimePoint
    let order: Int
    let name: String?

    /// Initializes a PlaybackSegment
    ///
    /// - Parameters:
    ///   - id: Unique identifier
    ///   - startPoint: Start point of the segment
    ///   - endPoint: End point of the segment
    ///   - order: Order in the playlist
    ///   - name: Optional name for the segment
    public init(id: UUID = UUID(), startPoint: TimePoint, endPoint: TimePoint, order: Int, name: String? = nil) {
        self.id = id
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.order = order
        self.name = name
    }
}

/// Represents a playlist of segments for sequential playback
public struct SegmentPlaylist: Codable, Equatable, Identifiable {
    public let id: UUID
    let name: String
    var segments: [PlaybackSegment]
    let videoIdentifier: String // URL or unique identifier of the video
    var isLooping: Bool // Whether to loop the entire segment playlist

    /// Initializes a SegmentPlaylist
    ///
    /// - Parameters:
    ///   - id: Unique identifier
    ///   - name: Name of the playlist
    ///   - segments: Array of segments in playback order
    ///   - videoIdentifier: Identifier for the associated video
    ///   - isLooping: Whether to loop the playlist
    public init(id: UUID = UUID(), name: String, segments: [PlaybackSegment], videoIdentifier: String, isLooping: Bool = false) {
        self.id = id
        self.name = name
        self.segments = segments.sorted { $0.order < $1.order }
        self.videoIdentifier = videoIdentifier
        self.isLooping = isLooping
    }

    /// Returns the next segment after the given segment
    ///
    /// - Parameter currentSegment: Current segment
    /// - Returns: Next segment, or nil if at the end (and not looping)
    public func nextSegment(after currentSegment: PlaybackSegment) -> PlaybackSegment? {
        guard let currentIndex = segments.firstIndex(where: { $0.id == currentSegment.id }) else {
            return nil
        }

        let nextIndex = currentIndex + 1
        if nextIndex < segments.count {
            return segments[nextIndex]
        } else if isLooping {
            return segments.first
        }
        return nil
    }

    /// Returns the total duration of all segments
    ///
    /// - Returns: Total duration as CMTime
    public func totalDuration() -> CMTime {
        return segments.reduce(CMTime.zero) { total, segment in
            let segmentDuration = CMTimeSubtract(
                segment.endPoint.toCMTime(),
                segment.startPoint.toCMTime()
            )
            return CMTimeAdd(total, segmentDuration)
        }
    }
}

/// Container for all A-B loops associated with a video
public struct VideoLoopData: Codable {
    let videoIdentifier: String
    var abLoops: [ABLoop]
    var segmentPlaylists: [SegmentPlaylist]

    /// Initializes VideoLoopData
    ///
    /// - Parameters:
    ///   - videoIdentifier: Identifier for the associated video
    ///   - abLoops: Array of A-B loops
    ///   - segmentPlaylists: Array of segment playlists
    public init(videoIdentifier: String, abLoops: [ABLoop] = [], segmentPlaylists: [SegmentPlaylist] = []) {
        self.videoIdentifier = videoIdentifier
        self.abLoops = abLoops
        self.segmentPlaylists = segmentPlaylists
    }
}
