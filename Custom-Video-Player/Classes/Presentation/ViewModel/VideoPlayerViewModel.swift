import AVFoundation

enum PlayerState {
    case play
    case pause
}

/// Protocol for handling video player delegate methods.
protocol VideoPlayerDelegate: AnyObject {
    func didFinishFetchingVideoQualityInformationWithSuccess()
    func didFinishFetchingVideoQualityInformationWithFailure()
}

/// ViewModel for the video player.
public class VideoPlayerViewModel {
    // MARK: - Properties

    private let seekDuration: Float64 = 15
    var playerState: PlayerState = .pause
    var config: VideoPlayerConfig
    private let useCase: VideoPlayerUseCase
    private var playbackQualities: [VideoQuality]?
    var playbackQualityStrings: [String]?
    weak var delegate: VideoPlayerDelegate?
    
    /// The currently selected video, if the playlist and index are valid.
    private var currentVideo: Video? {
        guard let videos = config.playlist.videos, !videos.isEmpty else { return nil }
        let index = config.playlist.currentVideoIndex ?? 0
        guard index >= 0, index < videos.count else { return nil }
        return videos[index]
    }

    /// URL of the current video.
    var url: URL? {
        guard let url = currentVideo?.url else { return nil }
        return URL(string: url)
    }

    /// Indicates if the current content is live.
    var isLiveContent: Bool? {
        return currentVideo?.isLiveContent
    }
    
    /// Indicates if the previous button is enabled.
    var isPreviousButtonEnabled: Bool {
        let currentVideoIndex = config.playlist.currentVideoIndex ?? 0
        if currentVideoIndex - 1 >= 0 {
            return true
        }
        return false
    }
    
    /// Indicates if the next button is enabled.
    var isNextButtonEnabled: Bool {
        let currentVideoIndex = config.playlist.currentVideoIndex ?? 0
        if currentVideoIndex + 1 == config.playlist.videos?.count {
            return false
        }
        return true
    }

    /// Title label text for the current video.
    var titleLabelText: String {
        return config.playlist.title
    }
    
    /// Subtitle label text for the current video.
    var subtitleLabelText: String? {
        return currentVideo?.title
    }
    
    /// Initializes the video player view model.
    ///
    /// - Parameters:
    ///   - useCase: Video player use case.
    ///   - config: Video player configuration.
    public init(
        useCase: VideoPlayerUseCase,
        config: VideoPlayerConfig
    ) {
        self.useCase = useCase
        self.config = config
    }
    
    // MARK: - AVPlayer Time
    
    /// Calculates the time for seeking forward in the video.
    ///
    /// Returns `nil` when the current time is not a usable number — an indefinite or invalid
    /// `CMTime` is reported while the player has no ready item (for example between
    /// `replaceCurrentItem(with: nil)` and the replacement becoming ready), and converting the
    /// resulting NaN to `Int64` would trap.
    ///
    /// - Parameters:
    ///   - currentTime: Current time of the video.
    ///   - duration: Duration of the video.
    /// - Returns: Time for seeking forward, or `nil` when it cannot be computed.
    func getForwardTime(currentTime: CMTime, duration: CMTime) -> CMTime? {
        let playerCurrentTime = CMTimeGetSeconds(currentTime)
        guard playerCurrentTime.isFinite, playerCurrentTime >= 0 else { return nil }

        let totalDuration = CMTimeGetSeconds(duration)
        let newTime = playerCurrentTime + seekDuration

        // Live streams report an indefinite duration, so there is nothing to clamp against;
        // seek ahead and let the player pin the request to its seekable range.
        guard totalDuration.isFinite, totalDuration >= 0 else {
            return makeTime(seconds: newTime)
        }

        if newTime < totalDuration {
            return makeTime(seconds: newTime)
        }
        return makeTime(seconds: totalDuration)
    }

    /// Calculates the time for seeking backward in the video.
    ///
    /// Returns `nil` when the current time is not a usable number, for the same reason as
    /// `getForwardTime(currentTime:duration:)`.
    ///
    /// - Parameter currentTime: Current time of the video.
    /// - Returns: Time for seeking backward, or `nil` when it cannot be computed.
    func getBackwardTime(currentTime: CMTime) -> CMTime? {
        let playerCurrentTime = CMTimeGetSeconds(currentTime)
        guard playerCurrentTime.isFinite else { return nil }

        var newTime = playerCurrentTime - seekDuration

        if newTime < 0 {
            newTime = 0
        }
        return makeTime(seconds: newTime)
    }

    /// Builds a millisecond-precision `CMTime` from a number of seconds.
    ///
    /// `Int64(_:)` traps on NaN, on infinities and on values outside `Int64`'s range, so every
    /// conversion is range-checked first.
    ///
    /// - Parameter seconds: The number of seconds to represent.
    /// - Returns: The corresponding `CMTime`, or `nil` when the value cannot be represented.
    private func makeTime(seconds: Float64) -> CMTime? {
        let milliseconds = seconds * 1000
        // 9.0e18 is comfortably below Int64.max (~9.223e18) and exactly representable as a Double.
        guard milliseconds.isFinite, abs(milliseconds) < 9.0e18 else { return nil }
        return CMTimeMake(value: Int64(milliseconds), timescale: 1000)
    }

    /// Formats the total duration of the video.
    ///
    /// - Parameter totalDuration: Total duration of the video.
    /// - Returns: Formatted string representing the duration.
    func getFormattedTime(totalDuration: Double) -> String {
        // Guard against non-finite values (e.g. an indefinite duration on a live stream, or the
        // NaN reported while no item is ready), which would trap when converted to Int.
        guard totalDuration.isFinite, totalDuration >= 0 else {
            return "00:00"
        }
        let hours = Int(totalDuration.truncatingRemainder(dividingBy: 86400) / 3600)
        let minutes = Int(totalDuration.truncatingRemainder(dividingBy: 3600) / 60)
        let seconds = Int(totalDuration.truncatingRemainder(dividingBy: 60))

        if hours > 0 {
            return String(format: "%i:%02i:%02i", hours, minutes, seconds)
        }
        return String(format: "%02i:%02i", minutes, seconds)
    }
    
    // MARK: - Video Quality
    
    /// Fetches supported video qualities.
    func fetchSupportedVideoQualites() {
        guard let url = url else { return }
        let helper = M3u8Helper()
        useCase.getM3U8Config(videoURL: url, completion: { [weak self] result in
            guard let self = self else { return }
            switch result {
            case let .success(data):
                self.playbackQualities = helper.fetchSupportedVideoQualities(with: data)
                self.playbackQualityStrings = self.playbackQualities?.map(\.resolution)
                self.delegate?.didFinishFetchingVideoQualityInformationWithSuccess()
            case .failure:
                self.delegate?.didFinishFetchingVideoQualityInformationWithFailure()
            }
        })
    }
    
    /// Fetches the playback bitrate for a given index.
    ///
    /// - Parameter index: Index of the selected quality.
    /// - Returns: Bitrate of the selected quality.
    func fetchPlaybackBitrate(for index: Int) -> Double? {
        guard let playbackQualities = playbackQualities, index >= 0, index < playbackQualities.count else { return nil }
        return playbackQualities[index].bitrate
    }
}