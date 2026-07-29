import AVFoundation
import Foundation
import XCTest
@testable import CustomVideoPlayer

/// Tests for `ABLoopManager` activation semantics, loop detection, and persistence.
///
/// These cover the contract that the A-B loop feature depends on end to end: activating
/// a loop must leave it active, and `shouldLoop(at:)` must report the seek target once
/// playback passes point B.
final class ABLoopManagerTests: XCTestCase {
    private var manager: ABLoopManager!
    private let videoID = "https://example.com/test.m3u8"

    override func setUp() {
        super.setUp()
        manager = ABLoopManager()
        // The manager persists to UserDefaults.standard, so clear shared state to keep
        // tests independent of each other and of anything left by the host app.
        manager.clearAllLoopData()
    }

    override func tearDown() {
        manager.clearAllLoopData()
        manager = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeLoop(fromSeconds start: Int, toSeconds end: Int, name: String? = nil) -> ABLoop {
        ABLoop(
            pointA: TimePoint(seconds: start),
            pointB: TimePoint(seconds: end),
            name: name
        )
    }

    private func makePlaylist(segmentCount: Int = 2, isLooping: Bool = false) -> SegmentPlaylist {
        let segments = (0 ..< segmentCount).map { index in
            PlaybackSegment(
                startPoint: TimePoint(seconds: index * 10),
                endPoint: TimePoint(seconds: index * 10 + 5),
                order: index
            )
        }
        return SegmentPlaylist(
            name: "Practice run",
            segments: segments,
            videoIdentifier: videoID,
            isLooping: isLooping
        )
    }

    // MARK: - Activation

    /// Regression test for the defect that made the A-B loop feature inert: selecting a
    /// loop left no loop active, so playback never looped.
    func testSetActiveLoopLeavesTheLoopActive() {
        let loop = makeLoop(fromSeconds: 5, toSeconds: 10)

        manager.setActiveLoop(loop)

        XCTAssertEqual(manager.getActiveLoop(), loop, "Activating a loop must leave it active.")
    }

    /// Activating a loop is sufficient on its own — the manager clears the other mode.
    /// Callers must not "also" clear it; see `testClearingTheOtherModeAfterActivationWipesTheLoop`.
    func testActivatingLoopClearsAnyActiveSegmentPlaylist() {
        manager.setActiveSegmentPlaylist(makePlaylist())
        XCTAssertNotNil(manager.getActiveSegmentPlaylist())

        let loop = makeLoop(fromSeconds: 0, toSeconds: 3)
        manager.setActiveLoop(loop)

        XCTAssertEqual(manager.getActiveLoop(), loop)
        XCTAssertNil(manager.getActiveSegmentPlaylist(), "The two modes are mutually exclusive.")
    }

    func testActivatingSegmentPlaylistClearsAnyActiveLoop() {
        manager.setActiveLoop(makeLoop(fromSeconds: 0, toSeconds: 3))
        XCTAssertNotNil(manager.getActiveLoop())

        let playlist = makePlaylist()
        manager.setActiveSegmentPlaylist(playlist)

        XCTAssertEqual(manager.getActiveSegmentPlaylist(), playlist)
        XCTAssertNil(manager.getActiveLoop(), "The two modes are mutually exclusive.")
        XCTAssertEqual(manager.getCurrentSegment(), playlist.segments.first)
    }

    /// Characterization test documenting the trap that caused the original defect.
    ///
    /// Both setters already clear the opposing mode, and both dispatch onto the same
    /// serial queue. A caller that activates one mode and then clears the other enqueues
    /// a second block that nils what it just set — deterministically, not as a race.
    /// Callers must set exactly one mode and stop.
    func testClearingTheOtherModeAfterActivationWipesTheLoop() {
        manager.setActiveLoop(makeLoop(fromSeconds: 5, toSeconds: 10))
        manager.setActiveSegmentPlaylist(nil)

        XCTAssertNil(
            manager.getActiveLoop(),
            "Redundant cross-clearing destroys the activation; callers must not do this."
        )
    }

    func testDeactivatingClearsEverything() {
        manager.setActiveLoop(makeLoop(fromSeconds: 1, toSeconds: 2))
        manager.setActiveLoop(nil)

        XCTAssertNil(manager.getActiveLoop())
        XCTAssertNil(manager.getActiveSegmentPlaylist())
        XCTAssertNil(manager.getCurrentSegment())
    }

    // MARK: - Loop detection

    func testShouldLoopReturnsNilBeforePointB() {
        manager.setActiveLoop(makeLoop(fromSeconds: 5, toSeconds: 10))

        let beforeEnd = CMTime(seconds: 7, preferredTimescale: 600)

        XCTAssertNil(manager.shouldLoop(at: beforeEnd))
    }

    func testShouldLoopSeeksBackToPointAAtPointB() {
        manager.setActiveLoop(makeLoop(fromSeconds: 5, toSeconds: 10))

        let atEnd = CMTime(seconds: 10, preferredTimescale: 600)
        let seekTarget = manager.shouldLoop(at: atEnd)

        XCTAssertNotNil(seekTarget, "Reaching point B must produce a seek back to point A.")
        XCTAssertEqual(CMTimeGetSeconds(seekTarget ?? .zero), 5, accuracy: 0.001)
    }

    func testShouldLoopSeeksBackToPointAPastPointB() {
        manager.setActiveLoop(makeLoop(fromSeconds: 5, toSeconds: 10))

        let pastEnd = CMTime(seconds: 12, preferredTimescale: 600)
        let seekTarget = manager.shouldLoop(at: pastEnd)

        XCTAssertEqual(CMTimeGetSeconds(seekTarget ?? .zero), 5, accuracy: 0.001)
    }

    func testShouldLoopReturnsNilWhenNothingIsActive() {
        XCTAssertNil(manager.shouldLoop(at: CMTime(seconds: 99, preferredTimescale: 600)))
    }

    // MARK: - Storage

    func testAddedLoopsAreRetrievableForTheirVideo() {
        let first = makeLoop(fromSeconds: 0, toSeconds: 5, name: "Intro")
        let second = makeLoop(fromSeconds: 30, toSeconds: 45, name: "Solo")

        manager.addABLoop(first, for: videoID)
        manager.addABLoop(second, for: videoID)

        XCTAssertEqual(manager.getABLoops(for: videoID), [first, second])
    }

    func testLoopsAreScopedToTheirVideo() {
        manager.addABLoop(makeLoop(fromSeconds: 0, toSeconds: 5), for: videoID)

        XCTAssertTrue(manager.getABLoops(for: "https://example.com/other.m3u8").isEmpty)
    }

    func testRemovingALoopAlsoDeactivatesIt() {
        let loop = makeLoop(fromSeconds: 0, toSeconds: 5)
        manager.addABLoop(loop, for: videoID)
        manager.setActiveLoop(loop)

        manager.removeABLoop(withId: loop.id, for: videoID)

        XCTAssertTrue(manager.getABLoops(for: videoID).isEmpty)
        XCTAssertNil(manager.getActiveLoop(), "Removing the active loop must deactivate it.")
    }

    func testLoopsSurviveANewManagerInstance() {
        let loop = makeLoop(fromSeconds: 12, toSeconds: 34, name: "Bridge")
        manager.addABLoop(loop, for: videoID)

        let reloaded = ABLoopManager()

        XCTAssertEqual(reloaded.getABLoops(for: videoID), [loop], "Loops must persist across launches.")
    }

    /// An intentional removal of the last loop must still reach storage — the
    /// "don't overwrite good data with an empty set" guard only applies after a load
    /// that failed to decode, never to a deliberate edit.
    func testRemovingTheLastLoopIsPersisted() {
        let loop = makeLoop(fromSeconds: 0, toSeconds: 5)
        manager.addABLoop(loop, for: videoID)

        manager.removeABLoop(withId: loop.id, for: videoID)

        XCTAssertTrue(
            ABLoopManager().getABLoops(for: videoID).isEmpty,
            "An intentional removal must be persisted, not suppressed."
        )
    }

    // MARK: - Thread safety

    /// `videoLoopData` used to be mutated on the caller's thread while only the
    /// activation state was queue-guarded, so a concurrent add and read could corrupt
    /// the dictionary or silently drop a write. All access now goes through the single
    /// serial `stateQueue`, and interleaving reads must not cost a write.
    func testConcurrentAddsAndReadsDoNotCorruptLoopStorage() {
        let manager = self.manager!
        let iterations = 64

        DispatchQueue.concurrentPerform(iterations: iterations) { index in
            if index.isMultiple(of: 2) {
                manager.addABLoop(makeLoop(fromSeconds: index, toSeconds: index + 1), for: videoID)
            } else {
                _ = manager.getABLoops(for: videoID)
            }
        }

        let loops = manager.getABLoops(for: videoID)
        XCTAssertEqual(loops.count, iterations / 2, "A lost write means the dictionary raced.")
        XCTAssertEqual(
            Set(loops.map(\.id)).count,
            iterations / 2,
            "Every concurrently added loop must survive intact and distinct."
        )
    }

    /// Inserting *new* keys concurrently is the case that actually corrupts a
    /// `Dictionary` (it can reallocate storage), so exercise several videos at once.
    func testConcurrentAddsAcrossVideosDoNotCorruptTheDictionary() {
        let manager = self.manager!
        let videoIDs = (0 ..< 8).map { "https://example.com/concurrent-\($0).m3u8" }
        let loopsPerVideo = 8

        DispatchQueue.concurrentPerform(iterations: videoIDs.count * loopsPerVideo) { index in
            let identifier = videoIDs[index % videoIDs.count]
            manager.addABLoop(makeLoop(fromSeconds: index, toSeconds: index + 1), for: identifier)
        }

        for identifier in videoIDs {
            XCTAssertEqual(
                manager.getABLoops(for: identifier).count,
                loopsPerVideo,
                "Concurrent inserts of new keys dropped entries for \(identifier)."
            )
        }
    }

    /// Every public method takes `stateQueue` exactly once, so the whole API can be
    /// driven back to back off the main queue without re-entering the queue.
    ///
    /// The expectation timeout is what turns a re-entrancy bug into a test failure
    /// instead of a hung CI job.
    func testCommonCallSequencesDoNotDeadlock() {
        let manager = self.manager!
        let videoID = self.videoID
        let loop = makeLoop(fromSeconds: 0, toSeconds: 5)
        let playlist = makePlaylist()
        let updatedPlaylist = SegmentPlaylist(
            id: playlist.id,
            name: "Updated",
            segments: playlist.segments,
            videoIdentifier: videoID,
            isLooping: true
        )
        let farFuture = CMTime(seconds: 99, preferredTimescale: 600)
        let finished = expectation(description: "the full call sequence returns")

        DispatchQueue.global(qos: .userInitiated).async {
            manager.addABLoop(loop, for: videoID)
            manager.setActiveLoop(loop)
            _ = manager.getActiveLoop()
            _ = manager.getABLoops(for: videoID)
            _ = manager.shouldLoop(at: farFuture)

            manager.addSegmentPlaylist(playlist, for: videoID)
            manager.updateSegmentPlaylist(updatedPlaylist, for: videoID)
            _ = manager.getSegmentPlaylists(for: videoID)
            manager.setActiveSegmentPlaylist(updatedPlaylist)
            _ = manager.getActiveSegmentPlaylist()
            _ = manager.getCurrentSegment()
            _ = manager.shouldAdvanceSegment(at: farFuture)

            manager.removeSegmentPlaylist(withId: playlist.id, for: videoID)
            manager.removeABLoop(withId: loop.id, for: videoID)
            manager.clearLoopData(for: videoID)
            manager.clearAllLoopData()

            // `init` loads under the same queue; constructing off the main queue must
            // not deadlock either.
            _ = ABLoopManager()
            finished.fulfill()
        }

        wait(for: [finished], timeout: 10)
    }

    /// Mutations and reads interleaved from several queues at once, including the
    /// activation state, must all complete — the two halves of the state share one
    /// queue precisely so they can be updated together without a second lock.
    func testInterleavedMutationAndActivationDoNotDeadlock() {
        let manager = self.manager!
        let loops = (0 ..< 16).map { makeLoop(fromSeconds: $0, toSeconds: $0 + 1) }
        let playlist = makePlaylist()

        DispatchQueue.concurrentPerform(iterations: loops.count) { index in
            let loop = loops[index]
            manager.addABLoop(loop, for: videoID)
            manager.setActiveLoop(loop)
            _ = manager.shouldLoop(at: CMTime(seconds: 99, preferredTimescale: 600))
            manager.addSegmentPlaylist(playlist, for: videoID)
            _ = manager.getSegmentPlaylists(for: videoID)
            manager.removeABLoop(withId: loop.id, for: videoID)
        }

        XCTAssertTrue(
            manager.getABLoops(for: videoID).isEmpty,
            "Each loop was added and removed, so none may remain."
        )
        XCTAssertEqual(manager.getSegmentPlaylists(for: videoID).count, loops.count)
    }

    // MARK: - Persistence recovery

    /// A stored blob that cannot be decoded is quarantined rather than discarded, and
    /// a subsequent empty save must not replace it — losing loops to one bad byte was
    /// the old behaviour.
    func testUnreadableStoredDataIsQuarantinedAndNotOverwritten() {
        let corrupted = Data("this is not JSON".utf8)
        UserDefaults.standard.set(corrupted, forKey: ABLoopConstants.storageKey)
        UserDefaults.standard.removeObject(forKey: ABLoopManager.corruptedStorageKey)

        let reloaded = ABLoopManager()

        XCTAssertTrue(
            reloaded.getABLoops(for: videoID).isEmpty,
            "Undecodable storage must surface as no loops, not as guessed data."
        )
        XCTAssertEqual(
            UserDefaults.standard.data(forKey: ABLoopManager.corruptedStorageKey),
            corrupted,
            "The unreadable blob must be preserved so a future migration can recover it."
        )

        // Mutations that leave the manager empty must not write "[]" over the blob.
        reloaded.removeABLoop(withId: UUID(), for: videoID)
        reloaded.clearLoopData(for: "https://example.com/never-stored.m3u8")

        XCTAssertEqual(
            UserDefaults.standard.data(forKey: ABLoopConstants.storageKey),
            corrupted,
            "An empty save must not destroy data that merely failed to decode."
        )
    }

    /// Once there is real data to store again, saving resumes normally and the
    /// quarantined copy is left alone.
    func testDataWrittenAfterACorruptLoadPersistsAndKeepsTheBackup() {
        let corrupted = Data("{ truncated".utf8)
        UserDefaults.standard.set(corrupted, forKey: ABLoopConstants.storageKey)
        UserDefaults.standard.removeObject(forKey: ABLoopManager.corruptedStorageKey)

        let recovered = ABLoopManager()
        let loop = makeLoop(fromSeconds: 3, toSeconds: 9, name: "After recovery")
        recovered.addABLoop(loop, for: videoID)

        XCTAssertEqual(
            ABLoopManager().getABLoops(for: videoID),
            [loop],
            "Data written after a failed load must persist normally."
        )
        XCTAssertEqual(
            UserDefaults.standard.data(forKey: ABLoopManager.corruptedStorageKey),
            corrupted,
            "The quarantined blob must survive later writes."
        )
    }

    /// `Dictionary(uniqueKeysWithValues:)` traps on a duplicate key, so a stored blob
    /// with two entries for the same video used to crash the app at player
    /// construction. Duplicates are now collapsed, keeping the richer entry.
    func testDuplicateVideoIdentifiersInStorageDoNotTrap() throws {
        let sparse = VideoLoopData(
            videoIdentifier: videoID,
            abLoops: [makeLoop(fromSeconds: 0, toSeconds: 1)]
        )
        let rich = VideoLoopData(
            videoIdentifier: videoID,
            abLoops: [
                makeLoop(fromSeconds: 10, toSeconds: 11, name: "Kept"),
                makeLoop(fromSeconds: 20, toSeconds: 21, name: "Also kept")
            ]
        )

        // Either encounter order must resolve the same way.
        for stored in [[sparse, rich], [rich, sparse]] {
            let encoded = try JSONEncoder().encode(stored)
            UserDefaults.standard.set(encoded, forKey: ABLoopConstants.storageKey)
            UserDefaults.standard.removeObject(forKey: ABLoopManager.corruptedStorageKey)

            let reloaded = ABLoopManager()

            XCTAssertEqual(
                reloaded.getABLoops(for: videoID),
                rich.abLoops,
                "Duplicate identifiers must collapse deterministically onto the richer entry."
            )
            XCTAssertNil(
                UserDefaults.standard.data(forKey: ABLoopManager.corruptedStorageKey),
                "A duplicate key is decodable, so nothing should be quarantined."
            )
        }
    }
}
