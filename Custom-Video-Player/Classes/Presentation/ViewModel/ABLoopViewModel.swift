import Foundation
import AVFoundation

/// Mode for the A-B Loop view controller
enum ABLoopViewMode {
    case abLoop
    case segmentPlaylist
}

/// ViewModel for managing A-B loop data and business logic
class ABLoopViewModel {
    // MARK: - Properties

    let abLoopManager: ABLoopManager
    let videoIdentifier: String
    private(set) var currentMode: ABLoopViewMode = .abLoop

    private(set) var abLoops: [ABLoop] = []
    private(set) var segmentPlaylists: [SegmentPlaylist] = []

    // MARK: - Initialization

    init(abLoopManager: ABLoopManager, videoIdentifier: String) {
        self.abLoopManager = abLoopManager
        self.videoIdentifier = videoIdentifier
        loadData()
    }

    // MARK: - Data Management

    /// Loads all loops and playlists for the current video
    func loadData() {
        abLoops = abLoopManager.getABLoops(for: videoIdentifier)
        segmentPlaylists = abLoopManager.getSegmentPlaylists(for: videoIdentifier)
    }

    /// Returns the number of items in the current mode
    var itemCount: Int {
        switch currentMode {
        case .abLoop:
            return abLoops.count
        case .segmentPlaylist:
            return segmentPlaylists.count
        }
    }

    /// Switches the current mode
    func switchMode(to mode: ABLoopViewMode) {
        currentMode = mode
    }

    // MARK: - A-B Loop Operations

    /// Returns the A-B loop at the specified index
    func getABLoop(at index: Int) -> ABLoop? {
        guard index < abLoops.count else { return nil }
        return abLoops[index]
    }

    /// Checks if the A-B loop at the specified index is active
    func isABLoopActive(at index: Int) -> Bool {
        guard let loop = getABLoop(at: index) else { return false }
        return abLoopManager.getActiveLoop()?.id == loop.id
    }

    /// Removes the A-B loop at the specified index
    func removeABLoop(at index: Int) {
        guard let loop = getABLoop(at: index) else { return }
        abLoopManager.removeABLoop(withId: loop.id, for: videoIdentifier)
        abLoops.remove(at: index)
    }

    // MARK: - Segment Playlist Operations

    /// Returns the segment playlist at the specified index
    func getSegmentPlaylist(at index: Int) -> SegmentPlaylist? {
        guard index < segmentPlaylists.count else { return nil }
        return segmentPlaylists[index]
    }

    /// Checks if the segment playlist at the specified index is active
    func isSegmentPlaylistActive(at index: Int) -> Bool {
        guard let playlist = getSegmentPlaylist(at: index) else { return false }
        return abLoopManager.getActiveSegmentPlaylist()?.id == playlist.id
    }

    /// Removes the segment playlist at the specified index
    func removeSegmentPlaylist(at index: Int) {
        guard let playlist = getSegmentPlaylist(at: index) else { return }
        abLoopManager.removeSegmentPlaylist(withId: playlist.id, for: videoIdentifier)
        segmentPlaylists.remove(at: index)
    }

    // MARK: - Active State

    /// Checks if there is any active loop or playlist
    var hasActiveLoopOrPlaylist: Bool {
        return abLoopManager.getActiveLoop() != nil || abLoopManager.getActiveSegmentPlaylist() != nil
    }

    /// Returns the title for the create button based on current mode
    var createButtonTitle: String {
        switch currentMode {
        case .abLoop:
            return ABLoopConstants.Strings.createNewLoop
        case .segmentPlaylist:
            return ABLoopConstants.Strings.createSegmentPlaylist
        }
    }

    // MARK: - Helpers

    /// Returns a formatted display string for an A-B loop
    func displayString(for loop: ABLoop) -> (title: String, detail: String) {
        let title = loop.name ?? ABLoopConstants.Strings.defaultLoopName
        let detail = "\(loop.pointA.toString()) → \(loop.pointB.toString())"
        return (title, detail)
    }

    /// Returns a formatted display string for a segment playlist
    func displayString(for playlist: SegmentPlaylist) -> (title: String, detail: String) {
        let title = playlist.name
        let detail = "\(playlist.segments.count) segment(s)"
        return (title, detail)
    }
}
