import AVFoundation
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
}
