import AVKit
import UIKit
import SnapKit

/// Delegate protocol for handling player control actions.
@objc protocol PlayerControlsViewDelegate {
    func seekForward()
    func seekBackward()
    func togglePlayPause()
    func playPreviousVideo()
    func playNextVideo()
    func goBack()
    func sliderValueChanged(slider: UISlider, event: UIEvent)
    func switchSubtitles()
    func openSettings()
    func seekToLive()
    func openABLoopManager()
    /// Reports the rate the user picked with the speed button.
    ///
    /// The receiver must treat this as a *selection*, not as a command to play: assigning a
    /// non-zero `AVPlayer.rate` starts playback, so a speed chosen while paused has to be
    /// remembered and applied on the next resume.
    ///
    /// - Parameter rate: The newly selected playback rate, e.g. `0.75` or `1.5`.
    func didChangePlaybackSpeed(to rate: Float)
    /// Starts Picture-in-Picture, or stops it when it is already running.
    func togglePictureInPicture()
}

/// The playback rates the speed button cycles through, in the order it cycles them.
///
/// Modelled as an enum rather than a bare `[Float]` so the cycle has a single source of truth:
/// `next` derives the wrap-around from `allCases`, which means adding a rate here is the only
/// edit needed to add it to the control.
enum PlaybackSpeed: Float, CaseIterable {
    case half = 0.5
    case threeQuarters = 0.75
    case normal = 1.0
    case fiveQuarters = 1.25
    case threeHalves = 1.5
    case double = 2.0

    /// The next rate in the cycle, wrapping from the fastest back to the slowest.
    var next: PlaybackSpeed {
        let all = PlaybackSpeed.allCases
        guard let index = all.firstIndex(of: self) else { return .normal }
        return all[(index + 1) % all.count]
    }

    /// Short label shown on the speed button.
    ///
    /// Spelled out per case rather than formatted numerically so that `1.0` reads as `"1x"`
    /// while `0.75` keeps both decimals — a single format string cannot do both.
    var displayText: String {
        switch self {
        case .half: return "0.5x"
        case .threeQuarters: return "0.75x"
        case .normal: return "1x"
        case .fiveQuarters: return "1.25x"
        case .threeHalves: return "1.5x"
        case .double: return "2x"
        }
    }
}

/// Custom view for player controls.
class PlayerControlsView: UIView {
    weak var delegate: PlayerControlsViewDelegate?
    
    // MARK: - Controls on Top
    
    private let backButton = UIButton().configure {
        $0.setImage(VideoPlayerImage.backButton.uiImage, for: .normal)
    }
    
    private let subtitleButton = UIButton().configure {
        $0.setImage(VideoPlayerImage.subtitlesButton.uiImage, for: .normal)
    }
    
    private let settingsButton = UIButton().configure {
        $0.setImage(VideoPlayerImage.settingsButton.uiImage, for: .normal)
    }

    private let abLoopButton = UIButton().configure {
        $0.setTitle(CVPLocalized("player.abLoop", value: "A-B", comment: "Title of the A-B loop button."), for: .normal)
        $0.titleLabel?.font = UIFontMetrics(forTextStyle: .footnote)
            .scaledFont(for: FontUtility.helveticaNeueBold(ofSize: 14))
        $0.titleLabel?.adjustsFontForContentSizeCategory = true
        $0.setTitleColor(VideoPlayerColor(palette: .white).uiColor, for: .normal)
        $0.backgroundColor = VideoPlayerColor(palette: .red).uiColor.withAlphaComponent(0.7)
        $0.layer.cornerRadius = 4
        $0.contentEdgeInsets = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
    }

    /// Cycles through `PlaybackSpeed`; its title always shows the *current* rate, never the next one.
    private let speedButton = UIButton().configure {
        $0.setTitle(PlaybackSpeed.normal.displayText, for: .normal)
        $0.titleLabel?.font = UIFontMetrics(forTextStyle: .footnote)
            .scaledFont(for: FontUtility.helveticaNeueBold(ofSize: 14))
        $0.titleLabel?.adjustsFontForContentSizeCategory = true
        $0.setTitleColor(VideoPlayerColor(palette: .white).uiColor, for: .normal)
        $0.backgroundColor = VideoPlayerColor(palette: .black, alpha: 0.4).uiColor
        $0.layer.cornerRadius = 4
        $0.contentEdgeInsets = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
    }

    /// Hidden until the controller confirms that Picture-in-Picture is supported *and* that a
    /// controller could actually be built over the current player layer.
    private let pictureInPictureButton = UIButton().configure {
        $0.setImage(UIImage(systemName: "pip.enter"), for: .normal)
        $0.tintColor = VideoPlayerColor(palette: .white).uiColor
        $0.isHidden = true
        $0.isEnabled = false
    }

    /// The system AirPlay route picker. It talks to the shared route system directly, so it needs
    /// no delegate and no wiring to the `AVPlayer` beyond `allowsExternalPlayback`.
    private let routePickerView = AVRoutePickerView().configure {
        $0.tintColor = VideoPlayerColor(palette: .white).uiColor
        $0.activeTintColor = VideoPlayerColor(palette: .red).uiColor
        $0.prioritizesVideoDevices = true
    }

    /// Every control in the top-right corner, in left-to-right order.
    ///
    /// A stack rather than a chain of `trailing`-to-`leading` constraints because several of these
    /// are conditionally hidden (Picture-in-Picture where unsupported, the quality button when no
    /// variants were found, the A-B and speed buttons on live streams). A `UIStackView` collapses
    /// hidden arranged subviews, so hiding one no longer leaves a hole in the row.
    private lazy var topRightControlsStack = UIStackView(arrangedSubviews: [
        speedButton,
        abLoopButton,
        pictureInPictureButton,
        routePickerView,
        subtitleButton,
        settingsButton,
    ]).configure {
        $0.axis = .horizontal
        $0.alignment = .center
        $0.spacing = CGFloat.space8
    }

    // MARK: - Controls on Middle
    
    private let previousVideoButton = UIButton().configure {
        $0.setImage(VideoPlayerImage.previousVideoButton.uiImage, for: .normal)
    }
    
    private let rewindButton = UIButton().configure {
        $0.setImage(VideoPlayerImage.rewindButton.uiImage, for: .normal)
    }
    
    private let playPauseButton = UIButton().configure {
        $0.setImage(VideoPlayerImage.pauseButton.uiImage, for: .normal)
    }
    
    private let forwardButton = UIButton().configure {
        $0.setImage(VideoPlayerImage.forwardButton.uiImage, for: .normal)
    }
    
    private let nextVideoButton = UIButton().configure {
        $0.setImage(VideoPlayerImage.nextVideoButton.uiImage, for: .normal)
    }
    
    // MARK: - Controls on Bottom
    
    private let titleLabel = UILabel().configure {
        $0.font = UIFontMetrics(forTextStyle: .title3)
            .scaledFont(for: FontUtility.helveticaNeueRegular(ofSize: 20))
        $0.adjustsFontForContentSizeCategory = true
        $0.textColor = VideoPlayerColor(palette: .white).uiColor
    }

    private let subtitleLabel = UILabel().configure {
        $0.font = UIFontMetrics(forTextStyle: .subheadline)
            .scaledFont(for: FontUtility.helveticaNeueLight(ofSize: 14))
        $0.adjustsFontForContentSizeCategory = true
        $0.textColor = VideoPlayerColor(palette: .pearlWhite).uiColor
    }
    
    private let seekBar = UISlider().configure { seekBar in
        seekBar.maximumTrackTintColor = VideoPlayerColor(palette: .pearlWhite).uiColor
        seekBar.minimumTrackTintColor = VideoPlayerColor(palette: .red).uiColor
        seekBar.minimumValue = 0
        seekBar.setThumbImage(nil, for: .normal)
        let thumbSize = CGSize(width: CGFloat.space12, height: CGFloat.space12)
        let thumbImage = UIGraphicsImageRenderer(size: thumbSize).image { _ in
            VideoPlayerColor(palette: .red).uiColor.setFill()
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: thumbSize)).fill()
        }
        seekBar.setThumbImage(thumbImage, for: .normal)
    }
    
    /// Elapsed time, shown next to `totalTimeLabel`.
    ///
    /// Hidden from VoiceOver: "00:00/" is read out as a bare pair of numbers followed by a slash,
    /// and the seek bar already carries the same information spelled out as spoken time.
    private let currentTimeLabel = UILabel().configure {
        $0.text = "00:00/"
        $0.font = UIFontMetrics(forTextStyle: .footnote)
            .scaledFont(for: FontUtility.helveticaNeueLight(ofSize: 14))
        $0.adjustsFontForContentSizeCategory = true
        $0.textColor = VideoPlayerColor(palette: .white).uiColor
        $0.isAccessibilityElement = false
    }

    /// Total duration. Hidden from VoiceOver for the same reason as `currentTimeLabel`.
    private let totalTimeLabel = UILabel().configure {
        $0.text = "00:00"
        $0.font = UIFontMetrics(forTextStyle: .footnote)
            .scaledFont(for: FontUtility.helveticaNeueLight(ofSize: 14))
        $0.adjustsFontForContentSizeCategory = true
        $0.textColor = VideoPlayerColor(palette: .white).uiColor
        $0.isAccessibilityElement = false
    }
    
    private let liveButton = UIButton().configure {
        $0.backgroundColor = .clear
        $0.contentEdgeInsets = UIEdgeInsets.zero
        $0.isHidden = true
        $0.isEnabled = false
    }
    
    // MARK: - Control State Setters
    
    var playPauseButtonImage: UIImage? {
        get {
            playPauseButton.currentImage
        }
        set(newValue) {
            playPauseButton.setImage(newValue, for: .normal)
            updatePlayPauseAccessibilityLabel()
        }
    }

    var seekBarValue: Float {
        get {
            seekBar.value
        }
        set(newValue) {
            seekBar.value = newValue
            updateSeekBarAccessibilityValue()
        }
    }

    var seekBarMaximumValue: Float {
        get {
            seekBar.maximumValue
        }
        set(newValue) {
            seekBar.maximumValue = newValue
            updateSeekBarAccessibilityValue()
        }
    }
    
    var currentTimeLabelText: String? {
        get {
            currentTimeLabel.text
        }
        set(newValue) {
            currentTimeLabel.text = newValue
        }
    }
    
    var totalTimeLabelText: String? {
        get {
            totalTimeLabel.text
        }
        set(newValue) {
            totalTimeLabel.text = newValue
        }
    }
    
    var titleLabelText: String? {
        get {
            titleLabel.text
        }
        set(newValue) {
            titleLabel.text = newValue
        }
    }
    
    var subtitleLabelText: String? {
        get {
            subtitleLabel.text
        }
        set(newValue) {
            subtitleLabel.text = newValue
        }
    }
    
    var previousVideoButtonState: Bool {
        get {
            previousVideoButton.isEnabled
        }
        set(newValue) {
            previousVideoButton.isEnabled = newValue
        }
    }
    
    var nextVideoButtonState: Bool {
        get {
            nextVideoButton.isEnabled
        }
        set(newValue) {
            nextVideoButton.isEnabled = newValue
        }
    }
    
    var isPlaying: Bool = false {
        didSet {
            playPauseButtonImage = isPlaying ? VideoPlayerImage.pauseButton.uiImage : VideoPlayerImage.playButton.uiImage
        }
    }

    /// The rate currently shown on the speed button.
    ///
    /// Read-only from the outside: the control owns the cycle, and the player follows it via
    /// `PlayerControlsViewDelegate.didChangePlaybackSpeed(to:)`.
    private(set) var playbackSpeed: PlaybackSpeed = .normal {
        didSet {
            speedButton.setTitle(playbackSpeed.displayText, for: .normal)
            updateSpeedButtonAccessibilityLabel()
        }
    }

    /// `true` while the Picture-in-Picture button is on screen and tappable.
    var isPictureInPictureButtonAvailable: Bool {
        !pictureInPictureButton.isHidden && pictureInPictureButton.isEnabled
    }

    /// `true` while the A-B loop button is on screen and tappable.
    ///
    /// Loop evaluation is gated behind `!isLiveContent` in the controller, so on a live stream
    /// this must report `false` — otherwise the button is fully interactive and silently does
    /// nothing.
    var isABLoopButtonAvailable: Bool {
        !abLoopButton.isHidden && abLoopButton.isEnabled
    }

    private let dynamicSpacing: CGFloat = UIScreen.main.bounds.height * 0.055

    /// The visible "LIVE" badge text, shared by the badge itself and its VoiceOver label.
    private static var liveText: String {
        CVPLocalized("player.live", value: "LIVE", comment: "Badge shown on a live stream.")
    }

    /// What tapping the "LIVE" badge does, announced as a VoiceOver hint.
    private static var seekToLiveHint: String {
        CVPLocalized(
            "player.seekToLive.accessibility",
            value: "Jump to live",
            comment: "VoiceOver hint for the badge that seeks back to the live edge."
        )
    }

    /// The smallest hit area the HIG allows for a control, in points.
    ///
    /// The image buttons carry no size constraints of their own, so they inherit the intrinsic
    /// size of their PDF artwork — well under this on every asset in the library.
    private static let minimumTouchTarget: CGFloat = 44

    init() {
        super.init(frame: .zero)
        setupViews()
        setUpEvents()
        setUpAccessibility()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Player Control Views

extension PlayerControlsView {
    private func setupViews() {
        // Setting up controls on top
        addSubview(backButton)
        addSubview(topRightControlsStack)

        // Setting constraints for controls on top
        backButton.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(CGFloat.space24)
            make.leading.equalToSuperview().offset(dynamicSpacing)
        }

        topRightControlsStack.snp.makeConstraints { make in
            make.top.equalTo(backButton.snp.top)
            make.trailing.equalToSuperview().offset(-dynamicSpacing)
        }

        // `AVRoutePickerView` has no intrinsic content size, so inside a stack it would collapse
        // to zero width and the AirPlay glyph would never be visible. Sized to the minimum touch
        // target rather than to the glyph, like every other control in the row.
        routePickerView.snp.makeConstraints { make in
            make.size.equalTo(CGSize(width: PlayerControlsView.minimumTouchTarget,
                                     height: PlayerControlsView.minimumTouchTarget))
        }

        // Setting up controls in the middle
        addSubview(previousVideoButton)
        addSubview(rewindButton)
        addSubview(playPauseButton)
        addSubview(forwardButton)
        addSubview(nextVideoButton)

        // The transport row is the one part of the layout that must *not* mirror: "previous,
        // rewind, play, forward, next" reads left-to-right in every locale, the same way it does
        // on physical transport controls. `forceLeftToRight` keeps the glyphs themselves from
        // being mirrored, and `left`/`right` — rather than `leading`/`trailing` — keeps the order
        // fixed no matter which direction the constraints are resolved in.
        [previousVideoButton, rewindButton, playPauseButton, forwardButton, nextVideoButton]
            .forEach { $0.semanticContentAttribute = .forceLeftToRight }

        // Setting constraints for controls in the middle
        previousVideoButton.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.right.equalTo(rewindButton.snp.left).offset(-CGFloat.space16)
        }

        rewindButton.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.right.equalTo(playPauseButton.snp.left).offset(-CGFloat.space16)
        }

        playPauseButton.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }

        forwardButton.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.left.equalTo(playPauseButton.snp.right).offset(CGFloat.space16)
        }

        nextVideoButton.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.left.equalTo(forwardButton.snp.right).offset(CGFloat.space16)
        }

        // Setting up controls at the bottom
        addSubview(titleLabel)
        addSubview(subtitleLabel)
        addSubview(seekBar)
        addSubview(currentTimeLabel)
        addSubview(totalTimeLabel)
        addSubview(liveButton)
        
        // Setting constraints for controls at the bottom
        titleLabel.snp.makeConstraints { make in
            make.bottom.equalTo(subtitleLabel.snp.top).offset(-CGFloat.space4)
            make.leading.equalTo(seekBar.snp.leading)
            make.trailing.equalTo(seekBar.snp.trailing)
        }
        
        subtitleLabel.snp.makeConstraints { make in
            make.bottom.equalTo(seekBar.snp.top).offset(-CGFloat.space12)
            make.leading.equalTo(seekBar.snp.leading)
            make.trailing.equalTo(seekBar.snp.trailing)
        }
        
        // The bottom row is aligned to the *stack's* trailing edge rather than to
        // `settingsButton`'s. The stack collapses hidden arranged subviews, so anchoring to any
        // individual button would drag the seek bar leftwards whenever that button is hidden
        // (quality-fetch failure, live content, unsupported Picture-in-Picture).
        seekBar.snp.makeConstraints { make in
            make.leading.equalTo(backButton.snp.leading)
            make.trailing.equalTo(topRightControlsStack.snp.trailing)
            make.bottom.equalToSuperview().offset(-CGFloat.space24)
            make.height.equalTo(CGFloat.space2)
        }

        currentTimeLabel.snp.makeConstraints { make in
            make.trailing.equalTo(totalTimeLabel.snp.leading)
            make.bottom.equalTo(totalTimeLabel.snp.bottom)
        }

        totalTimeLabel.snp.makeConstraints { make in
            make.trailing.equalTo(topRightControlsStack.snp.trailing)
            make.bottom.equalTo(seekBar.snp.top).offset(-CGFloat.space12)
        }

        liveButton.snp.makeConstraints { make in
            make.trailing.equalTo(topRightControlsStack.snp.trailing)
            make.bottom.equalTo(seekBar.snp.top).offset(-CGFloat.space12)
        }
        
        liveButton.setAttributedTitle(getAttributedLiveString(isLive: true), for: .normal)

        // A *minimum* rather than a fixed size: the artwork keeps its natural size and the
        // tappable region grows around it, which also leaves room for the title buttons to grow
        // with the user's preferred content size instead of clipping their text.
        [
            backButton,
            subtitleButton,
            settingsButton,
            abLoopButton,
            speedButton,
            pictureInPictureButton,
            previousVideoButton,
            rewindButton,
            playPauseButton,
            forwardButton,
            nextVideoButton,
            liveButton,
        ].forEach { control in
            control.snp.makeConstraints { make in
                make.width.greaterThanOrEqualTo(PlayerControlsView.minimumTouchTarget)
                make.height.greaterThanOrEqualTo(PlayerControlsView.minimumTouchTarget)
            }
        }
    }

    private func getAttributedLiveString(isLive: Bool) -> NSMutableAttributedString {
        let dotString = "\u{2022}  "
        let liveText = PlayerControlsView.liveText
        let attributedString = NSMutableAttributedString()

        let dotAttributes: [NSAttributedString.Key: Any] = [
            // Scaled once at build time: an attributed title cannot re-scale itself the way
            // `adjustsFontForContentSizeCategory` re-scales a plain label.
            .font: UIFontMetrics(forTextStyle: .title3)
                .scaledFont(for: FontUtility.helveticaNeueRegular(ofSize: 20)),
            .foregroundColor: isLive ? VideoPlayerColor(palette: .red).uiColor : VideoPlayerColor(palette: .pearlWhite).uiColor,
        ]

        let liveString = NSMutableAttributedString(string: dotString + liveText)

        let liveAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor:VideoPlayerColor(palette: .white).uiColor,
        ]

        // Measured in UTF-16 units, because a translated label need not be plain ASCII.
        let dotLength = (dotString as NSString).length
        liveString.addAttributes(liveAttributes, range: NSRange(location: dotLength, length: (liveText as NSString).length))

        let dotRange = NSRange(location: 0, length: dotLength)
        liveString.addAttributes(dotAttributes, range: dotRange)
        
        attributedString.append(liveString)
        
        return attributedString
    }
}

// MARK: - Accessibility

extension PlayerControlsView {
    /// Names every control for VoiceOver.
    ///
    /// The image buttons are drawn from PDF assets, so without a label VoiceOver falls back to the
    /// asset file name and announces "play_button". The two *stateful* controls — play/pause and
    /// the seek bar — are handled separately, because their label and value have to be refreshed
    /// every time the state behind them changes.
    private func setUpAccessibility() {
        backButton.accessibilityLabel = CVPLocalized(
            "player.back.accessibility", value: "Back", comment: "VoiceOver label for the button that leaves the player."
        )
        subtitleButton.accessibilityLabel = CVPLocalized(
            "player.subtitles.accessibility", value: "Subtitles", comment: "VoiceOver label for the subtitle picker button."
        )
        settingsButton.accessibilityLabel = CVPLocalized(
            "player.settings.accessibility", value: "Video quality", comment: "VoiceOver label for the quality picker button."
        )
        abLoopButton.accessibilityLabel = CVPLocalized(
            "player.abLoop.accessibility", value: "A-B loop", comment: "VoiceOver label for the A-B loop button."
        )
        pictureInPictureButton.accessibilityLabel = CVPLocalized(
            "player.pictureInPicture.accessibility", value: "Picture in Picture", comment: "VoiceOver label for the PiP button."
        )
        routePickerView.accessibilityLabel = CVPLocalized(
            "player.airPlay.accessibility", value: "AirPlay", comment: "VoiceOver label for the AirPlay route picker."
        )
        previousVideoButton.accessibilityLabel = CVPLocalized(
            "player.previousVideo.accessibility", value: "Previous video", comment: "VoiceOver label for the previous-video button."
        )
        rewindButton.accessibilityLabel = CVPLocalized(
            "player.seekBackward.accessibility", value: "Skip back 15 seconds", comment: "VoiceOver label for the rewind button."
        )
        forwardButton.accessibilityLabel = CVPLocalized(
            "player.seekForward.accessibility", value: "Skip forward 15 seconds", comment: "VoiceOver label for the fast-forward button."
        )
        nextVideoButton.accessibilityLabel = CVPLocalized(
            "player.nextVideo.accessibility", value: "Next video", comment: "VoiceOver label for the next-video button."
        )
        seekBar.accessibilityLabel = CVPLocalized(
            "player.seekBar.accessibility", value: "Playback position", comment: "VoiceOver label for the seek bar."
        )

        // The badge reads as "LIVE"; what tapping it *does* belongs in the hint, and it is only
        // tappable once playback has drifted off the live edge — see `updateLiveState(with:)`.
        liveButton.accessibilityLabel = PlayerControlsView.liveText
        liveButton.accessibilityHint = PlayerControlsView.seekToLiveHint

        titleLabel.accessibilityTraits.insert(.header)

        updatePlayPauseAccessibilityLabel()
        updateSpeedButtonAccessibilityLabel()
        updateSeekBarAccessibilityValue()
    }

    /// Keeps the play/pause button's VoiceOver label in step with the glyph it is showing.
    ///
    /// This is the fix a VoiceOver user notices most: the button conveys playback state through
    /// its icon alone, so without a matching label there is no way to tell whether the video is
    /// playing. The glyph is assigned from outside through `playPauseButtonImage`, so the label
    /// has to be derived from the image rather than from a flag this view controls.
    private func updatePlayPauseAccessibilityLabel() {
        let pauseGlyph = VideoPlayerImage.pauseButton.uiImage
        let playGlyph = VideoPlayerImage.playButton.uiImage
        let showsPauseGlyph: Bool

        if pauseGlyph.isEqual(playGlyph) {
            // Neither asset resolved and both collapsed to the same empty image, so the glyph
            // carries no information — fall back to the state this view was told about.
            showsPauseGlyph = isPlaying
        } else {
            showsPauseGlyph = playPauseButton.currentImage?.isEqual(pauseGlyph) ?? isPlaying
        }

        // The label names the *action*: the pause glyph is shown while the video plays, and
        // tapping it pauses.
        playPauseButton.accessibilityLabel = showsPauseGlyph
            ? CVPLocalized("player.pause.accessibility", value: "Pause", comment: "VoiceOver label while the video is playing.")
            : CVPLocalized("player.play.accessibility", value: "Play", comment: "VoiceOver label while the video is paused.")
    }

    /// Announces the *current* rate, which the "1x"-style title only hints at visually.
    private func updateSpeedButtonAccessibilityLabel() {
        speedButton.accessibilityLabel = String(
            format: CVPLocalized(
                "player.speed.value.accessibility",
                value: "%@ speed",
                comment: "VoiceOver label for the speed button. %@ is a multiplier such as \"1.5x\"."
            ),
            playbackSpeed.displayText
        )
    }

    /// Reports the seek bar's position as spoken time.
    ///
    /// `seekBar.maximumValue` is a raw number of seconds, so the percentage VoiceOver derives from
    /// a bare `UISlider` ("47 percent") tells the listener nothing useful about where they are.
    private func updateSeekBarAccessibilityValue() {
        let elapsed = PlayerControlsView.spokenTime(seconds: Double(seekBar.value))
        let total = PlayerControlsView.spokenTime(seconds: Double(seekBar.maximumValue))
        seekBar.accessibilityValue = String(
            format: CVPLocalized(
                "player.seekBar.value.accessibility",
                value: "%1$@ of %2$@",
                comment: "VoiceOver value for the seek bar. %1$@ is the elapsed time, %2$@ the total duration."
            ),
            elapsed,
            total
        )
    }

    /// Spells `seconds` out in words — "1 minute, 5 seconds" — for VoiceOver.
    private static func spokenTime(seconds: Double) -> String {
        let interval = seconds.isFinite && seconds > 0 ? seconds : 0
        return spokenTimeFormatter.string(from: interval) ?? ""
    }

    /// Shared because `DateComponentsFormatter` is comparatively expensive to build, and the seek
    /// bar's value is refreshed on every periodic time observation.
    private static let spokenTimeFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .full
        formatter.zeroFormattingBehavior = .dropLeading
        return formatter
    }()
}

// MARK: - Player Control Events

extension PlayerControlsView {
    private func setUpEvents() {
        // Adding targets for control events
        playPauseButton.addTarget(self, action: #selector(pausePlay), for: .touchUpInside)
        forwardButton.addTarget(self, action: #selector(doForwardJump), for: .touchUpInside)
        rewindButton.addTarget(self, action: #selector(doBackwardJump), for: .touchUpInside)
        previousVideoButton.addTarget(self, action: #selector(playPreviousVideo), for: .touchUpInside)
        nextVideoButton.addTarget(self, action: #selector(playNextVideo), for: .touchUpInside)
        seekBar.addTarget(self, action: #selector(onSliderValChanged(slider:event:)), for: .valueChanged)
        backButton.addTarget(self, action: #selector(backButtonTap), for: .touchUpInside)
        subtitleButton.addTarget(self, action: #selector(subtitleButtonTap), for: .touchUpInside)
        settingsButton.addTarget(self, action: #selector(settingsButtonTap), for: .touchUpInside)
        liveButton.addTarget(self, action: #selector(seekLiveButtonTap), for: .touchUpInside)
        abLoopButton.addTarget(self, action: #selector(abLoopButtonTap), for: .touchUpInside)
        speedButton.addTarget(self, action: #selector(speedButtonTap), for: .touchUpInside)
        pictureInPictureButton.addTarget(self, action: #selector(pictureInPictureButtonTap), for: .touchUpInside)
    }
    
    // MARK: - Control Event Handlers
    
    @IBAction private func pausePlay(_: UIButton) {
        delegate?.togglePlayPause()
    }
    
    @IBAction private func doForwardJump(_: UIButton) {
        delegate?.seekForward()
    }
    
    @IBAction private func doBackwardJump(_: UIButton) {
        delegate?.seekBackward()
    }
    
    @IBAction private func playPreviousVideo(_: UIButton) {
        delegate?.playPreviousVideo()
    }
    
    @IBAction private func playNextVideo(_: UIButton) {
        delegate?.playNextVideo()
    }
    
    @IBAction private func backButtonTap(_: UIButton) {
        delegate?.goBack()
    }
    
    @IBAction private func subtitleButtonTap(_: UIButton) {
        delegate?.switchSubtitles()
    }
    
    @IBAction private func settingsButtonTap(_: UIButton) {
        delegate?.openSettings()
    }
    
    @objc private func onSliderValChanged(slider: UISlider, event: UIEvent) {
        updateSeekBarAccessibilityValue()
        delegate?.sliderValueChanged(slider: slider, event: event)
    }
    
    @IBAction private func seekLiveButtonTap() {
        delegate?.seekToLive()
    }

    @IBAction private func abLoopButtonTap(_: UIButton) {
        delegate?.openABLoopManager()
    }

    @IBAction private func speedButtonTap(_: UIButton) {
        cyclePlaybackSpeed()
    }

    @IBAction private func pictureInPictureButtonTap(_: UIButton) {
        delegate?.togglePictureInPicture()
    }

    /// Advances to the next rate in the cycle, updates the button title and reports the new rate.
    ///
    /// `internal` rather than `private` so the cycle — including its wrap-around — can be
    /// exercised without synthesising touch events.
    @discardableResult
    func cyclePlaybackSpeed() -> PlaybackSpeed {
        playbackSpeed = playbackSpeed.next
        delegate?.didChangePlaybackSpeed(to: playbackSpeed.rawValue)
        return playbackSpeed
    }
}

// MARK: - Player Control State Updation

extension PlayerControlsView {
    func disableSubtitlesButton() {
        subtitleButton.isEnabled = false
    }
    
    func unhideSettingsButton() {
        settingsButton.isHidden = false
    }
    
    func hideSettingsButton() {
        settingsButton.isHidden = true
    }
    
    /// Shows or hides the Picture-in-Picture button.
    ///
    /// - Parameter isAvailable: `true` only when `AVPictureInPictureController` is supported on
    ///   this device *and* one could be built over the current player layer.
    func setPictureInPictureAvailable(_ isAvailable: Bool) {
        pictureInPictureButton.isHidden = !isAvailable
        pictureInPictureButton.isEnabled = isAvailable
    }

    func enableLiveControls() {
        liveButton.isHidden = false
        settingsButton.isHidden = true
        subtitleButton.isHidden = true
        totalTimeLabel.isHidden = true
        currentTimeLabel.isHidden = true
        forwardButton.isHidden = true
        rewindButton.isHidden = true
        // A live stream has no fixed timeline, so both of these are inert: loop evaluation is
        // gated behind `!isLiveContent` in the controller, and a rate other than 1.0 on a live
        // edge just falls off it. Left visible they were fully interactive and did nothing.
        abLoopButton.isHidden = true
        abLoopButton.isEnabled = false
        speedButton.isHidden = true
        speedButton.isEnabled = false
    }
    
    func updateLiveState(with isLive: Bool) {
        liveButton.setAttributedTitle(getAttributedLiveString(isLive: isLive), for: .normal)
        liveButton.isEnabled = !isLive
        // Only advertise the action while the badge can actually perform it: at the live edge the
        // badge is a status indicator, not a control.
        liveButton.accessibilityHint = isLive ? nil : PlayerControlsView.seekToLiveHint
    }
}