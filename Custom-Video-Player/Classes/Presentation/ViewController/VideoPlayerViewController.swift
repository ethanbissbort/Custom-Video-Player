import UIKit
import AVKit
import AVFoundation
import os

public class VideoPlayerViewController: UIViewController {
    let viewModel: VideoPlayerViewModel
    let coordinator: VideoPlayerCoordinator
    let abLoopManager = ABLoopManager()

    /// A library must not `print` into the host app's console; route diagnostics through
    /// the unified log instead, matching `ABLoopManager`.
    private let logger = Logger(subsystem: "com.customvideoplayer", category: "VideoPlayerViewController")

    private var periodicTimeObserver: Any?
    private var didSetupControls: Bool = false
    /// Set when an audio session interruption pauses playback that was actually in progress, so
    /// that `.ended` only resumes what the interruption stopped. Without it a video the user had
    /// deliberately paused before the phone rang would start playing again on its own, because
    /// `.shouldResume` reflects the *system's* willingness to resume, not the user's intent.
    private var didPauseForInterruption: Bool = false
    private var controlsHiddenTimer: Timer?
    private let controlsHideDelay: TimeInterval = 3.0
    var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    var playerItem: AVPlayerItem?
    let playerControlsView = PlayerControlsView()
    var subtitleSelectionView: SubtitleSelectionViewController?
    var qualitySelectionView: QualitySelectionViewController?
    
    // Custom Subtitle Styling
    private let subtitleStyling = AVTextStyleRule(textMarkupAttributes: [
        kCMTextMarkupAttribute_CharacterBackgroundColorARGB as String: [0.0, 0.0, 0.0, 0.4],
        kCMTextMarkupAttribute_ForegroundColorARGB as String: [1.0, 1.0, 1.0, 1.0],
        kCMTextMarkupAttribute_FontFamilyName as String: UIFont.preferredFont(forTextStyle: .body).fontName,
    ])
    
    // `internal` (not `private`): accessed from VideoPlayerViewController+ErrorHandling.swift,
    // which is a separate file, so `private` would not compile.
    let activityIndicatorView = UIActivityIndicatorView().configure {
        $0.tintColor = .gray
        $0.color = .gray
        $0.hidesWhenStopped = true
    }
    
    public init(viewModel: VideoPlayerViewModel, coordinator: VideoPlayerCoordinator) {
        self.viewModel = viewModel
        self.coordinator = coordinator
        super.init(nibName: nil, bundle: nil)
    }
    
    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    
    override public func viewWillAppear(_: Bool) {
        navigationController?.setNavigationBarHidden(true, animated: false)
        tabBarController?.tabBar.isHidden = true
    }
    
    override public func viewWillDisappear(_: Bool) {
        resetOrientation(UIInterfaceOrientationMask.portrait)
        UIViewController.attemptRotationToDeviceOrientation()
        navigationController?.setNavigationBarHidden(false, animated: false)
        tabBarController?.tabBar.isHidden = false
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        resetOrientation(UIInterfaceOrientationMask.landscapeRight)
        UIViewController.attemptRotationToDeviceOrientation()
        NotificationCenter.default.addObserver(self, selector: #selector(appMovedToBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        abLoopManager.delegate = self
        addLoader()
        setupPlayer()
    }
    
    /// Intentionally empty. The host app detects landscape-capable controllers via
    /// `responds(to: Selector("shouldForceLandscape"))` (see the Example AppDelegate), so this
    /// method's mere presence is what matters — do not remove it.
    @objc func shouldForceLandscape() {}
    
    @objc func appMovedToBackground() {
        pausePlayer()
    }
    
    public override var shouldAutorotate: Bool {
        return true
    }
    
    public override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .landscape
    }
    
    override public func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        playerLayer?.frame = view.bounds
    }
    
    deinit {
        playerItem?.removeObserver(self, forKeyPath: "status")
        // Buffering-recovery observers, registered alongside "status" in `addObservers()`.
        playerItem?.removeObserver(self, forKeyPath: "playbackLikelyToKeepUp")
        playerItem?.removeObserver(self, forKeyPath: "playbackBufferEmpty")

        // Remove runtime error handling notifications
        NotificationCenter.default.removeObserver(
            self,
            name: .AVPlayerItemFailedToPlayToEndTime,
            object: nil
        )
        NotificationCenter.default.removeObserver(
            self,
            name: .AVPlayerItemPlaybackStalled,
            object: nil
        )
        NotificationCenter.default.removeObserver(
            self,
            name: .AVPlayerItemDidPlayToEndTime,
            object: nil
        )
        NotificationCenter.default.removeObserver(
            self,
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )

        // Remove audio session notifications
        NotificationCenter.default.removeObserver(
            self,
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        NotificationCenter.default.removeObserver(
            self,
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )

        // An AVPlayerLayer retains its AVPlayer, so a layer left in the layer tree keeps the whole
        // player graph alive for as long as the view hierarchy does. Detach before discarding.
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil

        // Hand the audio session back so other apps can resume theirs. Deliberately placed above
        // the live-content guard below, which returns early.
        deactivateAudioSession()

        guard let isLiveContent = viewModel.isLiveContent, !isLiveContent else { return }
        if let periodicTimeObserver = periodicTimeObserver {
            player?.removeTimeObserver(periodicTimeObserver)
        }
        periodicTimeObserver = nil
        player?.currentItem?.removeObserver(self, forKeyPath: "duration")
        player?.cancelPendingPrerolls()
        player?.replaceCurrentItem(with: nil)
        invalidateControlsHiddenTimer()
    }
}

// MARK: - Video Player Setup

extension VideoPlayerViewController {
    private func addLoader() {
        view.addSubview(activityIndicatorView)
        activityIndicatorView.snp.makeConstraints { make in
            make.centerY.equalTo(view.snp.centerY)
            make.centerX.equalTo(view.snp.centerX)
        }
    }

    private func setupPlayer() {
        guard let videoURL = viewModel.url else { return }
        activateAudioSession()
        activityIndicatorView.startAnimating()
        playerItem = AVPlayerItem(url: videoURL)
        if let subtitleStyling = subtitleStyling {
            playerItem?.textStyleRules = [subtitleStyling]
        }
        player = AVPlayer(playerItem: playerItem)
        addObservers()
        fetchSupportedQualities()
        // Defensive: `resetPlayerItems()` already detaches the outgoing layer, but this also covers
        // any path that reaches `setupPlayer()` twice without a reset in between. Leaving a stale
        // layer in the tree would both stack sublayers and pin the previous AVPlayer in memory.
        playerLayer?.removeFromSuperlayer()
        playerLayer = AVPlayerLayer(player: player)
        guard let playerLayer = playerLayer else { return }
        view.backgroundColor = .black
        view.layer.addSublayer(playerLayer)
    }
    
    private func setupControls() {
        guard let totalDuration = player?.currentItem?.duration else { return }
        playerControlsView.totalTimeLabelText = viewModel.getFormattedTime(totalDuration: totalDuration.seconds)
        playerControlsView.titleLabelText = viewModel.titleLabelText
        playerControlsView.subtitleLabelText = viewModel.subtitleLabelText
        playerControlsView.previousVideoButtonState = viewModel.isPreviousButtonEnabled
        playerControlsView.nextVideoButtonState = viewModel.isNextButtonEnabled
        view.addSubview(playerControlsView)
        playerControlsView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        playerControlsView.delegate = self
        setupGestureRecognizers()
        setupSubtiteSelectionView()
    }
    
    private func setupLiveControls() {
        playerControlsView.titleLabelText = viewModel.titleLabelText
        playerControlsView.subtitleLabelText = viewModel.subtitleLabelText
        playerControlsView.previousVideoButtonState = viewModel.isPreviousButtonEnabled
        playerControlsView.nextVideoButtonState = viewModel.isNextButtonEnabled
        view.addSubview(playerControlsView)
        playerControlsView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        playerControlsView.delegate = self
        setupGestureRecognizers()
        playerControlsView.enableLiveControls()
    }
    
    private func setupSubtiteSelectionView() {
        guard let supportedLanguages = player?.supportedSubtitleOptions, !supportedLanguages.isEmpty else {
            playerControlsView.disableSubtitlesButton()
            return
        }
        subtitleSelectionView = SubtitleSelectionViewController(viewModel: .init(supportedLanguages: supportedLanguages))
        subtitleSelectionView?.delegate = self
    }
    
    func setupQualitySelectionView() {
        guard let playbackQualityStrings = viewModel.playbackQualityStrings, !playbackQualityStrings.isEmpty else {
            return
        }
        playerControlsView.unhideSettingsButton()
        qualitySelectionView = QualitySelectionViewController(viewModel: .init(supportedResolutions: playbackQualityStrings))
        qualitySelectionView?.delegate = self
    }
    
    private func setupGestureRecognizers() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        view.addGestureRecognizer(tapGesture)
    }
    
    func pausePlayer() {
        guard viewModel.playerState == .play else { return }
        player?.pause()
        playerControlsView.playPauseButtonImage = VideoPlayerImage.playButton.uiImage
        viewModel.playerState = .pause
    }
    
    func resumePlayer() {
        guard viewModel.playerState == .pause else { return }
        player?.play()
        playerControlsView.playPauseButtonImage = VideoPlayerImage.pauseButton.uiImage
        viewModel.playerState = .play
    }
    
    private func fetchSupportedQualities() {
        viewModel.delegate = self
        viewModel.fetchSupportedVideoQualites()
    }
}

// MARK: - Audio Session

extension VideoPlayerViewController {
    /// Configures and activates the shared audio session for video playback.
    ///
    /// The `.playback` category is what makes playback audible while the hardware ring/silent
    /// switch is engaged; without it the video plays completely silently. `.moviePlayback` is the
    /// mode Apple documents for long-form video (it enables the appropriate signal processing).
    ///
    /// Every call is wrapped in `do`/`catch` on purpose: a session failure (another app holding an
    /// exclusive route, a denied category, …) must degrade to silent playback rather than trap the
    /// host app. This is a library — it never gets to decide that the process should die.
    private func activateAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playback, mode: .moviePlayback)
            try audioSession.setActive(true)
        } catch {
            logger.error("Failed to configure the audio session for playback: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Releases the shared audio session on teardown.
    ///
    /// `.notifyOthersOnDeactivation` lets apps that were interrupted by us (music, podcasts) resume
    /// on their own; without it they stay silent until the user restarts them by hand.
    private func deactivateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            logger.error("Failed to deactivate the audio session: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Handles audio session interruptions (incoming call, Siri, another app taking the session).
    ///
    /// On `.began` the system has *already* silenced us, so the player, `viewModel.playerState` and
    /// the play/pause button image are all brought in line — otherwise the UI keeps claiming the
    /// video is playing while nothing moves.
    @objc private func handleAudioSessionInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else {
            return
        }

        // `InterruptionOptions` is a value type, so reading it here and capturing it is safe even
        // when the block below runs later on the main queue.
        let options = AVAudioSession.InterruptionOptions(
            rawValue: (userInfo[AVAudioSessionInterruptionOptionKey] as? UInt) ?? 0
        )

        switch type {
        case .began:
            runOnMainThread { [weak self] in
                guard let self = self else { return }
                self.didPauseForInterruption = self.viewModel.playerState == .play
                self.pausePlayer()
            }
        case .ended:
            runOnMainThread { [weak self] in
                guard let self = self else { return }
                // Only resume when the system says we may (anything else — e.g. the user started
                // another app's audio — means we must stay paused) and when the interruption is
                // what stopped us in the first place.
                let shouldResume = self.didPauseForInterruption && options.contains(.shouldResume)
                // The interruption is over either way, so the flag is always cleared.
                self.didPauseForInterruption = false
                guard shouldResume else { return }
                // The session was deactivated by the interruption, so it has to be reactivated
                // before `play()` will produce any sound.
                self.activateAudioSession()
                self.resumePlayer()
            }
        @unknown default:
            break
        }
    }

    /// Handles output route changes.
    ///
    /// `.oldDeviceUnavailable` is the "headphones were unplugged / Bluetooth went away" case. Per
    /// Apple's HIG playback must pause there, so audio never suddenly blasts out of the built-in
    /// speaker. Every other reason (a *new* device becoming available, a category change, …) is
    /// intentionally ignored — pausing on those would be user-hostile.
    @objc private func handleAudioSessionRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue),
              reason == .oldDeviceUnavailable
        else {
            return
        }

        runOnMainThread { [weak self] in
            guard let self = self else { return }
            self.pausePlayer()
        }
    }
}

// MARK: - Main Thread Dispatch

extension VideoPlayerViewController {
    /// Runs `work` on the main queue, executing it inline when the caller is already on main.
    ///
    /// AVFoundation makes no guarantee about which thread KVO callbacks and `AVPlayerItem`
    /// notifications are delivered on — for HLS they routinely arrive on a background queue — yet
    /// every one of those handlers adds subviews, installs SnapKit constraints or drives the
    /// activity indicator. Marshalling is therefore mandatory.
    ///
    /// The inline fast path keeps main-thread callbacks synchronous, which preserves the ordering
    /// the `didSetupControls` gate was written against. Correctness of that gate does not depend on
    /// ordering anyway: it is read and written on the main thread only, so whichever of the
    /// `duration`/`status` blocks runs second sees `true` and skips the duplicate setup.
    ///
    /// `internal` (not `private`): called from VideoPlayerViewController+ErrorHandling.swift,
    /// which is a separate file, so `private` would not compile.
    func runOnMainThread(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }
}

// MARK: - Observers

extension VideoPlayerViewController {
    private func addObservers() {
        playerItem?.addObserver(self, forKeyPath: "status", options: [.new, .initial], context: nil)

        // Buffering-recovery observers. `.AVPlayerItemPlaybackStalled` tells us when playback stops,
        // but nothing tells us when it can continue — these do, which is what lets the loader be
        // torn down again (see `handlePlaybackBufferingChange()`).
        //
        // The strings are the *Objective-C* property names: `AVPlayerItem` declares them as
        // `playbackLikelyToKeepUp` / `playbackBufferEmpty` with `getter=isPlaybackLikelyToKeepUp` /
        // `getter=isPlaybackBufferEmpty`. String-based KVO resolves against the Objective-C name, so
        // the Swift spellings would silently never fire.
        //
        // `.initial` is deliberately omitted (unlike "status"/"duration"): it would fire
        // synchronously inside `setupPlayer()`, before the item has loaded anything.
        playerItem?.addObserver(self, forKeyPath: "playbackLikelyToKeepUp", options: [.new], context: nil)
        playerItem?.addObserver(self, forKeyPath: "playbackBufferEmpty", options: [.new], context: nil)

        // Add runtime error handling notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemFailedToPlayToEndTime),
            name: .AVPlayerItemFailedToPlayToEndTime,
            object: playerItem
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemPlaybackStalled),
            name: .AVPlayerItemPlaybackStalled,
            object: playerItem
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidPlayToEndTime),
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )

        // Add audio session notifications. Scoped to the shared session object, mirroring the way
        // the player-item notifications above are scoped to `playerItem`. Registered above the
        // live-content guard because interruptions and route changes apply to live streams too.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionInterruption),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance()
        )

        guard let isLiveContent = viewModel.isLiveContent, !isLiveContent else { return }
        player?.currentItem?.addObserver(self, forKeyPath: "duration", options: [.new, .initial], context: nil)
        let interval = CMTime(seconds: 1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        let mainQueue = DispatchQueue.main
        periodicTimeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: mainQueue) { [weak self] time in
            guard let self = self else { return }
            if self.player?.currentItem?.status == .readyToPlay {
                self.playerControlsView.seekBarValue = Float(time.seconds)
                self.playerControlsView.currentTimeLabelText = time.durationText + "/"

                // Check for A-B loop
                if let loopSeekTime = self.abLoopManager.shouldLoop(at: time) {
                    self.player?.seek(to: loopSeekTime, toleranceBefore: CMTime.zero, toleranceAfter: CMTime.zero)
                }

                // Check for segment playlist advancement
                if let segmentSeekTime = self.abLoopManager.shouldAdvanceSegment(at: time) {
                    self.player?.seek(to: segmentSeekTime, toleranceBefore: CMTime.zero, toleranceAfter: CMTime.zero)
                }
            }
        }
    }
    
    /// Removes the observers registered in `addObservers()` for the current `playerItem`/`player`.
    /// Must be called before discarding the current item (e.g. when switching videos) so that
    /// `AVPlayerItem`s are not deallocated while KVO observers are still registered.
    /// Mirrors `addObservers()`: the per-notification `object:` and the live-content guard match
    /// exactly what was registered. The app-lifecycle observer is intentionally NOT removed here
    /// (it is owned for the controller's lifetime and torn down in `deinit`); the audio session
    /// observers ARE, because `addObservers()` registers them and `setupPlayer()` re-runs on every
    /// video switch — leaving them in place would register a second copy each time.
    private func removeObservers() {
        playerItem?.removeObserver(self, forKeyPath: "status")
        playerItem?.removeObserver(self, forKeyPath: "playbackLikelyToKeepUp")
        playerItem?.removeObserver(self, forKeyPath: "playbackBufferEmpty")

        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemFailedToPlayToEndTime, object: playerItem)
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemPlaybackStalled, object: playerItem)
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: playerItem)

        NotificationCenter.default.removeObserver(self, name: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance())
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.routeChangeNotification, object: AVAudioSession.sharedInstance())

        guard let isLiveContent = viewModel.isLiveContent, !isLiveContent else { return }
        if let periodicTimeObserver = periodicTimeObserver {
            player?.removeTimeObserver(periodicTimeObserver)
        }
        periodicTimeObserver = nil
        player?.currentItem?.removeObserver(self, forKeyPath: "duration")
    }

    public override func observeValue(forKeyPath keyPath: String?, of _: Any?, change _: [NSKeyValueChangeKey: Any]?, context _: UnsafeMutableRawPointer?) {
        // AVFoundation delivers KVO on whichever thread it happens to be using — for HLS these
        // callbacks routinely arrive off the main thread — and every branch below touches UIKit
        // (adds subviews, installs SnapKit constraints, drives the activity indicator).
        runOnMainThread { [weak self] in
            guard let self = self else { return }
            self.handleObservedValueChange(forKeyPath: keyPath)
        }
    }

    /// Main-thread body of `observeValue(forKeyPath:of:change:context:)`.
    ///
    /// State is re-read from `player?.currentItem` rather than from the KVO `change` dictionary so
    /// that a callback which was queued onto the main thread always acts on the item's *current*
    /// state, never on a value that has since been superseded.
    private func handleObservedValueChange(forKeyPath keyPath: String?) {
        switch keyPath {
        case "duration":
            if let duration = player?.currentItem?.duration, duration.seconds > 0.0, !didSetupControls {
                activityIndicatorView.stopAnimating()
                playerControlsView.seekBarMaximumValue = Float(duration.seconds)
                enableControls()
                resumePlayer()
            }
        case "status":
            switch player?.currentItem?.status {
            case .readyToPlay:
                if let isLiveContent = viewModel.isLiveContent, isLiveContent, !didSetupControls {
                    activityIndicatorView.stopAnimating()
                    playerControlsView.seekBarValue = 1
                    playerControlsView.seekBarMaximumValue = 1
                    enableControls()
                    resumePlayer()
                }
            case .failed:
                activityIndicatorView.stopAnimating()
                handlePlayerError(player?.currentItem?.error)
            default:
                break
            }
        case "playbackLikelyToKeepUp", "playbackBufferEmpty":
            handlePlaybackBufferingChange()
        default:
            break
        }
    }

    /// Drives the loader for mid-playback buffering, and — crucially — turns it back off.
    ///
    /// `playerItemPlaybackStalled` starts the indicator and kills the controls auto-hide timer, but
    /// the stall notification has no counterpart for "playback recovered". Without this the
    /// indicator stayed up forever after the first stall, because the only `stopAnimating()` calls
    /// on the initial-load path are gated behind `!didSetupControls`.
    private func handlePlaybackBufferingChange() {
        // Before the controls exist, the "status"/"duration" path owns the loader (it is showing the
        // initial load, not a stall). Taking over here would hide it while the video is still blank.
        guard didSetupControls, let currentItem = player?.currentItem else { return }

        if currentItem.isPlaybackLikelyToKeepUp {
            activityIndicatorView.stopAnimating()
            // The stall handler invalidated the auto-hide timer to keep the controls on screen while
            // buffering. Restore it, otherwise the controls stay up for the rest of the session.
            resetControlsHiddenTimer()
        } else if currentItem.isPlaybackBufferEmpty {
            // The buffer drained mid-playback. `.AVPlayerItemPlaybackStalled` normally covers this,
            // but it is not posted in every configuration, so mirror its UI here as well.
            activityIndicatorView.startAnimating()
            invalidateControlsHiddenTimer()
        }
    }

    private func enableControls() {
        if let isLiveContent = viewModel.isLiveContent, isLiveContent {
            setupLiveControls()
        } else {
            setupControls()
        }
        didSetupControls = true
        showControls()
    }
}

// MARK: - Show/Hide Control Functionality

extension VideoPlayerViewController {
    @objc private func handleTap(_: UITapGestureRecognizer) {
        resetControlsHiddenTimer()
        playerControlsView.isHidden ? showControls() : hideControls()
    }
    
    private func showControls() {
        playerControlsView.isHidden = false
        
        UIView.animate(withDuration: 0.25) {
            self.playerControlsView.alpha = 1
        }
        resetControlsHiddenTimer()
    }
    
    @objc func hideControls() {
        UIView.animate(withDuration: 0.25) {
            self.playerControlsView.alpha = 0
        } completion: { _ in
            self.playerControlsView.isHidden = true
        }
    }
    
    func resetControlsHiddenTimer() {
        invalidateControlsHiddenTimer()
        controlsHiddenTimer = Timer.scheduledTimer(timeInterval: controlsHideDelay,
                                                   target: self,
                                                   selector: #selector(hideControlsDueToInactivity), userInfo: nil, repeats: false)
    }
    
    func invalidateControlsHiddenTimer() {
        controlsHiddenTimer?.invalidate()
        controlsHiddenTimer = nil
    }
    
    @objc private func hideControlsDueToInactivity() {
        hideControls()
    }
}

// MARK: - Reset Player

extension VideoPlayerViewController {
    func resetPlayer(with currentVideoIndex: Int) {
        resetPlayerItems()
        viewModel.config.playlist.currentVideoIndex = currentVideoIndex
        resetControlsHiddenTimer()
        playerControlsView.seekBarValue = 0
        playerControlsView.currentTimeLabelText = "00:00"
        setupPlayer()
        resumePlayer()
    }
    
    func resetPlayerItems() {
        hideControls()
        didSetupControls = false
        disableGestureRecognizers()
        // Remove observers from the outgoing item/player before discarding it, otherwise the
        // AVPlayerItem is deallocated with KVO observers still registered.
        removeObservers()
        player?.replaceCurrentItem(with: nil)
        playerItem = nil
        // Detach before dropping the reference. An AVPlayerLayer retains its AVPlayer, so nilling
        // the property alone leaves the layer in `view.layer`'s sublayers keeping the old player
        // alive — every video switch would stack another layer and another AVPlayer.
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        viewModel.playerState = .pause
    }
    
    private func disableGestureRecognizers() {
        view.gestureRecognizers?.removeAll()
    }
}

// MARK: - A-B Loop Functionality

extension VideoPlayerViewController {
    /// Gets the frame rate of the currently playing video
    ///
    /// - Returns: Frame rate as Double, defaults to ABLoopConstants.defaultFrameRate if unavailable
    func getVideoFrameRate() -> Double {
        guard let track = playerItem?.asset.tracks(withMediaType: .video).first else {
            return ABLoopConstants.defaultFrameRate
        }
        return Double(track.nominalFrameRate)
    }
}

// MARK: - ABLoopViewControllerDelegate

extension VideoPlayerViewController: ABLoopViewControllerDelegate {
    func didSelectABLoop(_ loop: ABLoop?) {
        // `setActiveLoop` already clears any active segment playlist, so the two modes are
        // mutually exclusive by construction. Clearing the other mode again here would
        // enqueue a second block on the same serial queue that nils the loop just set.
        abLoopManager.setActiveLoop(loop)
        resumePlayer()
        resetControlsHiddenTimer()
    }

    func didSelectSegmentPlaylist(_ playlist: SegmentPlaylist?) {
        // `setActiveSegmentPlaylist` already clears any active A-B loop — see above.
        abLoopManager.setActiveSegmentPlaylist(playlist)
        resumePlayer()
        resetControlsHiddenTimer()
    }

    func didRequestSeek(to time: CMTime) {
        player?.seek(to: time, toleranceBefore: CMTime.zero, toleranceAfter: CMTime.zero)
    }
}

// MARK: - ABLoopManagerDelegate

extension VideoPlayerViewController: ABLoopManagerDelegate {
    public func abLoopDidReachEnd(_ loop: ABLoop) {
        // Optional: Add visual feedback or logging when loop repeats
    }

    public func segmentPlaylistDidFinishSegment(_ segment: PlaybackSegment) {
        // Optional: Add visual feedback or logging when segment finishes
    }

    public func segmentPlaylistDidComplete(_ playlist: SegmentPlaylist) {
        // Optional: Add visual feedback or logging when playlist completes
    }
}

