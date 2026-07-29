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
        $0.setTitle("A-B", for: .normal)
        $0.titleLabel?.font = FontUtility.helveticaNeueBold(ofSize: 14)
        $0.setTitleColor(VideoPlayerColor(palette: .white).uiColor, for: .normal)
        $0.backgroundColor = VideoPlayerColor(palette: .red).uiColor.withAlphaComponent(0.7)
        $0.layer.cornerRadius = 4
        $0.contentEdgeInsets = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
    }

    /// Cycles through `PlaybackSpeed`; its title always shows the *current* rate, never the next one.
    private let speedButton = UIButton().configure {
        $0.setTitle(PlaybackSpeed.normal.displayText, for: .normal)
        $0.titleLabel?.font = FontUtility.helveticaNeueBold(ofSize: 14)
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
        $0.font = FontUtility.helveticaNeueRegular(ofSize: 20)
        $0.textColor = VideoPlayerColor(palette: .white).uiColor
    }
    
    private let subtitleLabel = UILabel().configure {
        $0.font = FontUtility.helveticaNeueLight(ofSize: 14)
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
    
    private let currentTimeLabel = UILabel().configure {
        $0.text = "00:00/"
        $0.font = FontUtility.helveticaNeueLight(ofSize: 14)
        $0.textColor = VideoPlayerColor(palette: .white).uiColor
    }
    
    private let totalTimeLabel = UILabel().configure {
        $0.text = "00:00"
        $0.font = FontUtility.helveticaNeueLight(ofSize: 14)
        $0.textColor = VideoPlayerColor(palette: .white).uiColor
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
        }
    }
    
    var seekBarValue: Float {
        get {
            seekBar.value
        }
        set(newValue) {
            seekBar.value = newValue
        }
    }
    
    var seekBarMaximumValue: Float {
        get {
            seekBar.maximumValue
        }
        set(newValue) {
            seekBar.maximumValue = newValue
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

    init() {
        super.init(frame: .zero)
        setupViews()
        setUpEvents()
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
        // to zero width and the AirPlay glyph would never be visible.
        routePickerView.snp.makeConstraints { make in
            make.size.equalTo(CGSize(width: CGFloat.space32, height: CGFloat.space32))
        }

        // Setting up controls in the middle
        addSubview(previousVideoButton)
        addSubview(rewindButton)
        addSubview(playPauseButton)
        addSubview(forwardButton)
        addSubview(nextVideoButton)
        
        // Setting constraints for controls in the middle
        previousVideoButton.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.trailing.equalTo(rewindButton.snp.leading).offset(-CGFloat.space16)
        }
        
        rewindButton.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.trailing.equalTo(playPauseButton.snp.leading).offset(-CGFloat.space16)
        }
        
        playPauseButton.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
        
        forwardButton.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.leading.equalTo(playPauseButton.snp.trailing).offset(CGFloat.space16)
        }
        
        nextVideoButton.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.leading.equalTo(forwardButton.snp.trailing).offset(CGFloat.space16)
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
    }
    
    private func getAttributedLiveString(isLive: Bool) -> NSMutableAttributedString {
        let dotString = "\u{2022}  "
        let attributedString = NSMutableAttributedString()
        
        let dotAttributes: [NSAttributedString.Key: Any] = [
            .font: FontUtility.helveticaNeueRegular(ofSize: 20),
            .foregroundColor: isLive ? VideoPlayerColor(palette: .red).uiColor : VideoPlayerColor(palette: .pearlWhite).uiColor,
        ]

        let liveString = NSMutableAttributedString(string: dotString + "LIVE")

        let liveAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor:VideoPlayerColor(palette: .white).uiColor,
        ]

        liveString.addAttributes(liveAttributes, range: NSRange(location: dotString.count, length: "LIVE".count))

        let dotRange = NSRange(location: 0, length: dotString.count)
        liveString.addAttributes(dotAttributes, range: dotRange)
        
        attributedString.append(liveString)
        
        return attributedString
    }
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
    }
}