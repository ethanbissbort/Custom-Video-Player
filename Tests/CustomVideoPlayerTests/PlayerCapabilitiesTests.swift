import AVFoundation
import UIKit
import XCTest
@testable import CustomVideoPlayer

/// Tests for the playback capabilities added on top of the core player: variable speed,
/// Picture-in-Picture availability, and the live-content gating of the A-B loop button.
///
/// Everything here is exercised without real playback. The controller is built but its view is
/// deliberately never loaded — `viewDidLoad()` constructs an `AVPlayer` around the configured URL,
/// which would put a network fetch inside a unit test. Where a player is needed, a bare
/// `AVPlayer()` with no item stands in: it has a well-defined `rate` of `0` and touches no media.
///
/// XCTest invokes these on the main thread, which is what the UIKit access below requires.
final class PlayerCapabilitiesTests: XCTestCase {
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
    }

    override func tearDown() {
        // The delegate methods under test restart the controls auto-hide timer, which retains the
        // controller until it fires. Cancel it so nothing outlives the test case.
        controller.invalidateControlsHiddenTimer()
        controller = nil
        super.tearDown()
    }

    // MARK: - Speed cycle

    /// The cycle must visit every advertised rate, in ascending order, exactly once per lap.
    func testSpeedCycleVisitsEveryRateInAscendingOrder() {
        XCTAssertEqual(
            PlaybackSpeed.allCases.map { $0.rawValue },
            [0.5, 0.75, 1.0, 1.25, 1.5, 2.0],
            "The advertised speed ladder changed; the control's labels and the player's rate clamping both depend on it."
        )

        var visited: [Float] = []
        var speed = PlaybackSpeed.half
        for _ in PlaybackSpeed.allCases {
            visited.append(speed.rawValue)
            speed = speed.next
        }

        XCTAssertEqual(visited, [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
    }

    /// Wrap-around is the part a hand-rolled `index + 1` gets wrong.
    func testSpeedCycleWrapsFromFastestToSlowest() {
        XCTAssertEqual(PlaybackSpeed.double.next, .half)
        XCTAssertEqual(PlaybackSpeed.normal.next, .fiveQuarters)
    }

    func testSpeedDisplayTextMatchesRate() {
        XCTAssertEqual(PlaybackSpeed.half.displayText, "0.5x")
        XCTAssertEqual(PlaybackSpeed.threeQuarters.displayText, "0.75x")
        XCTAssertEqual(PlaybackSpeed.normal.displayText, "1x")
        XCTAssertEqual(PlaybackSpeed.fiveQuarters.displayText, "1.25x")
        XCTAssertEqual(PlaybackSpeed.threeHalves.displayText, "1.5x")
        XCTAssertEqual(PlaybackSpeed.double.displayText, "2x")
    }

    /// Tapping the control has to both advance its own state and report the new rate; reporting a
    /// rate the button is no longer showing would desynchronise the UI from the player.
    func testSpeedButtonAdvancesAndReportsEveryRate() {
        let controlsView = PlayerControlsView()
        let delegate = PlayerControlsDelegateSpy()
        controlsView.delegate = delegate

        XCTAssertEqual(controlsView.playbackSpeed, .normal, "The control must start at 1x.")

        // One full lap from 1x back to 1x.
        for _ in PlaybackSpeed.allCases {
            controlsView.cyclePlaybackSpeed()
        }

        XCTAssertEqual(delegate.reportedRates, [1.25, 1.5, 2.0, 0.5, 0.75, 1.0])
        XCTAssertEqual(controlsView.playbackSpeed, .normal, "A full lap must return to where it started.")
    }

    // MARK: - Selecting a speed must never start playback

    /// The central safety property of the speed control: `AVPlayer.rate` is the transport control,
    /// so writing a non-zero value while paused *starts* the video. Picking a speed on a paused
    /// player must therefore leave the player untouched.
    func testSelectingASpeedWhilePausedDoesNotStartPlayback() {
        let player = AVPlayer()
        controller.player = player
        controller.viewModel.playerState = .pause

        controller.didChangePlaybackSpeed(to: 2.0)

        XCTAssertEqual(player.rate, 0, "Selecting a speed while paused must not set a non-zero rate.")
        XCTAssertEqual(controller.viewModel.playerState, .pause, "Selecting a speed must not change the play/pause state.")
    }

    /// …but the selection is still remembered, so the next resume plays at the chosen speed.
    func testSelectingASpeedWhilePausedIsStillRemembered() {
        controller.player = AVPlayer()
        controller.viewModel.playerState = .pause

        XCTAssertEqual(controller.selectedPlaybackRate, 1.0, "The player must start at 1x.")

        controller.didChangePlaybackSpeed(to: 0.5)

        XCTAssertEqual(controller.selectedPlaybackRate, 0.5, accuracy: 0.0001)
    }

    /// Re-applying the stored rate — which happens on resume, after scrubbing and after a stall —
    /// must also be inert while paused, for the same reason.
    func testApplyingTheStoredRateWhilePausedDoesNotStartPlayback() {
        let player = AVPlayer()
        controller.player = player
        controller.setPlaybackRate(1.5)
        controller.viewModel.playerState = .pause

        controller.applySelectedPlaybackRate()

        XCTAssertEqual(player.rate, 0, "Re-applying the stored rate must never resume a paused player.")
    }

    /// The control and the controller have to agree, so the whole delegate path is exercised
    /// rather than just `setPlaybackRate(_:)`.
    func testControlsViewDrivesTheControllerSelectedRate() {
        let controlsView = PlayerControlsView()
        controlsView.delegate = controller
        controller.player = AVPlayer()
        controller.viewModel.playerState = .pause

        controlsView.cyclePlaybackSpeed()

        XCTAssertEqual(controller.selectedPlaybackRate, PlaybackSpeed.fiveQuarters.rawValue, accuracy: 0.0001)
        XCTAssertEqual(controller.viewModel.playerState, .pause)
    }

    // MARK: - Live content gating

    /// Loop evaluation is gated behind `!isLiveContent`, so leaving the A-B button interactive on
    /// a live stream gave the user a button that silently did nothing.
    func testLiveControlsDisableTheABLoopButton() {
        let controlsView = PlayerControlsView()

        XCTAssertTrue(controlsView.isABLoopButtonAvailable, "On-demand content must keep the A-B button.")

        controlsView.enableLiveControls()

        XCTAssertFalse(controlsView.isABLoopButtonAvailable, "A live stream cannot loop, so the A-B button must be gone.")
    }

    // MARK: - Picture in Picture availability

    /// The button stays hidden until the controller reports a usable Picture-in-Picture
    /// controller, which it cannot do where the platform does not support PiP.
    func testPictureInPictureButtonIsHiddenUntilMadeAvailable() {
        let controlsView = PlayerControlsView()

        XCTAssertFalse(controlsView.isPictureInPictureButtonAvailable)

        controlsView.setPictureInPictureAvailable(true)
        XCTAssertTrue(controlsView.isPictureInPictureButtonAvailable)

        controlsView.setPictureInPictureAvailable(false)
        XCTAssertFalse(controlsView.isPictureInPictureButtonAvailable)
    }
}

// MARK: - Helpers

/// Records what `PlayerControlsView` reports upward. Every other requirement is a no-op — the
/// protocol is `@objc` with no optional members, so they all have to exist.
private final class PlayerControlsDelegateSpy: NSObject, PlayerControlsViewDelegate {
    private(set) var reportedRates: [Float] = []
    private(set) var pictureInPictureToggleCount = 0

    func didChangePlaybackSpeed(to rate: Float) {
        reportedRates.append(rate)
    }

    func togglePictureInPicture() {
        pictureInPictureToggleCount += 1
    }

    func seekForward() {}
    func seekBackward() {}
    func togglePlayPause() {}
    func playPreviousVideo() {}
    func playNextVideo() {}
    func goBack() {}
    func sliderValueChanged(slider _: UISlider, event _: UIEvent) {}
    func switchSubtitles() {}
    func openSettings() {}
    func seekToLive() {}
    func openABLoopManager() {}
}
