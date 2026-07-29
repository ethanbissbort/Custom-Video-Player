import AVFoundation
import XCTest
@testable import CustomVideoPlayer

/// Regression tests for the view model's time arithmetic.
///
/// `Int64(_:)` and `Int(_:)` **trap** on NaN and on infinities — they are not lossy
/// conversions, they abort the process. The player reaches those values routinely: an item that
/// is not ready reports `CMTime.indefinite`, a live stream reports an indefinite duration, and
/// `player.currentTime()` is invalid between `replaceCurrentItem(with: nil)` and the replacement
/// becoming ready. A tap on the skip buttons in that window used to crash the host app.
///
/// Everything here is pure arithmetic: no network, no player, no waiting.
final class VideoPlayerViewModelTests: XCTestCase {
    private var viewModel: VideoPlayerViewModel!

    /// A use case that never calls back, so no test can accidentally depend on the network.
    private struct StubUseCase: VideoPlayerUseCase {
        func getM3U8Config(videoURL: URL, completion: @escaping (Result<Data, Error>) -> Void) {}
    }

    override func setUp() {
        super.setUp()
        let playlist = VideoPlaylist(
            title: "Test playlist",
            videos: [Video(url: "https://example.com/video.m3u8", title: "Test", isLiveContent: false)]
        )
        viewModel = VideoPlayerViewModel(
            useCase: StubUseCase(),
            config: VideoPlayerConfig(playlist: playlist)
        )
    }

    override func tearDown() {
        viewModel = nil
        super.tearDown()
    }

    private func time(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 600)
    }

    // MARK: - getForwardTime

    func testForwardTimeSeeksAheadByTheSeekDuration() {
        let result = viewModel.getForwardTime(currentTime: time(10), duration: time(100))

        XCTAssertNotNil(result)
        XCTAssertEqual(CMTimeGetSeconds(result ?? .invalid), 25, accuracy: 0.001)
    }

    func testForwardTimeClampsToTheEndOfTheItem() {
        let result = viewModel.getForwardTime(currentTime: time(95), duration: time(100))

        XCTAssertEqual(CMTimeGetSeconds(result ?? .invalid), 100, accuracy: 0.001)
    }

    func testForwardTimeReturnsNilForAnIndefiniteCurrentTime() {
        XCTAssertNil(viewModel.getForwardTime(currentTime: .indefinite, duration: time(100)))
    }

    func testForwardTimeReturnsNilForAnInvalidCurrentTime() {
        XCTAssertNil(viewModel.getForwardTime(currentTime: .invalid, duration: time(100)))
    }

    func testForwardTimeReturnsNilForAnInfiniteCurrentTime() {
        XCTAssertNil(viewModel.getForwardTime(currentTime: .positiveInfinity, duration: time(100)))
        XCTAssertNil(viewModel.getForwardTime(currentTime: .negativeInfinity, duration: time(100)))
    }

    func testForwardTimeReturnsNilForANegativeCurrentTime() {
        XCTAssertNil(viewModel.getForwardTime(currentTime: time(-5), duration: time(100)))
    }

    /// A live stream has no duration to clamp against, so the skip still has to work: the player
    /// pins the request to its own seekable range.
    func testForwardTimeStillSeeksWhenTheDurationIsIndefinite() {
        let result = viewModel.getForwardTime(currentTime: time(10), duration: .indefinite)

        XCTAssertEqual(CMTimeGetSeconds(result ?? .invalid), 25, accuracy: 0.001)
    }

    func testForwardTimeStillSeeksWhenTheDurationIsInvalidOrInfinite() {
        XCTAssertEqual(CMTimeGetSeconds(viewModel.getForwardTime(currentTime: time(10), duration: .invalid) ?? .invalid),
                       25,
                       accuracy: 0.001)
        XCTAssertEqual(CMTimeGetSeconds(viewModel.getForwardTime(currentTime: time(10), duration: .positiveInfinity) ?? .invalid),
                       25,
                       accuracy: 0.001)
    }

    /// A finite but absurd current time still overflows `Int64` once scaled to milliseconds,
    /// which traps just as loudly as NaN does.
    func testForwardTimeReturnsNilWhenTheResultCannotBeRepresented() {
        let hugeTime = CMTimeMake(value: Int64.max / 2, timescale: 1)

        XCTAssertNil(viewModel.getForwardTime(currentTime: hugeTime, duration: .indefinite))
    }

    // MARK: - getBackwardTime

    func testBackwardTimeSeeksBackByTheSeekDuration() {
        let result = viewModel.getBackwardTime(currentTime: time(100))

        XCTAssertEqual(CMTimeGetSeconds(result ?? .invalid), 85, accuracy: 0.001)
    }

    func testBackwardTimeClampsToTheStartOfTheItem() {
        let result = viewModel.getBackwardTime(currentTime: time(5))

        XCTAssertEqual(CMTimeGetSeconds(result ?? .invalid), 0, accuracy: 0.001)
    }

    func testBackwardTimeClampsANegativeCurrentTimeToZero() {
        let result = viewModel.getBackwardTime(currentTime: time(-5))

        XCTAssertEqual(CMTimeGetSeconds(result ?? .invalid), 0, accuracy: 0.001)
    }

    func testBackwardTimeReturnsNilForAnIndefiniteCurrentTime() {
        XCTAssertNil(viewModel.getBackwardTime(currentTime: .indefinite))
    }

    func testBackwardTimeReturnsNilForAnInvalidCurrentTime() {
        XCTAssertNil(viewModel.getBackwardTime(currentTime: .invalid))
    }

    func testBackwardTimeReturnsNilForAnInfiniteCurrentTime() {
        XCTAssertNil(viewModel.getBackwardTime(currentTime: .positiveInfinity))
        XCTAssertNil(viewModel.getBackwardTime(currentTime: .negativeInfinity))
    }

    func testBackwardTimeReturnsNilWhenTheResultCannotBeRepresented() {
        let hugeTime = CMTimeMake(value: Int64.max / 2, timescale: 1)

        XCTAssertNil(viewModel.getBackwardTime(currentTime: hugeTime))
    }

    // MARK: - getFormattedTime

    func testFormattedTimeUsesMinutesAndSecondsUnderAnHour() {
        XCTAssertEqual(viewModel.getFormattedTime(totalDuration: 0), "00:00")
        XCTAssertEqual(viewModel.getFormattedTime(totalDuration: 65), "01:05")
        XCTAssertEqual(viewModel.getFormattedTime(totalDuration: 3599), "59:59")
    }

    func testFormattedTimeAddsHoursForLongerContent() {
        XCTAssertEqual(viewModel.getFormattedTime(totalDuration: 3661), "1:01:01")
        XCTAssertEqual(viewModel.getFormattedTime(totalDuration: 86399), "23:59:59")
    }

    /// `CMTimeGetSeconds` hands back NaN for an indefinite or invalid duration, which is what
    /// the controller feeds straight into this method.
    func testFormattedTimeReturnsZeroForNonFiniteDurations() {
        XCTAssertEqual(viewModel.getFormattedTime(totalDuration: .nan), "00:00")
        XCTAssertEqual(viewModel.getFormattedTime(totalDuration: .infinity), "00:00")
        XCTAssertEqual(viewModel.getFormattedTime(totalDuration: -.infinity), "00:00")
        XCTAssertEqual(viewModel.getFormattedTime(totalDuration: CMTimeGetSeconds(.indefinite)), "00:00")
        XCTAssertEqual(viewModel.getFormattedTime(totalDuration: CMTimeGetSeconds(.invalid)), "00:00")
    }

    func testFormattedTimeReturnsZeroForNegativeDurations() {
        XCTAssertEqual(viewModel.getFormattedTime(totalDuration: -1), "00:00")
    }
}
