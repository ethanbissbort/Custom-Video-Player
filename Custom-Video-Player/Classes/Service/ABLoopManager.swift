import Foundation
import AVFoundation

/// Delegate protocol for A-B loop events
public protocol ABLoopManagerDelegate: AnyObject {
    func abLoopDidReachEnd(_ loop: ABLoop)
    func segmentPlaylistDidFinishSegment(_ segment: PlaybackSegment)
    func segmentPlaylistDidComplete(_ playlist: SegmentPlaylist)
}

/// Manages A-B loop functionality and segment playlists
public class ABLoopManager {
    // MARK: - Properties

    weak var delegate: ABLoopManagerDelegate?

    private var videoLoopData: [String: VideoLoopData] = [:]
    private var currentActiveLoop: ABLoop?
    private var currentSegmentPlaylist: SegmentPlaylist?
    private var currentSegment: PlaybackSegment?

    private let userDefaults = UserDefaults.standard
    private let storageKey = "com.customvideoplayer.abloops"

    /// Serial queue for thread-safe state management
    private let stateQueue = DispatchQueue(label: "com.customvideoplayer.abloop.state")

    // MARK: - Initialization

    public init() {
        loadAllLoopData()
    }

    // MARK: - A-B Loop Management

    /// Sets the currently active A-B loop (thread-safe)
    ///
    /// - Parameter loop: The loop to activate, or nil to deactivate
    public func setActiveLoop(_ loop: ABLoop?) {
        stateQueue.async { [weak self] in
            self?.currentActiveLoop = loop
            self?.currentSegmentPlaylist = nil
            self?.currentSegment = nil
        }
    }

    /// Returns the currently active A-B loop (thread-safe)
    ///
    /// - Returns: The active loop, or nil if none is active
    public func getActiveLoop() -> ABLoop? {
        return stateQueue.sync {
            return currentActiveLoop
        }
    }

    /// Checks if playback should loop based on current time (thread-safe)
    ///
    /// - Parameter currentTime: Current playback time
    /// - Returns: CMTime to seek to, or nil if no loop should occur
    public func shouldLoop(at currentTime: CMTime) -> CMTime? {
        return stateQueue.sync {
            if let activeLoop = currentActiveLoop {
                let endTime = activeLoop.pointB.toCMTime()
                // Check if we've reached or passed the end point
                if currentTime >= endTime {
                    DispatchQueue.main.async { [weak self] in
                        self?.delegate?.abLoopDidReachEnd(activeLoop)
                    }
                    return activeLoop.pointA.toCMTime()
                }
            }
            return nil
        }
    }

    /// Adds a new A-B loop for a video
    ///
    /// - Parameters:
    ///   - loop: The A-B loop to add
    ///   - videoIdentifier: Identifier for the video
    public func addABLoop(_ loop: ABLoop, for videoIdentifier: String) {
        if videoLoopData[videoIdentifier] == nil {
            videoLoopData[videoIdentifier] = VideoLoopData(videoIdentifier: videoIdentifier)
        }
        videoLoopData[videoIdentifier]?.abLoops.append(loop)
        saveLoopData()
    }

    /// Removes an A-B loop
    ///
    /// - Parameters:
    ///   - loopId: ID of the loop to remove
    ///   - videoIdentifier: Identifier for the video
    public func removeABLoop(withId loopId: UUID, for videoIdentifier: String) {
        videoLoopData[videoIdentifier]?.abLoops.removeAll { $0.id == loopId }
        if currentActiveLoop?.id == loopId {
            currentActiveLoop = nil
        }
        saveLoopData()
    }

    /// Gets all A-B loops for a video
    ///
    /// - Parameter videoIdentifier: Identifier for the video
    /// - Returns: Array of A-B loops
    public func getABLoops(for videoIdentifier: String) -> [ABLoop] {
        return videoLoopData[videoIdentifier]?.abLoops ?? []
    }

    // MARK: - Segment Playlist Management

    /// Sets the currently active segment playlist (thread-safe)
    ///
    /// - Parameter playlist: The playlist to activate, or nil to deactivate
    public func setActiveSegmentPlaylist(_ playlist: SegmentPlaylist?) {
        stateQueue.async { [weak self] in
            self?.currentSegmentPlaylist = playlist
            self?.currentActiveLoop = nil
            if let playlist = playlist {
                self?.currentSegment = playlist.segments.first
            } else {
                self?.currentSegment = nil
            }
        }
    }

    /// Returns the currently active segment playlist (thread-safe)
    ///
    /// - Returns: The active playlist, or nil if none is active
    public func getActiveSegmentPlaylist() -> SegmentPlaylist? {
        return stateQueue.sync {
            return currentSegmentPlaylist
        }
    }

    /// Returns the current segment being played (thread-safe)
    ///
    /// - Returns: The current segment, or nil if none is active
    public func getCurrentSegment() -> PlaybackSegment? {
        return stateQueue.sync {
            return currentSegment
        }
    }

    /// Checks if playback should advance to next segment (thread-safe)
    ///
    /// - Parameter currentTime: Current playback time
    /// - Returns: CMTime to seek to for next segment, or nil if no transition needed
    public func shouldAdvanceSegment(at currentTime: CMTime) -> CMTime? {
        return stateQueue.sync {
            guard let playlist = currentSegmentPlaylist,
                  let segment = currentSegment else {
                return nil
            }

            let endTime = segment.endPoint.toCMTime()
            // Check if we've reached or passed the end point of current segment
            if currentTime >= endTime {
                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.segmentPlaylistDidFinishSegment(segment)
                }

                if let nextSegment = playlist.nextSegment(after: segment) {
                    currentSegment = nextSegment
                    return nextSegment.startPoint.toCMTime()
                } else {
                    // Playlist finished
                    DispatchQueue.main.async { [weak self] in
                        self?.delegate?.segmentPlaylistDidComplete(playlist)
                    }
                    if playlist.isLooping {
                        currentSegment = playlist.segments.first
                        return playlist.segments.first?.startPoint.toCMTime()
                    } else {
                        currentSegmentPlaylist = nil
                        currentSegment = nil
                    }
                }
            }
            return nil
        }
    }

    /// Adds a new segment playlist for a video
    ///
    /// - Parameters:
    ///   - playlist: The segment playlist to add
    ///   - videoIdentifier: Identifier for the video
    public func addSegmentPlaylist(_ playlist: SegmentPlaylist, for videoIdentifier: String) {
        if videoLoopData[videoIdentifier] == nil {
            videoLoopData[videoIdentifier] = VideoLoopData(videoIdentifier: videoIdentifier)
        }
        videoLoopData[videoIdentifier]?.segmentPlaylists.append(playlist)
        saveLoopData()
    }

    /// Removes a segment playlist
    ///
    /// - Parameters:
    ///   - playlistId: ID of the playlist to remove
    ///   - videoIdentifier: Identifier for the video
    public func removeSegmentPlaylist(withId playlistId: UUID, for videoIdentifier: String) {
        videoLoopData[videoIdentifier]?.segmentPlaylists.removeAll { $0.id == playlistId }
        if currentSegmentPlaylist?.id == playlistId {
            currentSegmentPlaylist = nil
            currentSegment = nil
        }
        saveLoopData()
    }

    /// Gets all segment playlists for a video
    ///
    /// - Parameter videoIdentifier: Identifier for the video
    /// - Returns: Array of segment playlists
    public func getSegmentPlaylists(for videoIdentifier: String) -> [SegmentPlaylist] {
        return videoLoopData[videoIdentifier]?.segmentPlaylists ?? []
    }

    /// Updates an existing segment playlist
    ///
    /// - Parameters:
    ///   - playlist: The updated playlist
    ///   - videoIdentifier: Identifier for the video
    public func updateSegmentPlaylist(_ playlist: SegmentPlaylist, for videoIdentifier: String) {
        if let index = videoLoopData[videoIdentifier]?.segmentPlaylists.firstIndex(where: { $0.id == playlist.id }) {
            videoLoopData[videoIdentifier]?.segmentPlaylists[index] = playlist
            if currentSegmentPlaylist?.id == playlist.id {
                currentSegmentPlaylist = playlist
            }
            saveLoopData()
        }
    }

    // MARK: - Persistence

    /// Saves all loop data to UserDefaults
    private func saveLoopData() {
        let encoder = JSONEncoder()
        do {
            let encoded = try encoder.encode(Array(videoLoopData.values))
            userDefaults.set(encoded, forKey: storageKey)
        } catch {
            print("Failed to save loop data: \(error)")
        }
    }

    /// Loads all loop data from UserDefaults
    private func loadAllLoopData() {
        guard let data = userDefaults.data(forKey: storageKey) else {
            return
        }

        let decoder = JSONDecoder()
        do {
            let loopDataArray = try decoder.decode([VideoLoopData].self, from: data)
            videoLoopData = Dictionary(uniqueKeysWithValues: loopDataArray.map { ($0.videoIdentifier, $0) })
        } catch {
            print("Failed to load loop data: \(error)")
        }
    }

    /// Clears all loop data for a specific video
    ///
    /// - Parameter videoIdentifier: Identifier for the video
    public func clearLoopData(for videoIdentifier: String) {
        videoLoopData.removeValue(forKey: videoIdentifier)
        if currentActiveLoop != nil || currentSegmentPlaylist?.videoIdentifier == videoIdentifier {
            currentActiveLoop = nil
            currentSegmentPlaylist = nil
            currentSegment = nil
        }
        saveLoopData()
    }

    /// Clears all loop data
    public func clearAllLoopData() {
        videoLoopData.removeAll()
        currentActiveLoop = nil
        currentSegmentPlaylist = nil
        currentSegment = nil
        userDefaults.removeObject(forKey: storageKey)
    }
}
