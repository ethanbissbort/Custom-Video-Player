import XCTest
@testable import CustomVideoPlayer

/// Tests for the HLS master-playlist parser that drives the quality selection menu.
final class M3U8HelperTests: XCTestCase {
    private var helper: M3u8Helper!

    override func setUp() {
        super.setUp()
        helper = M3u8Helper()
    }

    override func tearDown() {
        helper = nil
        super.tearDown()
    }

    private func qualities(for manifest: String) -> [VideoQuality] {
        helper.fetchSupportedVideoQualities(with: Data(manifest.utf8))
    }

    // MARK: - Parsing

    func testParsesBitrateAndResolutionForEachVariant() {
        let manifest = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360
        low.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=2560000,RESOLUTION=1280x720
        high.m3u8
        """

        let result = qualities(for: manifest)

        // "Auto" is always prepended, so two variants yield three entries.
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result.map(\.resolution), ["Auto", "720p", "360p"])
        XCTAssertEqual(result[1].bitrate, 2_560_000)
        XCTAssertEqual(result[2].bitrate, 800_000)
    }

    func testSortsVariantsByDescendingBitrate() {
        let manifest = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=400000,RESOLUTION=426x240
        a.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080
        b.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=1200000,RESOLUTION=854x480
        c.m3u8
        """

        let result = qualities(for: manifest)

        XCTAssertEqual(result.map(\.resolution), ["Auto", "1080p", "480p", "240p"])
    }

    func testAlwaysOffersAnAutoOptionFirst() {
        let result = qualities(for: """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360
        low.m3u8
        """)

        XCTAssertEqual(result.first?.resolution, "Auto")
        XCTAssertEqual(result.first?.bitrate, .greatestFiniteMagnitude)
    }

    /// Regression test: sorting used a non-strict (`>=`) comparator, which violates the
    /// strict weak ordering Swift's sort requires and can trap at runtime once several
    /// variants share a bitrate.
    func testHandlesVariantsThatShareABitrate() {
        var manifest = "#EXTM3U\n"
        for height in [1080, 720, 576, 480, 360, 240] {
            manifest += "#EXT-X-STREAM-INF:BANDWIDTH=1500000,RESOLUTION=1280x\(height)\n"
            manifest += "v\(height).m3u8\n"
        }

        let result = qualities(for: manifest)

        XCTAssertEqual(result.count, 7, "Auto plus six equal-bitrate variants.")
        XCTAssertEqual(result.first?.resolution, "Auto")
    }

    /// Regression test: rows were split on "\n" only, leaving a trailing "\r" that made
    /// the final attribute on each line unparseable.
    func testParsesManifestsWithWindowsLineEndings() {
        let manifest = "#EXTM3U\r\n"
            + "#EXT-X-STREAM-INF:RESOLUTION=1280x720,BANDWIDTH=2560000\r\n"
            + "high.m3u8\r\n"

        let result = qualities(for: manifest)

        XCTAssertEqual(result.count, 2, "The variant must survive CRLF line endings.")
        XCTAssertEqual(result[1].bitrate, 2_560_000)
    }

    func testKeepsTheHighestBitrateWhenAResolutionRepeats() {
        let manifest = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=1000000,RESOLUTION=1280x720
        a.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=3000000,RESOLUTION=1280x720
        b.m3u8
        """

        let result = qualities(for: manifest)

        XCTAssertEqual(result.count, 2, "Duplicate resolutions collapse to one entry.")
        XCTAssertEqual(result[1].bitrate, 3_000_000)
    }

    // MARK: - Malformed input

    func testIgnoresVariantsMissingAnAttribute() {
        let manifest = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=800000
        no-resolution.m3u8
        #EXT-X-STREAM-INF:RESOLUTION=640x360
        no-bandwidth.m3u8
        """

        XCTAssertEqual(qualities(for: manifest).map(\.resolution), ["Auto"])
    }

    func testReturnsOnlyAutoForNonManifestContent() {
        // A 404 HTML body still reaches the parser today, because the HTTP status is
        // never checked. It must not yield bogus quality entries.
        let result = qualities(for: "<html><body>404 Not Found</body></html>")

        XCTAssertEqual(result.map(\.resolution), ["Auto"])
    }

    func testReturnsOnlyAutoForEmptyData() {
        XCTAssertEqual(helper.fetchSupportedVideoQualities(with: Data()).map(\.resolution), ["Auto"])
    }
}
