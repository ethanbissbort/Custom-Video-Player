import AVFoundation
import Foundation
import XCTest
@testable import CustomVideoPlayer

/// Records the segment-playlist callbacks `ABLoopManager` delivers.
///
/// The manager always hands delegate calls to the main queue, so every mutation here
/// happens on the thread XCTest runs the assertions on.
private final class SegmentPlaylistDelegateSpy: ABLoopManagerDelegate {
    private(set) var finishedSegments: [PlaybackSegment] = []
    private(set) var completedPlaylists: [SegmentPlaylist] = []

    var onFinishSegment: (() -> Void)?
    var onComplete: (() -> Void)?

    func abLoopDidReachEnd(_ loop: ABLoop) {}

    func segmentPlaylistDidFinishSegment(_ segment: PlaybackSegment) {
        finishedSegments.append(segment)
        onFinishSegment?()
    }

    func segmentPlaylistDidComplete(_ playlist: SegmentPlaylist) {
        completedPlaylists.append(playlist)
        onComplete?()
    }
}

/// Tests for the segment playlist feature.
///
/// The engine behind segment playlists — `shouldAdvanceSegment(at:)`,
/// `SegmentPlaylist.nextSegment(after:)` and the two playlist delegate callbacks — was
/// unreachable for as long as nothing could create a playlist: `addSegmentPlaylist(_:for:)`
/// had no callers, so the Segment Playlists tab was permanently empty. These tests drive
/// the same sequence `SegmentPlaylistCreationViewController` now performs on save, then
/// exercise the playback transitions that sequence unlocks.
final class SegmentPlaylistTests: XCTestCase {
    private var manager: ABLoopManager!
    private var delegateSpy: SegmentPlaylistDelegateSpy!

    private let videoID = "https://example.com/segments.m3u8"
    private let otherVideoID = "https://example.com/other-segments.m3u8"

    override func setUp() {
        super.setUp()
        manager = ABLoopManager()
        // The manager persists to UserDefaults.standard, so clear shared state to keep
        // tests independent of each other and of anything left by the host app.
        manager.clearAllLoopData()
        delegateSpy = SegmentPlaylistDelegateSpy()
        manager.delegate = delegateSpy
    }

    override func tearDown() {
        manager.clearAllLoopData()
        manager = nil
        delegateSpy = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Builds segments whose `order` matches their position, which is the invariant the
    /// creation UI maintains and `ABLoopValidation.validateSegmentPlaylist(_:)` enforces.
    private func makeSegments(_ ranges: [(start: Int, end: Int)]) -> [PlaybackSegment] {
        ranges.enumerated().map { index, range in
            PlaybackSegment(
                startPoint: TimePoint(seconds: range.start),
                endPoint: TimePoint(seconds: range.end),
                order: index
            )
        }
    }

    /// Default ranges deliberately start away from zero so a wrap-around to the first
    /// segment is distinguishable from "returned CMTime.zero".
    private func makePlaylist(
        name: String = "Practice run",
        ranges: [(start: Int, end: Int)] = [(start: 5, end: 10), (start: 20, end: 25)],
        isLooping: Bool = false,
        videoIdentifier: String? = nil
    ) -> SegmentPlaylist {
        SegmentPlaylist(
            name: name,
            segments: makeSegments(ranges),
            videoIdentifier: videoIdentifier ?? videoID,
            isLooping: isLooping
        )
    }

    private func seconds(_ value: Int) -> CMTime {
        CMTime(seconds: Double(value), preferredTimescale: 600)
    }

    // MARK: - Creation and persistence

    /// End to end along the path the creation dialog takes on save: validate, store,
    /// then read back — including from a fresh manager, which is what the next launch does.
    func testCreatingASegmentPlaylistValidatesStoresAndReloads() {
        let playlist = makePlaylist(name: "Solo drill", ranges: [(start: 5, end: 10), (start: 20, end: 25), (start: 40, end: 55)], isLooping: true)

        XCTAssertTrue(
            ABLoopValidation.validateSegmentPlaylist(playlist).isValid,
            "The creation dialog refuses to save a playlist that fails validation."
        )

        manager.addSegmentPlaylist(playlist, for: videoID)

        XCTAssertEqual(manager.getSegmentPlaylists(for: videoID), [playlist])
        XCTAssertEqual(
            ABLoopManager().getSegmentPlaylists(for: videoID),
            [playlist],
            "A created playlist must survive to the next launch."
        )
        XCTAssertEqual(
            ABLoopManager().getSegmentPlaylists(for: videoID).first?.segments.map(\.order),
            [0, 1, 2],
            "Segment order is what drives playback, so it must round-trip intact."
        )
    }

    func testSegmentPlaylistsAreScopedToTheirVideo() {
        manager.addSegmentPlaylist(makePlaylist(), for: videoID)

        XCTAssertTrue(manager.getSegmentPlaylists(for: otherVideoID).isEmpty)
    }

    func testActivatingAPlaylistStartsOnItsFirstSegment() {
        let playlist = makePlaylist()

        manager.setActiveSegmentPlaylist(playlist)

        XCTAssertEqual(manager.getActiveSegmentPlaylist(), playlist)
        XCTAssertEqual(manager.getCurrentSegment(), playlist.segments.first)
    }

    func testRemovingTheActivePlaylistDeactivatesIt() {
        let playlist = makePlaylist()
        manager.addSegmentPlaylist(playlist, for: videoID)
        manager.setActiveSegmentPlaylist(playlist)

        manager.removeSegmentPlaylist(withId: playlist.id, for: videoID)

        XCTAssertTrue(manager.getSegmentPlaylists(for: videoID).isEmpty)
        XCTAssertNil(manager.getActiveSegmentPlaylist())
        XCTAssertNil(manager.getCurrentSegment())
    }

    // MARK: - Segment transitions

    func testShouldAdvanceSegmentReturnsNilBeforeTheSegmentEnds() {
        manager.setActiveSegmentPlaylist(makePlaylist())

        XCTAssertNil(manager.shouldAdvanceSegment(at: seconds(7)))
    }

    func testShouldAdvanceSegmentReturnsNilWhenNoPlaylistIsActive() {
        XCTAssertNil(manager.shouldAdvanceSegment(at: seconds(99)))
    }

    func testShouldAdvanceSegmentSeeksToTheNextSegmentStart() {
        let playlist = makePlaylist()
        manager.setActiveSegmentPlaylist(playlist)

        let seekTarget = manager.shouldAdvanceSegment(at: seconds(10))

        XCTAssertNotNil(seekTarget, "Reaching a segment's end must seek to the next segment.")
        XCTAssertEqual(CMTimeGetSeconds(seekTarget ?? .zero), 20, accuracy: 0.001)
        XCTAssertEqual(manager.getCurrentSegment(), playlist.segments.last)
    }

    func testEachFinishedSegmentIsReportedInOrder() {
        let playlist = makePlaylist()
        manager.setActiveSegmentPlaylist(playlist)

        let bothReported = expectation(description: "both segments are reported as finished")
        bothReported.expectedFulfillmentCount = 2
        delegateSpy.onFinishSegment = { bothReported.fulfill() }

        _ = manager.shouldAdvanceSegment(at: seconds(10))
        _ = manager.shouldAdvanceSegment(at: seconds(25))

        wait(for: [bothReported], timeout: 5)

        XCTAssertEqual(delegateSpy.finishedSegments, playlist.segments)
    }

    /// `segmentPlaylistDidComplete` could never fire before, because no playlist could be
    /// created in the first place. With a real creation flow it is reachable, and this is
    /// the transition that reaches it.
    func testNonLoopingPlaylistCompletesAndDeactivatesAfterItsLastSegment() {
        let playlist = makePlaylist()
        manager.setActiveSegmentPlaylist(playlist)

        let completed = expectation(description: "segmentPlaylistDidComplete is delivered")
        delegateSpy.onComplete = { completed.fulfill() }

        XCTAssertNotNil(manager.shouldAdvanceSegment(at: seconds(10)))
        XCTAssertNil(
            manager.shouldAdvanceSegment(at: seconds(25)),
            "The final segment of a non-looping playlist has no successor to seek to."
        )

        wait(for: [completed], timeout: 5)

        XCTAssertEqual(delegateSpy.completedPlaylists, [playlist])
        XCTAssertNil(manager.getActiveSegmentPlaylist(), "A finished playlist deactivates itself.")
        XCTAssertNil(manager.getCurrentSegment())
    }

    func testLoopingPlaylistWrapsAroundToItsFirstSegment() {
        let playlist = makePlaylist(isLooping: true)
        manager.setActiveSegmentPlaylist(playlist)

        XCTAssertNotNil(manager.shouldAdvanceSegment(at: seconds(10)))
        let wrapTarget = manager.shouldAdvanceSegment(at: seconds(25))

        XCTAssertNotNil(wrapTarget, "A looping playlist must seek back to its first segment.")
        XCTAssertEqual(CMTimeGetSeconds(wrapTarget ?? .zero), 5, accuracy: 0.001)
        XCTAssertEqual(manager.getCurrentSegment(), playlist.segments.first)
        XCTAssertEqual(
            manager.getActiveSegmentPlaylist(),
            playlist,
            "A looping playlist stays active across the wrap-around."
        )
    }

    func testSingleSegmentLoopingPlaylistRepeatsItself() {
        let playlist = makePlaylist(ranges: [(start: 5, end: 10)], isLooping: true)
        manager.setActiveSegmentPlaylist(playlist)

        let seekTarget = manager.shouldAdvanceSegment(at: seconds(10))

        XCTAssertEqual(CMTimeGetSeconds(seekTarget ?? .zero), 5, accuracy: 0.001)
        XCTAssertEqual(manager.getCurrentSegment(), playlist.segments.first)
    }

    // MARK: - Validation

    /// The bound that was defined but never called: a point past the end of the video
    /// produces a loop or segment that looks normal, activates, and never fires because
    /// playback can never reach it.
    func testValidationRejectsATimePointBeyondTheVideoDuration() {
        let duration = CMTime(seconds: 60, preferredTimescale: 600)
        let beyondEnd = TimePoint(minutes: 1, seconds: 30)

        let result = ABLoopValidation.validateTimePointWithinDuration(beyondEnd, duration: duration)

        XCTAssertFalse(result.isValid, "A point past the end of the video must be rejected.")
        XCTAssertEqual(result.errorMessage, ABLoopConstants.Strings.durationExceededMessage)
    }

    func testValidationAcceptsATimePointInsideTheVideoDuration() {
        let duration = CMTime(seconds: 60, preferredTimescale: 600)

        XCTAssertTrue(
            ABLoopValidation.validateTimePointWithinDuration(TimePoint(seconds: 59), duration: duration).isValid
        )
    }

    func testValidationAcceptsATimePointExactlyAtTheVideoEnd() {
        let duration = CMTime(seconds: 60, preferredTimescale: 600)

        XCTAssertTrue(
            ABLoopValidation.validateTimePointWithinDuration(TimePoint(minutes: 1), duration: duration).isValid
        )
    }

    func testValidationRejectsAPlaylistWithNoSegments() {
        let empty = SegmentPlaylist(name: "Empty", segments: [], videoIdentifier: videoID)

        let result = ABLoopValidation.validateSegmentPlaylist(empty)

        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.errorMessage, ABLoopConstants.Strings.emptyPlaylistMessage)
    }

    func testValidationRejectsASegmentThatEndsBeforeItStarts() {
        let inverted = SegmentPlaylist(
            name: "Backwards",
            segments: [
                PlaybackSegment(
                    startPoint: TimePoint(seconds: 20),
                    endPoint: TimePoint(seconds: 10),
                    order: 0
                )
            ],
            videoIdentifier: videoID
        )

        XCTAssertFalse(ABLoopValidation.validateSegmentPlaylist(inverted).isValid)
    }

    /// The creation UI renumbers after every insertion, deletion and reorder precisely so
    /// this check can never fail on a playlist the user assembled.
    func testValidationRejectsNonContiguousSegmentOrdering() {
        let gapped = SegmentPlaylist(
            name: "Gapped",
            segments: [
                PlaybackSegment(startPoint: TimePoint(seconds: 5), endPoint: TimePoint(seconds: 10), order: 0),
                PlaybackSegment(startPoint: TimePoint(seconds: 20), endPoint: TimePoint(seconds: 25), order: 7)
            ],
            videoIdentifier: videoID
        )

        XCTAssertFalse(ABLoopValidation.validateSegmentPlaylist(gapped).isValid)
    }

    func testValidationAcceptsAPlaylistBuiltTheWayTheCreationFlowBuildsOne() {
        XCTAssertTrue(ABLoopValidation.validateSegmentPlaylist(makePlaylist()).isValid)
    }
}
