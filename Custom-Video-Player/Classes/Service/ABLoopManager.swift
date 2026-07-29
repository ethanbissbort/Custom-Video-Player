import Foundation
import AVFoundation
import os

/// Delegate protocol for A-B loop events
public protocol ABLoopManagerDelegate: AnyObject {
    func abLoopDidReachEnd(_ loop: ABLoop)
    func segmentPlaylistDidFinishSegment(_ segment: PlaybackSegment)
    func segmentPlaylistDidComplete(_ playlist: SegmentPlaylist)
}

/// Manages A-B loop functionality and segment playlists
///
/// ## Thread safety
///
/// Every public method is safe to call from any queue. *All* mutable state is owned by
/// a single serial queue, `stateQueue`: the persisted `videoLoopData` dictionary as well
/// as the activation state (`currentActiveLoop`, `currentSegmentPlaylist`,
/// `currentSegment`). There is deliberately only one queue — a second lock would create
/// a lock-ordering hazard, because several operations have to update the stored data and
/// the activation state as one atomic step (removing a loop that happens to be active,
/// for example).
///
/// Two rules keep the queue re-entrancy-safe, and both must be preserved by future edits:
///
/// 1. A public method takes the queue exactly once, in a single `stateQueue.sync`/`async`
///    block. It must never call another public method, and never nest `stateQueue.sync`
///    inside a block already running on `stateQueue` — that deadlocks immediately.
/// 2. Private helpers whose name ends in `Locked` assume they are *already* running on
///    `stateQueue`; they never take the queue themselves.
///
/// The queue never blocks on another queue, so there is no inversion: delegate callbacks
/// are always delivered with `DispatchQueue.main.async`, never synchronously.
public class ABLoopManager {
    // MARK: - Properties

    weak var delegate: ABLoopManagerDelegate?

    /// All persisted loop data, keyed by video identifier.
    ///
    /// - Important: Guarded by `stateQueue`. Never touch it outside a queue block.
    private var videoLoopData: [String: VideoLoopData] = [:]
    private var currentActiveLoop: ABLoop?
    private var currentSegmentPlaylist: SegmentPlaylist?
    private var currentSegment: PlaybackSegment?

    private let userDefaults = UserDefaults.standard
    private let storageKey = ABLoopConstants.storageKey

    /// Key under which a stored blob that failed to decode is quarantined.
    ///
    /// See `loadAllLoopDataLocked()` for the recovery policy. Not private so tests can
    /// assert that the policy holds.
    static let corruptedStorageKey = ABLoopConstants.storageKey + ".corrupted"

    /// `true` when the last load found a stored blob it could not decode.
    ///
    /// While set, `saveLoopDataLocked()` refuses to overwrite storage with an empty
    /// dictionary, so an unreadable-but-present blob is never replaced by "no loops".
    ///
    /// - Important: Guarded by `stateQueue`.
    private var hasUnreadableStoredData = false

    /// Libraries must not print to the host app's console; diagnostics go to the
    /// unified log instead.
    private let logger = Logger(subsystem: "com.customvideoplayer", category: "ABLoopManager")

    /// Serial queue for thread-safe state management
    private let stateQueue = DispatchQueue(label: "com.customvideoplayer.abloop.state")

    // MARK: - Initialization

    public init() {
        // `init` cannot already be executing on `stateQueue` (nothing else holds a
        // reference to `self` yet), so this synchronous hop is safe and gives the load
        // a well-defined happens-before edge with every later access.
        stateQueue.sync {
            loadAllLoopDataLocked()
        }
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

    /// Adds a new A-B loop for a video (thread-safe)
    ///
    /// - Parameters:
    ///   - loop: The A-B loop to add
    ///   - videoIdentifier: Identifier for the video
    public func addABLoop(_ loop: ABLoop, for videoIdentifier: String) {
        stateQueue.sync {
            var data = videoLoopData[videoIdentifier] ?? VideoLoopData(videoIdentifier: videoIdentifier)
            data.abLoops.append(loop)
            videoLoopData[videoIdentifier] = data
            saveLoopDataLocked()
        }
    }

    /// Removes an A-B loop (thread-safe)
    ///
    /// Removing the loop and deactivating it happen in one queue block so the stored
    /// data and the activation state can never be observed disagreeing.
    ///
    /// - Parameters:
    ///   - loopId: ID of the loop to remove
    ///   - videoIdentifier: Identifier for the video
    public func removeABLoop(withId loopId: UUID, for videoIdentifier: String) {
        stateQueue.sync {
            videoLoopData[videoIdentifier]?.abLoops.removeAll { $0.id == loopId }
            if currentActiveLoop?.id == loopId {
                currentActiveLoop = nil
            }
            saveLoopDataLocked()
        }
    }

    /// Gets all A-B loops for a video (thread-safe)
    ///
    /// - Parameter videoIdentifier: Identifier for the video
    /// - Returns: Array of A-B loops
    public func getABLoops(for videoIdentifier: String) -> [ABLoop] {
        return stateQueue.sync {
            return videoLoopData[videoIdentifier]?.abLoops ?? []
        }
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

    /// Adds a new segment playlist for a video (thread-safe)
    ///
    /// - Parameters:
    ///   - playlist: The segment playlist to add
    ///   - videoIdentifier: Identifier for the video
    public func addSegmentPlaylist(_ playlist: SegmentPlaylist, for videoIdentifier: String) {
        stateQueue.sync {
            var data = videoLoopData[videoIdentifier] ?? VideoLoopData(videoIdentifier: videoIdentifier)
            data.segmentPlaylists.append(playlist)
            videoLoopData[videoIdentifier] = data
            saveLoopDataLocked()
        }
    }

    /// Removes a segment playlist (thread-safe)
    ///
    /// - Parameters:
    ///   - playlistId: ID of the playlist to remove
    ///   - videoIdentifier: Identifier for the video
    public func removeSegmentPlaylist(withId playlistId: UUID, for videoIdentifier: String) {
        stateQueue.sync {
            videoLoopData[videoIdentifier]?.segmentPlaylists.removeAll { $0.id == playlistId }
            if currentSegmentPlaylist?.id == playlistId {
                currentSegmentPlaylist = nil
                currentSegment = nil
            }
            saveLoopDataLocked()
        }
    }

    /// Gets all segment playlists for a video (thread-safe)
    ///
    /// - Parameter videoIdentifier: Identifier for the video
    /// - Returns: Array of segment playlists
    public func getSegmentPlaylists(for videoIdentifier: String) -> [SegmentPlaylist] {
        return stateQueue.sync {
            return videoLoopData[videoIdentifier]?.segmentPlaylists ?? []
        }
    }

    /// Updates an existing segment playlist (thread-safe)
    ///
    /// - Parameters:
    ///   - playlist: The updated playlist
    ///   - videoIdentifier: Identifier for the video
    public func updateSegmentPlaylist(_ playlist: SegmentPlaylist, for videoIdentifier: String) {
        stateQueue.sync {
            guard let index = videoLoopData[videoIdentifier]?
                .segmentPlaylists
                .firstIndex(where: { $0.id == playlist.id }) else {
                return
            }

            videoLoopData[videoIdentifier]?.segmentPlaylists[index] = playlist
            if currentSegmentPlaylist?.id == playlist.id {
                currentSegmentPlaylist = playlist
            }
            saveLoopDataLocked()
        }
    }

    // MARK: - Persistence

    /// Saves all loop data to UserDefaults.
    ///
    /// - Important: Must be called from inside a `stateQueue` block. It never takes the
    ///   queue itself, because every caller already holds it.
    private func saveLoopDataLocked() {
        // Non-destructive policy: when the last load could not decode what is in storage,
        // that blob is still the user's only in-place copy of their loops. Writing an
        // empty array over it would turn a recoverable decode failure into permanent
        // data loss, so the write is skipped until there is actually something to store.
        // (A copy is also quarantined under `corruptedStorageKey`; see
        // `loadAllLoopDataLocked()`.)
        if videoLoopData.isEmpty && hasUnreadableStoredData {
            logger.notice("Skipped save: refusing to overwrite unreadable stored loop data with an empty set.")
            return
        }

        let encoder = JSONEncoder()
        do {
            let encoded = try encoder.encode(Array(videoLoopData.values))
            userDefaults.set(encoded, forKey: storageKey)
            // Storage now holds something we wrote, so it is readable by definition.
            hasUnreadableStoredData = false
        } catch {
            logger.error("Failed to save A-B loop data: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Loads all loop data from UserDefaults.
    ///
    /// - Important: Must be called from inside a `stateQueue` block.
    private func loadAllLoopDataLocked() {
        guard let data = userDefaults.data(forKey: storageKey) else {
            return
        }

        let decoder = JSONDecoder()
        do {
            let loopDataArray = try decoder.decode([VideoLoopData].self, from: data)
            // `Dictionary(uniqueKeysWithValues:)` traps on a duplicate key, which would
            // crash the host app during player construction over nothing worse than a
            // corrupt or hand-edited defaults blob. Collapse duplicates instead, keeping
            // whichever entry carries more data so the merge loses the least; ties keep
            // the earlier entry, so the outcome is deterministic.
            let keyedEntries: [(String, VideoLoopData)] = loopDataArray.map { ($0.videoIdentifier, $0) }
            videoLoopData = Dictionary(keyedEntries) { (existing: VideoLoopData, duplicate: VideoLoopData) -> VideoLoopData in
                let existingCount = existing.abLoops.count + existing.segmentPlaylists.count
                let duplicateCount = duplicate.abLoops.count + duplicate.segmentPlaylists.count
                return duplicateCount > existingCount ? duplicate : existing
            }
            hasUnreadableStoredData = false
        } catch {
            // Decode-failure policy: never destroy data we cannot read.
            //
            // 1. The undecodable blob is quarantined under `corruptedStorageKey` so a
            //    future schema migration can still recover it. It is only written if
            //    nothing is quarantined yet, so the oldest — and therefore most likely
            //    intact — copy wins rather than being overwritten by later garbage.
            // 2. `hasUnreadableStoredData` stops the next mutation from saving an empty
            //    dictionary over the original blob (see `saveLoopDataLocked()`).
            // 3. In-memory state stays empty: the manager reports "no loops" rather than
            //    guessing at partially decoded contents.
            hasUnreadableStoredData = true
            if userDefaults.data(forKey: Self.corruptedStorageKey) == nil {
                userDefaults.set(data, forKey: Self.corruptedStorageKey)
            }
            logger.error(
                "Failed to load A-B loop data; quarantined \(data.count, privacy: .public) bytes for recovery: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Clears all loop data for a specific video (thread-safe)
    ///
    /// Only the activation state belonging to `videoIdentifier` is torn down. The clear
    /// used to deactivate *any* non-nil `currentActiveLoop`, so wiping video A's saved
    /// loops silently killed a loop the user had running on video B.
    ///
    /// - Parameter videoIdentifier: Identifier for the video
    public func clearLoopData(for videoIdentifier: String) {
        stateQueue.sync {
            let removedData = videoLoopData.removeValue(forKey: videoIdentifier)

            if let activeLoop = currentActiveLoop,
               loopBelongsLocked(activeLoop, to: videoIdentifier, removedData: removedData) {
                currentActiveLoop = nil
            }

            if currentSegmentPlaylist?.videoIdentifier == videoIdentifier {
                currentSegmentPlaylist = nil
                currentSegment = nil
            }

            saveLoopDataLocked()
        }
    }

    /// Decides whether a loop belongs to the video being cleared.
    ///
    /// A loop created since `ABLoop.videoIdentifier` exists answers for itself. One
    /// restored from an older archive carries no owner, so it is attributed to the video
    /// whose stored bucket it was just removed from — which is the only place it could
    /// have been reached from. A loop that matches neither is left alone, because
    /// deactivating it is exactly the over-clearing this method exists to avoid.
    ///
    /// - Important: Must be called from inside a `stateQueue` block.
    ///
    /// - Parameters:
    ///   - loop: The currently active loop
    ///   - videoIdentifier: Identifier of the video being cleared
    ///   - removedData: The stored data just removed for that video, if any
    /// - Returns: true when the loop belongs to the cleared video
    private func loopBelongsLocked(
        _ loop: ABLoop,
        to videoIdentifier: String,
        removedData: VideoLoopData?
    ) -> Bool {
        if let owner = loop.videoIdentifier {
            return owner == videoIdentifier
        }

        guard let removedLoops = removedData?.abLoops else {
            return false
        }
        return removedLoops.contains { $0.id == loop.id }
    }

    /// Clears all loop data (thread-safe)
    public func clearAllLoopData() {
        stateQueue.sync {
            videoLoopData.removeAll()
            currentActiveLoop = nil
            currentSegmentPlaylist = nil
            currentSegment = nil
            userDefaults.removeObject(forKey: storageKey)
            // An explicit wipe is the one case where discarding a quarantined blob is
            // exactly what the caller asked for.
            userDefaults.removeObject(forKey: Self.corruptedStorageKey)
            hasUnreadableStoredData = false
        }
    }
}
