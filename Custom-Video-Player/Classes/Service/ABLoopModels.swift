import Foundation
import AVFoundation

/// Represents a precise time point in a video with frame-level accuracy
public struct TimePoint: Codable, Equatable {
    public let hours: Int
    public let minutes: Int
    public let seconds: Int
    public let frames: Int
    public let frameRate: Double

    /// Initializes a TimePoint with individual components
    ///
    /// - Parameters:
    ///   - hours: Hours component
    ///   - minutes: Minutes component
    ///   - seconds: Seconds component
    ///   - frames: Frame number (0-based)
    ///   - frameRate: Frame rate of the video (e.g., 29.97, 30, 24, etc.)
    public init(hours: Int = 0, minutes: Int = 0, seconds: Int = 0, frames: Int = 0, frameRate: Double = ABLoopConstants.defaultFrameRate) {
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
    public init(from cmTime: CMTime, frameRate: Double = ABLoopConstants.defaultFrameRate) {
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
    public static func parse(_ string: String, frameRate: Double = ABLoopConstants.defaultFrameRate) -> TimePoint? {
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
    public let pointA: TimePoint
    public let pointB: TimePoint
    public let name: String?

    /// Identifier of the video this loop was created for.
    ///
    /// Deliberately optional and defaulted, for two reasons that both have to hold:
    ///
    /// 1. Loops written by earlier versions have no such key in their stored JSON.
    ///    `init(from:)` decodes it with `decodeIfPresent`, so an old archive still loads
    ///    (as `nil`) instead of failing and taking every saved loop down with it.
    /// 2. Every existing `ABLoop(pointA:pointB:name:)` call site keeps compiling, because
    ///    the parameter is last and defaulted.
    ///
    /// `ABLoopManager` uses it to scope `clearLoopData(for:)` to the video being cleared;
    /// see `loopBelongsLocked(_:to:removedData:)` for how loops that predate the property
    /// are attributed.
    public let videoIdentifier: String?

    /// Initializes an ABLoop
    ///
    /// - Parameters:
    ///   - id: Unique identifier
    ///   - pointA: Start point of the loop
    ///   - pointB: End point of the loop
    ///   - name: Optional name for the loop
    ///   - videoIdentifier: Identifier of the video this loop belongs to, when known
    public init(
        id: UUID = UUID(),
        pointA: TimePoint,
        pointB: TimePoint,
        name: String? = nil,
        videoIdentifier: String? = nil
    ) {
        self.id = id
        self.pointA = pointA
        self.pointB = pointB
        self.name = name
        self.videoIdentifier = videoIdentifier
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case pointA
        case pointB
        case name
        case videoIdentifier
    }

    /// Decodes an `ABLoop`, tolerating archives written before `videoIdentifier` existed.
    ///
    /// Written out by hand rather than left to the compiler so the compatibility contract
    /// is explicit: `videoIdentifier` must stay optional-with-fallback here, because the
    /// alternative is a decode failure that quarantines — and therefore hides — every loop
    /// a user has ever saved.
    ///
    /// - Parameter decoder: Decoder to read from
    /// - Throws: `DecodingError` if a required property is missing or malformed
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        pointA = try container.decode(TimePoint.self, forKey: .pointA)
        pointB = try container.decode(TimePoint.self, forKey: .pointB)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        videoIdentifier = try container.decodeIfPresent(String.self, forKey: .videoIdentifier)
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
    public let startPoint: TimePoint
    public let endPoint: TimePoint
    public let order: Int
    public let name: String?

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
    public let name: String
    public var segments: [PlaybackSegment]
    public let videoIdentifier: String // URL or unique identifier of the video
    public var isLooping: Bool // Whether to loop the entire segment playlist

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
    public let videoIdentifier: String
    public var abLoops: [ABLoop]
    public var segmentPlaylists: [SegmentPlaylist]

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
