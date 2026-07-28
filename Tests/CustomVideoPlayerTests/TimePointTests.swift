import AVFoundation
import XCTest
@testable import CustomVideoPlayer

/// Tests for `TimePoint`, the frame-aware timecode value type behind the A-B loop UI.
final class TimePointTests: XCTestCase {
    // MARK: - Conversion

    func testToCMTimeSumsComponents() {
        let point = TimePoint(hours: 1, minutes: 2, seconds: 3, frameRate: 30)

        XCTAssertEqual(CMTimeGetSeconds(point.toCMTime()), 3723, accuracy: 0.001)
    }

    func testFramesContributeAFractionOfASecond() {
        let point = TimePoint(seconds: 1, frames: 15, frameRate: 30)

        XCTAssertEqual(CMTimeGetSeconds(point.toCMTime()), 1.5, accuracy: 0.001)
    }

    /// The same frame number means a different wall-clock offset at a different rate —
    /// this is the whole reason `TimePoint` carries its own frame rate.
    func testFrameOffsetDependsOnFrameRate() {
        let at30 = TimePoint(frames: 12, frameRate: 30).toCMTime()
        let at24 = TimePoint(frames: 12, frameRate: 24).toCMTime()

        XCTAssertEqual(CMTimeGetSeconds(at30), 0.4, accuracy: 0.001)
        XCTAssertEqual(CMTimeGetSeconds(at24), 0.5, accuracy: 0.001)
    }

    func testInitFromCMTimeSplitsIntoComponents() {
        let time = CMTime(seconds: 3723.5, preferredTimescale: 600)

        let point = TimePoint(from: time, frameRate: 30)

        XCTAssertEqual(point.hours, 1)
        XCTAssertEqual(point.minutes, 2)
        XCTAssertEqual(point.seconds, 3)
        XCTAssertEqual(point.frames, 15)
    }

    // MARK: - Formatting

    func testToStringUsesZeroPaddedTimecode() {
        let point = TimePoint(hours: 1, minutes: 2, seconds: 3, frames: 4, frameRate: 30)

        XCTAssertEqual(point.toString(), "01:02:03:04")
    }

    func testToStringPadsZeroValues() {
        XCTAssertEqual(TimePoint(frameRate: 30).toString(), "00:00:00:00")
    }

    // MARK: - Parsing

    func testParseReadsAllFourFields() {
        let point = TimePoint.parse("01:02:03:04", frameRate: 30)

        XCTAssertEqual(point?.hours, 1)
        XCTAssertEqual(point?.minutes, 2)
        XCTAssertEqual(point?.seconds, 3)
        XCTAssertEqual(point?.frames, 4)
    }

    func testParseRoundTripsThroughToString() {
        let original = TimePoint(hours: 2, minutes: 34, seconds: 56, frames: 7, frameRate: 30)

        let reparsed = TimePoint.parse(original.toString(), frameRate: 30)

        XCTAssertEqual(reparsed, original)
    }

    func testParseRejectsOutOfRangeComponents() {
        XCTAssertNil(TimePoint.parse("00:60:00:00", frameRate: 30), "Minutes must be < 60.")
        XCTAssertNil(TimePoint.parse("00:00:60:00", frameRate: 30), "Seconds must be < 60.")
        XCTAssertNil(TimePoint.parse("00:00:00:30", frameRate: 30), "Frames must be < the frame rate.")
        XCTAssertNil(TimePoint.parse("-1:00:00:00", frameRate: 30), "Negative values are invalid.")
    }

    func testParseRejectsMalformedInput() {
        XCTAssertNil(TimePoint.parse("", frameRate: 30))
        XCTAssertNil(TimePoint.parse("00:00:00", frameRate: 30), "Too few fields.")
        XCTAssertNil(TimePoint.parse("00:00:00:00:00", frameRate: 30), "Too many fields.")
        XCTAssertNil(TimePoint.parse("aa:bb:cc:dd", frameRate: 30), "Non-numeric fields.")
    }

    /// Frame 29 is valid at 30fps but not at 24fps — the bound tracks the supplied rate.
    func testParseFrameBoundFollowsFrameRate() {
        XCTAssertNotNil(TimePoint.parse("00:00:00:29", frameRate: 30))
        XCTAssertNil(TimePoint.parse("00:00:00:29", frameRate: 24))
    }

    // MARK: - Codable

    func testEncodesAndDecodesLosslessly() throws {
        let original = TimePoint(hours: 1, minutes: 2, seconds: 3, frames: 4, frameRate: 29.97)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TimePoint.self, from: data)

        XCTAssertEqual(decoded, original)
    }
}

/// Tests for the loop and segment value types built on `TimePoint`.
final class ABLoopModelTests: XCTestCase {
    private func point(_ seconds: Int) -> TimePoint {
        TimePoint(seconds: seconds, frameRate: 30)
    }

    func testLoopDurationIsTheSpanBetweenPoints() {
        let loop = ABLoop(pointA: point(10), pointB: point(25))

        XCTAssertEqual(CMTimeGetSeconds(loop.duration()), 15, accuracy: 0.001)
    }

    func testLoopContainsOnlyTimesWithinItsRange() {
        let loop = ABLoop(pointA: point(10), pointB: point(20))

        XCTAssertTrue(loop.contains(CMTime(seconds: 15, preferredTimescale: 600)))
        XCTAssertFalse(loop.contains(CMTime(seconds: 5, preferredTimescale: 600)))
        XCTAssertFalse(loop.contains(CMTime(seconds: 25, preferredTimescale: 600)))
    }

    func testNextSegmentFollowsPlaybackOrder() {
        let first = PlaybackSegment(startPoint: point(0), endPoint: point(5), order: 0)
        let second = PlaybackSegment(startPoint: point(10), endPoint: point(15), order: 1)
        let playlist = SegmentPlaylist(
            name: "Run",
            segments: [first, second],
            videoIdentifier: "video"
        )

        XCTAssertEqual(playlist.nextSegment(after: first), second)
    }

    func testNextSegmentStopsAtTheEndWhenNotLooping() {
        let first = PlaybackSegment(startPoint: point(0), endPoint: point(5), order: 0)
        let last = PlaybackSegment(startPoint: point(10), endPoint: point(15), order: 1)
        let playlist = SegmentPlaylist(
            name: "Run",
            segments: [first, last],
            videoIdentifier: "video",
            isLooping: false
        )

        XCTAssertNil(playlist.nextSegment(after: last))
    }

    func testNextSegmentWrapsToTheStartWhenLooping() {
        let first = PlaybackSegment(startPoint: point(0), endPoint: point(5), order: 0)
        let last = PlaybackSegment(startPoint: point(10), endPoint: point(15), order: 1)
        let playlist = SegmentPlaylist(
            name: "Run",
            segments: [first, last],
            videoIdentifier: "video",
            isLooping: true
        )

        XCTAssertEqual(playlist.nextSegment(after: last), first)
    }

    func testTotalDurationSumsEverySegment() {
        let playlist = SegmentPlaylist(
            name: "Run",
            segments: [
                PlaybackSegment(startPoint: point(0), endPoint: point(5), order: 0),
                PlaybackSegment(startPoint: point(10), endPoint: point(20), order: 1),
            ],
            videoIdentifier: "video"
        )

        XCTAssertEqual(CMTimeGetSeconds(playlist.totalDuration()), 15, accuracy: 0.001)
    }
}
