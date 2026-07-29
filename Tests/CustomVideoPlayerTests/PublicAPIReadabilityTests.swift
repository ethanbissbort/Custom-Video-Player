import AVFoundation
import XCTest
import CustomVideoPlayer

/// Consumer-perspective smoke tests for the library's public model surface.
///
/// Unlike every other file in this target, this one uses a **plain `import`** rather than
/// `@testable import` — and that is the entire point. `@testable` raises `internal` members to
/// visible, so a `@testable` test would happily read a property that a real third-party consumer
/// cannot see. These tests compile against exactly what an app that pulls in the library gets.
///
/// The models were previously declared `public` with `public` memberwise inits but `internal`
/// stored properties, which made the library effectively write-only: you could build a `Video`
/// but never read `video.url` back. These tests construct each model through its public
/// initializer and read every property back, so if a property's access level ever narrows again
/// this file fails to **compile** — a louder and earlier signal than a failing assertion.
final class PublicAPIReadabilityTests: XCTestCase {
    // MARK: - TimePoint

    func testTimePointExposesAllComponents() {
        let point = TimePoint(hours: 1, minutes: 2, seconds: 3, frames: 4, frameRate: 25)

        XCTAssertEqual(point.hours, 1)
        XCTAssertEqual(point.minutes, 2)
        XCTAssertEqual(point.seconds, 3)
        XCTAssertEqual(point.frames, 4)
        XCTAssertEqual(point.frameRate, 25, accuracy: 0.001)
    }

    func testTimePointFromCMTimeExposesAllComponents() {
        let point = TimePoint(from: CMTime(seconds: 3723.5, preferredTimescale: 600), frameRate: 30)

        XCTAssertEqual(point.hours, 1)
        XCTAssertEqual(point.minutes, 2)
        XCTAssertEqual(point.seconds, 3)
        XCTAssertEqual(point.frames, 15)
        XCTAssertEqual(point.frameRate, 30, accuracy: 0.001)
    }

    /// The public methods have to be reachable from outside the module too, not just the properties.
    func testTimePointPublicMethodsAreReachable() {
        let point = TimePoint(hours: 1, minutes: 2, seconds: 3, frames: 4, frameRate: 30)

        XCTAssertEqual(point.toString(), "01:02:03:04")
        XCTAssertEqual(CMTimeGetSeconds(point.toCMTime()), 3723.0 + 4.0 / 30.0, accuracy: 0.001)

        let parsed = TimePoint.parse("01:02:03:04", frameRate: 30)

        XCTAssertEqual(parsed?.hours, 1)
        XCTAssertEqual(parsed?.minutes, 2)
        XCTAssertEqual(parsed?.seconds, 3)
        XCTAssertEqual(parsed?.frames, 4)
    }

    // MARK: - ABLoop

    func testABLoopExposesAllProperties() {
        let id = UUID()
        let pointA = TimePoint(seconds: 10, frameRate: 30)
        let pointB = TimePoint(seconds: 25, frameRate: 30)

        let loop = ABLoop(id: id, pointA: pointA, pointB: pointB, name: "Chorus")

        XCTAssertEqual(loop.id, id)
        XCTAssertEqual(loop.pointA, pointA)
        XCTAssertEqual(loop.pointB, pointB)
        XCTAssertEqual(loop.name, "Chorus")
        // Reading through a nested public model, which needs `TimePoint`'s properties public too.
        XCTAssertEqual(loop.pointA.seconds, 10)
        XCTAssertEqual(loop.pointB.seconds, 25)
    }

    func testABLoopOmittedNameReadsBackAsNil() {
        let loop = ABLoop(pointA: TimePoint(seconds: 1), pointB: TimePoint(seconds: 2))

        XCTAssertNil(loop.name)
    }

    func testABLoopPublicMethodsAreReachable() {
        let loop = ABLoop(pointA: TimePoint(seconds: 10, frameRate: 30),
                          pointB: TimePoint(seconds: 25, frameRate: 30))

        XCTAssertEqual(CMTimeGetSeconds(loop.duration()), 15, accuracy: 0.001)
        XCTAssertTrue(loop.contains(CMTime(seconds: 12, preferredTimescale: 600)))
        XCTAssertFalse(loop.contains(CMTime(seconds: 30, preferredTimescale: 600)))
    }

    // MARK: - PlaybackSegment

    func testPlaybackSegmentExposesAllProperties() {
        let id = UUID()
        let startPoint = TimePoint(seconds: 5, frameRate: 30)
        let endPoint = TimePoint(seconds: 20, frameRate: 30)

        let segment = PlaybackSegment(id: id,
                                      startPoint: startPoint,
                                      endPoint: endPoint,
                                      order: 2,
                                      name: "Verse")

        XCTAssertEqual(segment.id, id)
        XCTAssertEqual(segment.startPoint, startPoint)
        XCTAssertEqual(segment.endPoint, endPoint)
        XCTAssertEqual(segment.order, 2)
        XCTAssertEqual(segment.name, "Verse")
    }

    // MARK: - SegmentPlaylist

    func testSegmentPlaylistExposesAllProperties() {
        let id = UUID()
        let first = makeSegment(order: 1, startSeconds: 0, endSeconds: 5)
        let second = makeSegment(order: 2, startSeconds: 10, endSeconds: 20)

        // Passed out of order on purpose: the public init sorts by `order`, and reading
        // `segments` back is the only way a consumer can observe that.
        let playlist = SegmentPlaylist(id: id,
                                       name: "Practice",
                                       segments: [second, first],
                                       videoIdentifier: "video-1",
                                       isLooping: true)

        XCTAssertEqual(playlist.id, id)
        XCTAssertEqual(playlist.name, "Practice")
        XCTAssertEqual(playlist.videoIdentifier, "video-1")
        XCTAssertTrue(playlist.isLooping)
        XCTAssertEqual(playlist.segments.count, 2)
        XCTAssertEqual(playlist.segments.map { $0.order }, [1, 2])
        XCTAssertEqual(playlist.segments.first?.id, first.id)
    }

    /// `segments` and `isLooping` are declared `var`, so a consumer must get a public *setter*
    /// as well as a getter. This would stop compiling under `public private(set) var`.
    func testSegmentPlaylistMutablePropertiesAreSettable() {
        var playlist = SegmentPlaylist(name: "Practice",
                                       segments: [makeSegment(order: 1, startSeconds: 0, endSeconds: 5)],
                                       videoIdentifier: "video-1")

        XCTAssertFalse(playlist.isLooping)

        playlist.isLooping = true
        playlist.segments = []

        XCTAssertTrue(playlist.isLooping)
        XCTAssertTrue(playlist.segments.isEmpty)
    }

    func testSegmentPlaylistPublicMethodsAreReachable() {
        let first = makeSegment(order: 1, startSeconds: 0, endSeconds: 5)
        let second = makeSegment(order: 2, startSeconds: 10, endSeconds: 20)
        let playlist = SegmentPlaylist(name: "Practice",
                                       segments: [first, second],
                                       videoIdentifier: "video-1")

        XCTAssertEqual(playlist.nextSegment(after: first)?.id, second.id)
        XCTAssertNil(playlist.nextSegment(after: second))
        XCTAssertEqual(CMTimeGetSeconds(playlist.totalDuration()), 15, accuracy: 0.001)
    }

    // MARK: - VideoLoopData

    func testVideoLoopDataExposesAllProperties() {
        let loop = ABLoop(pointA: TimePoint(seconds: 10, frameRate: 30),
                          pointB: TimePoint(seconds: 25, frameRate: 30),
                          name: "Chorus")
        let playlist = SegmentPlaylist(name: "Practice",
                                       segments: [makeSegment(order: 1, startSeconds: 0, endSeconds: 5)],
                                       videoIdentifier: "video-1")

        let data = VideoLoopData(videoIdentifier: "video-1",
                                 abLoops: [loop],
                                 segmentPlaylists: [playlist])

        XCTAssertEqual(data.videoIdentifier, "video-1")
        XCTAssertEqual(data.abLoops.count, 1)
        XCTAssertEqual(data.segmentPlaylists.count, 1)
        // Two levels of nesting, so every model in the chain has to be readable.
        XCTAssertEqual(data.abLoops.first?.name, "Chorus")
        XCTAssertEqual(data.abLoops.first?.pointA.seconds, 10)
        XCTAssertEqual(data.segmentPlaylists.first?.name, "Practice")
        XCTAssertEqual(data.segmentPlaylists.first?.segments.first?.order, 1)
    }

    func testVideoLoopDataMutablePropertiesAreSettable() {
        var data = VideoLoopData(videoIdentifier: "video-1")

        XCTAssertTrue(data.abLoops.isEmpty)
        XCTAssertTrue(data.segmentPlaylists.isEmpty)

        data.abLoops = [ABLoop(pointA: TimePoint(seconds: 1), pointB: TimePoint(seconds: 2))]
        data.segmentPlaylists = [SegmentPlaylist(name: "Practice",
                                                 segments: [],
                                                 videoIdentifier: "video-1")]

        XCTAssertEqual(data.abLoops.count, 1)
        XCTAssertEqual(data.segmentPlaylists.count, 1)
    }

    // MARK: - Video

    func testVideoExposesAllProperties() {
        let video = Video(url: "https://example.com/stream.m3u8", title: "Episode 1", isLiveContent: true)

        XCTAssertEqual(video.url, "https://example.com/stream.m3u8")
        XCTAssertEqual(video.title, "Episode 1")
        XCTAssertEqual(video.isLiveContent, true)
    }

    func testVideoDefaultsReadBack() {
        let video = Video(url: nil)

        XCTAssertNil(video.url)
        XCTAssertNil(video.title)
        XCTAssertEqual(video.isLiveContent, false)
    }

    // MARK: - VideoPlaylist

    func testVideoPlaylistExposesAllProperties() {
        let video = Video(url: "https://example.com/stream.m3u8", title: "Episode 1")

        let playlist = VideoPlaylist(title: "Season 1", currentVideoIndex: 0, videos: [video])

        XCTAssertEqual(playlist.title, "Season 1")
        XCTAssertEqual(playlist.currentVideoIndex, 0)
        XCTAssertEqual(playlist.videos?.count, 1)
        XCTAssertEqual(playlist.videos?.first?.url, "https://example.com/stream.m3u8")
        XCTAssertEqual(playlist.videos?.first?.title, "Episode 1")
    }

    func testVideoPlaylistAcceptsNilVideosAndIndex() {
        let playlist = VideoPlaylist(title: "Empty", videos: nil)

        XCTAssertEqual(playlist.title, "Empty")
        XCTAssertNil(playlist.currentVideoIndex)
        XCTAssertNil(playlist.videos)
    }

    func testVideoPlaylistMutablePropertyIsSettable() {
        var playlist = VideoPlaylist(title: "Season 1", videos: [Video(url: "a")])

        playlist.currentVideoIndex = 2

        XCTAssertEqual(playlist.currentVideoIndex, 2)
    }

    // MARK: - VideoPlayerConfig

    func testVideoPlayerConfigExposesPlaylist() {
        let playlist = VideoPlaylist(title: "Season 1",
                                     currentVideoIndex: 1,
                                     videos: [Video(url: "a"), Video(url: "b", title: "B")])

        let config = VideoPlayerConfig(playlist: playlist)

        XCTAssertEqual(config.playlist.title, "Season 1")
        XCTAssertEqual(config.playlist.currentVideoIndex, 1)
        XCTAssertEqual(config.playlist.videos?.count, 2)
        XCTAssertEqual(config.playlist.videos?.last?.title, "B")
    }

    func testVideoPlayerConfigPlaylistIsSettable() {
        var config = VideoPlayerConfig(playlist: VideoPlaylist(title: "Season 1", videos: nil))

        config.playlist = VideoPlaylist(title: "Season 2", videos: [Video(url: "a")])

        XCTAssertEqual(config.playlist.title, "Season 2")
        XCTAssertEqual(config.playlist.videos?.count, 1)
    }

    // MARK: - Helpers

    private func makeSegment(order: Int, startSeconds: Int, endSeconds: Int) -> PlaybackSegment {
        PlaybackSegment(startPoint: TimePoint(seconds: startSeconds, frameRate: 30),
                        endPoint: TimePoint(seconds: endSeconds, frameRate: 30),
                        order: order)
    }
}
