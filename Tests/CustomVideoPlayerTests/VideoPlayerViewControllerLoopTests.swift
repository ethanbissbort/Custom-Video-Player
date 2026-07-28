import AVFoundation
import UIKit
import XCTest
@testable import CustomVideoPlayer

/// Regression tests for the player's `ABLoopViewControllerDelegate` conformance.
///
/// The A-B loop defect lived here rather than in `ABLoopManager`: the delegate activated
/// a loop and then cleared the opposing mode, which enqueued a second block on the
/// manager's serial queue that nilled the loop it had just set. These tests exercise the
/// delegate exactly as `ABLoopViewController` does, so reintroducing that call fails CI.
///
/// XCTest invokes these on the main thread, which is what the UIKit access inside the
/// delegate methods requires.
final class VideoPlayerViewControllerLoopTests: XCTestCase {
    private var controller: VideoPlayerViewController!

    override func setUp() {
        super.setUp()
        let playlist = VideoPlaylist(
            title: "Test playlist",
            videos: [Video(url: "https://example.com/video.m3u8", title: "Test", isLiveContent: false)]
        )
        let viewModel = VideoPlayerViewModel(
            useCase: VideoPlayerService(),
            config: VideoPlayerConfig(playlist: playlist)
        )
        controller = VideoPlayerViewController(
            viewModel: viewModel,
            coordinator: VideoPlayerCoordinator(navigationController: UINavigationController())
        )
        controller.abLoopManager.clearAllLoopData()
    }

    override func tearDown() {
        controller.abLoopManager.clearAllLoopData()
        controller = nil
        super.tearDown()
    }

    private func makeLoop(fromSeconds start: Int, toSeconds end: Int) -> ABLoop {
        ABLoop(pointA: TimePoint(seconds: start), pointB: TimePoint(seconds: end))
    }

    private func makePlaylist() -> SegmentPlaylist {
        SegmentPlaylist(
            name: "Run",
            segments: [
                PlaybackSegment(
                    startPoint: TimePoint(seconds: 0),
                    endPoint: TimePoint(seconds: 5),
                    order: 0
                ),
            ],
            videoIdentifier: "https://example.com/video.m3u8"
        )
    }

    /// The core regression: selecting a loop must leave that loop active.
    func testSelectingALoopLeavesItActive() {
        let loop = makeLoop(fromSeconds: 5, toSeconds: 10)

        controller.didSelectABLoop(loop)

        XCTAssertEqual(
            controller.abLoopManager.getActiveLoop(),
            loop,
            "Selecting an A-B loop must leave it active, otherwise playback never loops."
        )
    }

    /// The user-visible consequence: once a loop is selected, passing point B must
    /// produce a seek back to point A.
    func testSelectingALoopMakesPlaybackLoopAtPointB() {
        controller.didSelectABLoop(makeLoop(fromSeconds: 5, toSeconds: 10))

        let seekTarget = controller.abLoopManager.shouldLoop(
            at: CMTime(seconds: 10, preferredTimescale: 600)
        )

        XCTAssertNotNil(seekTarget, "Reaching point B must trigger a loop.")
        XCTAssertEqual(CMTimeGetSeconds(seekTarget ?? .zero), 5, accuracy: 0.001)
    }

    func testSelectingALoopClearsAnyActiveSegmentPlaylist() {
        controller.didSelectSegmentPlaylist(makePlaylist())

        controller.didSelectABLoop(makeLoop(fromSeconds: 1, toSeconds: 2))

        XCTAssertNotNil(controller.abLoopManager.getActiveLoop())
        XCTAssertNil(controller.abLoopManager.getActiveSegmentPlaylist())
    }

    func testSelectingASegmentPlaylistLeavesItActive() {
        let playlist = makePlaylist()

        controller.didSelectSegmentPlaylist(playlist)

        XCTAssertEqual(controller.abLoopManager.getActiveSegmentPlaylist(), playlist)
        XCTAssertNil(controller.abLoopManager.getActiveLoop())
    }

    func testDeselectingALoopStopsLooping() {
        controller.didSelectABLoop(makeLoop(fromSeconds: 5, toSeconds: 10))

        controller.didSelectABLoop(nil)

        XCTAssertNil(controller.abLoopManager.getActiveLoop())
        XCTAssertNil(controller.abLoopManager.shouldLoop(at: CMTime(seconds: 99, preferredTimescale: 600)))
    }
}
