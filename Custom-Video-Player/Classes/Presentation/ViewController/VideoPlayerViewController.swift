import UIKit
import AVKit
import AVFoundation
import MediaPlayer
import os

public class VideoPlayerViewController: UIViewController {
    let viewModel: VideoPlayerViewModel
    let coordinator: VideoPlayerCoordinator
    let abLoopManager = ABLoopManager()

    /// A library must not `print` into the host app's console; route diagnostics through
    /// the unified log instead, matching `ABLoopManager`.
    private let logger = Logger(subsystem: "com.customvideoplayer", category: "VideoPlayerViewController")

    private var periodicTimeObserver: Any?
    /// Fires exactly at the active A-B loop's point B.
    ///
    /// The 1 Hz `periodicTimeObserver` is far too coarse to close a loop on: point B could
    /// overshoot by almost a full second, which is useless for the practice loops this library
    /// exists to serve. A boundary observer is scheduled by the player itself at the precise
    /// time, so it lands on the frame instead of on the next tick.
    ///
    /// Registered and re-registered exclusively through `updateLoopBoundaryObserver()` (which
    /// removes any previous one first) and torn down in `removeLoopBoundaryObserver()`.
    private var loopBoundaryTimeObserver: Any?
    /// The Picture-in-Picture controller for the *current* player layer.
    ///
    /// Rebuilt from scratch every time `setupPlayer()` creates a new layer — an
    /// `AVPictureInPictureController` is bound to the layer it was created with, so a stale one
    /// would silently drive the previous video's (already detached) layer.
    ///
    /// `internal` (not `private`): toggled from VideoPlayerViewController+Delegate.swift.
    var pictureInPictureController: AVPictureInPictureController?
    /// Remote-command targets registered on `MPRemoteCommandCenter.shared()`, paired with the
    /// command they belong to so every one can be handed back in `unregisterRemoteCommands()`.
    ///
    /// The command centre is a process-wide singleton: a target left behind outlives this
    /// controller and keeps hijacking the host app's lock screen and Control Center.
    private var remoteCommandTargets: [(command: MPRemoteCommand, target: Any)] = []
    /// The rate the user picked with the speed control.
    ///
    /// Deliberately *not* pushed straight into `AVPlayer.rate`: assigning a non-zero rate is what
    /// starts an `AVPlayer`, so writing it while paused would resume playback behind the user's
    /// back. The selection is stored here and applied by `applySelectedPlaybackRate()` only while
    /// playback is already running.
    ///
    /// `internal` (not `private`): read and written from VideoPlayerViewController+Delegate.swift.
    private(set) var selectedPlaybackRate: Float = 1.0
    /// The video track's real frame rate, once it has finished loading asynchronously.
    ///
    /// `nil` until then, which is why `getVideoFrameRate()` falls back to
    /// `ABLoopConstants.defaultFrameRate`.
    private var cachedVideoFrameRate: Double?
    /// The in-flight frame-rate load, kept so it can be cancelled when the item is replaced.
    private var frameRateLoadTask: Task<Void, Never>?
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
        // `resetOrientation` already calls `setNeedsUpdateOfSupportedInterfaceOrientations()`,
        // which replaced the deprecated `attemptRotationToDeviceOrientation()` in iOS 16.
        resetOrientation(UIInterfaceOrientationMask.portrait)
        navigationController?.setNavigationBarHidden(false, animated: false)
        tabBarController?.tabBar.isHidden = false
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        resetOrientation(UIInterfaceOrientationMask.landscapeRight)
        NotificationCenter.default.addObserver(self, selector: #selector(appMovedToBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        abLoopManager.delegate = self
        // Registered once for the controller's lifetime and removed in `deinit`, deliberately not
        // in `removeObservers()`: the command centre is a singleton shared with the host app, and
        // re-registering per video switch would need a matching removal on every path.
        registerRemoteCommands()
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

        // Hand the process-wide media surfaces back to the host app. Both are singletons, so a
        // target or a now-playing entry left behind here outlives this controller and keeps
        // driving (or misreporting) playback the user can no longer see.
        unregisterRemoteCommands()

        // Bound to the outgoing player layer; nothing else releases it.
        pictureInPictureController?.delegate = nil
        pictureInPictureController = nil

        // An AVPlayerLayer retains its AVPlayer, so a layer left in the layer tree keeps the whole
        // player graph alive for as long as the view hierarchy does. Detach before discarding.
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil

        // Hand the audio session back so other apps can resume theirs. Deliberately placed above
        // the live-content guard below, which returns early.
        deactivateAudioSession()

        frameRateLoadTask?.cancel()
        frameRateLoadTask = nil

        // Above the live-content guard on purpose: the boundary observer is only ever registered
        // for non-live content, but removing it is a no-op when there is none, and putting it
        // here means no future edit to the guard can strand it on the player.
        removeLoopBoundaryObserver()

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
        // `.timeDomain` keeps pitch natural when the rate is changed, which is what makes 0.5x
        // usable for practice; the default `.lowQualityZeroLatency` chipmunks the audio.
        playerItem?.audioTimePitchAlgorithm = .timeDomain
        player = AVPlayer(playerItem: playerItem)
        // AirPlay: without this the player refuses to hand video to an external route.
        player?.allowsExternalPlayback = true
        addObservers()
        fetchSupportedQualities()
        loadVideoFrameRate()
        // Defensive: `resetPlayerItems()` already detaches the outgoing layer, but this also covers
        // any path that reaches `setupPlayer()` twice without a reset in between. Leaving a stale
        // layer in the tree would both stack sublayers and pin the previous AVPlayer in memory.
        playerLayer?.removeFromSuperlayer()
        playerLayer = AVPlayerLayer(player: player)
        guard let playerLayer = playerLayer else { return }
        view.backgroundColor = .black
        view.layer.addSublayer(playerLayer)
        // Strictly after the layer exists: the controller is bound to the layer it is built with,
        // so it has to be rebuilt every time the layer is.
        setupPictureInPicture(for: playerLayer)
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
        playerControlsView.setPictureInPictureAvailable(pictureInPictureController != nil)
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
        playerControlsView.setPictureInPictureAvailable(pictureInPictureController != nil)
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
        updateNowPlayingInfo()
    }

    func resumePlayer() {
        guard viewModel.playerState == .pause else { return }
        player?.play()
        playerControlsView.playPauseButtonImage = VideoPlayerImage.pauseButton.uiImage
        viewModel.playerState = .play
        // `play()` always resumes at 1.0, so the user's speed has to be re-applied on every
        // resume — not only when they change it.
        applySelectedPlaybackRate()
        updateNowPlayingInfo()
    }

    private func fetchSupportedQualities() {
        viewModel.delegate = self
        viewModel.fetchSupportedVideoQualites()
    }
}

// MARK: - Playback Speed

extension VideoPlayerViewController {
    /// Records a newly selected playback rate and applies it if playback is already running.
    ///
    /// - Parameter rate: The rate to select, e.g. `0.75` or `1.5`.
    func setPlaybackRate(_ rate: Float) {
        selectedPlaybackRate = rate
        // No-op when paused — see `selectedPlaybackRate`. `resumePlayer()` picks it up.
        applySelectedPlaybackRate()
        updateNowPlayingInfo()
    }

    /// Pushes `selectedPlaybackRate` into the player, but only while playback is running.
    ///
    /// The guard is the whole point: `AVPlayer.rate` is not a preference, it is the transport
    /// control. Writing a non-zero value while paused *starts* playback, so this must never run
    /// on the paused path.
    ///
    /// `internal` (not `private`): also called from VideoPlayerViewController+Delegate.swift after
    /// seek-bar scrubbing, which restarts the player at 1.0.
    func applySelectedPlaybackRate() {
        guard viewModel.playerState == .play, let player = player, player.rate != 0 else { return }
        guard player.rate != selectedPlaybackRate else { return }
        player.rate = selectedPlaybackRate
    }
}

// MARK: - Now Playing Info & Remote Commands

extension VideoPlayerViewController {
    /// Publishes the current playback state to the lock screen and Control Center.
    ///
    /// Called on every state transition and on each 1 Hz tick, so the scrubber there tracks the
    /// in-app one. The rate reported is the *selected* rate while playing and `0` while paused —
    /// that is how the system decides which transport button to draw.
    func updateNowPlayingInfo() {
        var nowPlayingInfo: [String: Any] = [:]
        nowPlayingInfo[MPMediaItemPropertyTitle] = viewModel.subtitleLabelText ?? viewModel.titleLabelText
        nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = viewModel.titleLabelText

        if let duration = player?.currentItem?.duration, duration.isNumeric {
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration.seconds
        }
        if let currentTime = player?.currentTime(), currentTime.isNumeric {
            nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime.seconds
        }
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = viewModel.playerState == .play ? selectedPlaybackRate : 0.0
        nowPlayingInfo[MPNowPlayingInfoPropertyIsLiveStream] = viewModel.isLiveContent ?? false

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    /// Wires the lock screen / Control Center transport buttons to the in-app playback methods.
    ///
    /// Every target added here is recorded in `remoteCommandTargets` and handed back in
    /// `unregisterRemoteCommands()`. The handlers capture `self` weakly: the command centre is a
    /// singleton that holds its blocks until they are removed, so a strong capture would make
    /// `deinit` — and therefore the removal itself — unreachable.
    private func registerRemoteCommands() {
        guard remoteCommandTargets.isEmpty else { return }
        let commandCenter = MPRemoteCommandCenter.shared()

        // Matches the in-app skip buttons, which move by `VideoPlayerViewModel.seekDuration`.
        let skipInterval = NSNumber(value: VideoPlayerViewController.remoteSkipInterval)
        commandCenter.skipForwardCommand.preferredIntervals = [skipInterval]
        commandCenter.skipBackwardCommand.preferredIntervals = [skipInterval]

        addRemoteCommandTarget(to: commandCenter.playCommand) { [weak self] _ in
            guard let self = self, self.viewModel.playerState == .pause else { return .commandFailed }
            self.resumePlayer()
            return .success
        }

        addRemoteCommandTarget(to: commandCenter.pauseCommand) { [weak self] _ in
            guard let self = self, self.viewModel.playerState == .play else { return .commandFailed }
            self.pausePlayer()
            return .success
        }

        addRemoteCommandTarget(to: commandCenter.togglePlayPauseCommand) { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.togglePlayPause()
            return .success
        }

        addRemoteCommandTarget(to: commandCenter.skipForwardCommand) { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.seekForward()
            return .success
        }

        addRemoteCommandTarget(to: commandCenter.skipBackwardCommand) { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.seekBackward()
            return .success
        }
    }

    /// Enables `command`, attaches `handler` and records the resulting target so that
    /// `unregisterRemoteCommands()` can hand back exactly what was added.
    ///
    /// - Parameters:
    ///   - command: The remote command to wire up.
    ///   - handler: The block the system invokes; must not capture `self` strongly.
    private func addRemoteCommandTarget(
        to command: MPRemoteCommand,
        handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus
    ) {
        command.isEnabled = true
        let target = command.addTarget(handler: handler)
        remoteCommandTargets.append((command: command, target: target))
    }

    /// Exact counterpart of `registerRemoteCommands()`, plus the now-playing entry.
    ///
    /// Disabling is not enough on its own — a disabled command with a live target still retains
    /// the block — so each target is explicitly removed from the command it was added to.
    private func unregisterRemoteCommands() {
        for entry in remoteCommandTargets {
            entry.command.removeTarget(entry.target)
            entry.command.isEnabled = false
        }
        remoteCommandTargets.removeAll()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    /// Skip interval, in seconds, offered to the remote transport controls.
    private static let remoteSkipInterval: Double = 15
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

// MARK: - Picture in Picture

extension VideoPlayerViewController {
    /// Builds the Picture-in-Picture controller over `playerLayer`.
    ///
    /// An `AVPictureInPictureController` is permanently bound to the layer it was created with, so
    /// this is called from `setupPlayer()` every time a layer is created and the previous
    /// controller is dropped in `resetPlayerItems()`. Reusing one across a video switch would
    /// leave it driving the old, already-detached layer.
    ///
    /// `isPictureInPictureSupported()` is `false` on the Simulator and on devices without PiP, in
    /// which case no controller is built and the button stays hidden.
    ///
    /// - Note: PiP only actually starts when the *host* app declares the `audio` background mode;
    ///   that is the integrator's `Info.plist`, not something a library can set. A missing entry
    ///   surfaces through `failedToStartPictureInPictureWithError`, which is logged below.
    ///
    /// - Parameter playerLayer: The freshly created layer to attach to.
    private func setupPictureInPicture(for playerLayer: AVPlayerLayer) {
        pictureInPictureController?.delegate = nil
        pictureInPictureController = nil

        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }

        let contentSource = AVPictureInPictureController.ContentSource(playerLayer: playerLayer)
        let controller = AVPictureInPictureController(contentSource: contentSource)
        controller.delegate = self
        pictureInPictureController = controller
    }
}

// MARK: - AVPictureInPictureControllerDelegate

extension VideoPlayerViewController: AVPictureInPictureControllerDelegate {
    public func pictureInPictureControllerWillStartPictureInPicture(_: AVPictureInPictureController) {
        // The floating window carries its own transport controls; ours would sit on top of the
        // (now empty) full-screen layer for no reason.
        invalidateControlsHiddenTimer()
        hideControls()
    }

    public func pictureInPictureControllerDidStopPictureInPicture(_: AVPictureInPictureController) {
        resetControlsHiddenTimer()
    }

    public func pictureInPictureController(
        _: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        // This controller is never dismissed when PiP starts, so its view hierarchy and player
        // layer are still intact and there is nothing to rebuild — report success immediately.
        // Reporting `false` would make the system tear the PiP window down without restoring.
        completionHandler(true)
    }

    public func pictureInPictureController(
        _: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        logger.error("Picture in Picture failed to start: \(error.localizedDescription, privacy: .public)")
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
                self.updateNowPlayingInfo()

                // `AVPlayer` silently resets `rate` to 1.0 after some seeks and stall recoveries.
                // `applySelectedPlaybackRate()` only writes while the player is already moving, so
                // this can never resurrect playback the user paused.
                self.applySelectedPlaybackRate()

                // Check for A-B loop.
                //
                // Kept as a backstop even though `loopBoundaryTimeObserver` is what actually
                // closes the loop: a boundary observer does not fire if the loop was activated
                // while the play head was already past point B, and this tick catches that.
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

    /// Re-registers the boundary observer that closes the active A-B loop at point B.
    ///
    /// Call this on every change of the active loop — including deactivation, where the guards
    /// below simply leave no observer registered. Any previously registered observer is removed
    /// first, so the add/remove pairing holds no matter how often this runs.
    ///
    /// Boundary observers are only meaningful on a fixed timeline, hence the live-content guard,
    /// which mirrors the one guarding the periodic observer in `addObservers()`.
    func updateLoopBoundaryObserver() {
        removeLoopBoundaryObserver()

        guard let isLiveContent = viewModel.isLiveContent, !isLiveContent,
              let player = player,
              let activeLoop = abLoopManager.getActiveLoop()
        else {
            return
        }

        let pointB = activeLoop.pointB.toCMTime()
        guard pointB.isNumeric, pointB.seconds > 0 else { return }

        loopBoundaryTimeObserver = player.addBoundaryTimeObserver(
            forTimes: [NSValue(time: pointB)],
            queue: .main
        ) { [weak self] in
            guard let self = self else { return }
            // Evaluated at `pointB` rather than at `player.currentTime()` because a boundary
            // observer may fire a hair *before* the time it was scheduled for, which would make
            // `shouldLoop(at:)`'s `currentTime >= endTime` test fail and skip the loop. Passing
            // the boundary itself still lets the manager veto (the loop may have been changed or
            // cleared since registration) and still drives its delegate callback.
            guard let loopSeekTime = self.abLoopManager.shouldLoop(at: pointB) else { return }
            self.player?.seek(to: loopSeekTime, toleranceBefore: CMTime.zero, toleranceAfter: CMTime.zero)
        }
    }

    /// Removes the loop boundary observer if one is registered. Safe to call repeatedly.
    ///
    /// - Important: Must run before `player` is replaced — `removeTimeObserver(_:)` has to be sent
    ///   to the same `AVPlayer` the observer was added to.
    private func removeLoopBoundaryObserver() {
        if let loopBoundaryTimeObserver = loopBoundaryTimeObserver {
            player?.removeTimeObserver(loopBoundaryTimeObserver)
        }
        loopBoundaryTimeObserver = nil
    }

    /// Removes the observers registered in `addObservers()` for the current `playerItem`/`player`.
    /// Must be called before discarding the current item (e.g. when switching videos) so that
    /// `AVPlayerItem`s are not deallocated while KVO observers are still registered.
    /// Mirrors `addObservers()`: the per-notification `object:` and the live-content guard match
    /// exactly what was registered. The app-lifecycle observer is intentionally NOT removed here
    /// (it is owned for the controller's lifetime and torn down in `deinit`); the audio session
    /// observers ARE, because `addObservers()` registers them and `setupPlayer()` re-runs on every
    /// video switch — leaving them in place would register a second copy each time. The same goes
    /// for the loop boundary observer: it is registered on demand by
    /// `updateLoopBoundaryObserver()`, not by `addObservers()`, but it lives on the `AVPlayer`
    /// being discarded here so it must come off before that player is replaced.
    private func removeObservers() {
        playerItem?.removeObserver(self, forKeyPath: "status")
        playerItem?.removeObserver(self, forKeyPath: "playbackLikelyToKeepUp")
        playerItem?.removeObserver(self, forKeyPath: "playbackBufferEmpty")

        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemFailedToPlayToEndTime, object: playerItem)
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemPlaybackStalled, object: playerItem)
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: playerItem)

        NotificationCenter.default.removeObserver(self, name: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance())
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.routeChangeNotification, object: AVAudioSession.sharedInstance())

        // Above the live-content guard for the same reason as in `deinit`: it is a no-op when no
        // boundary observer is registered, and being here means the guard can never strand one.
        removeLoopBoundaryObserver()

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
            // Recovering from a stall restarts the player at 1.0, so the user's speed has to be
            // put back. No-op while paused — see `applySelectedPlaybackRate()`.
            applySelectedPlaybackRate()
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
        // An A-B loop is expressed as absolute timecodes, so it is meaningless against a different
        // video: left active it would keep firing against the new item's timeline and yank the
        // user back to the previous video's point A. `setActiveLoop(nil)` also clears any active
        // segment playlist, so this single call covers both modes.
        abLoopManager.setActiveLoop(nil)
        // Remove observers from the outgoing item/player before discarding it, otherwise the
        // AVPlayerItem is deallocated with KVO observers still registered. This also removes the
        // loop boundary observer, which must go back to the player it was added to.
        removeObservers()
        // The resolved frame rate belongs to the outgoing asset; a new one is loaded by
        // `setupPlayer()`, and until it lands callers fall back to the default.
        frameRateLoadTask?.cancel()
        frameRateLoadTask = nil
        cachedVideoFrameRate = nil
        // Bound to the layer being discarded below; `setupPlayer()` builds a fresh one.
        pictureInPictureController?.delegate = nil
        pictureInPictureController = nil
        playerControlsView.setPictureInPictureAvailable(false)
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
    /// Gets the frame rate of the currently playing video.
    ///
    /// Returns the cached value resolved by `loadVideoFrameRate()`, or the default while that load
    /// is still in flight (or if the asset never reports a usable rate). Timecodes computed from
    /// the default are simply coarse, never invalid.
    ///
    /// - Returns: Frame rate as Double, defaults to `ABLoopConstants.defaultFrameRate` if unavailable
    func getVideoFrameRate() -> Double {
        return cachedVideoFrameRate ?? ABLoopConstants.defaultFrameRate
    }

    /// Starts resolving the current asset's video frame rate and caches the result.
    ///
    /// This replaces the synchronous `asset.tracks(withMediaType:)` accessor, which is deprecated
    /// *and* wrong here: for a remote HLS asset whose playlist has not been parsed yet it returns
    /// an empty array, so the 30 fps fallback was the normal path and every A-B timecode was
    /// computed against the wrong denominator. `load(_:)` waits for the asset to actually load.
    private func loadVideoFrameRate() {
        guard let asset = playerItem?.asset else { return }

        frameRateLoadTask?.cancel()
        frameRateLoadTask = Task { [weak self] in
            let resolvedFrameRate = await VideoPlayerViewController.resolveFrameRate(for: asset)
            // Cancellation means the item was replaced while the load was in flight, so the answer
            // now describes an asset nobody is watching any more.
            guard !Task.isCancelled, let resolvedFrameRate = resolvedFrameRate else { return }
            guard let self = self else { return }
            self.runOnMainThread {
                self.cachedVideoFrameRate = resolvedFrameRate
            }
        }
    }

    /// Loads the first video track's nominal frame rate.
    ///
    /// `static` so it holds no reference to the controller: the load can outlive a video switch,
    /// and the caller decides — after checking cancellation — whether the answer is still wanted.
    ///
    /// - Parameter asset: The asset to inspect.
    /// - Returns: The frame rate, or `nil` when the asset exposes no usable video track.
    private static func resolveFrameRate(for asset: AVAsset) async -> Double? {
        do {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first else { return nil }
            let nominalFrameRate = try await track.load(.nominalFrameRate)
            // A track can legitimately report 0 before its format description is available;
            // reporting that upward would divide by zero in `TimePoint`.
            guard nominalFrameRate > 0 else { return nil }
            return Double(nominalFrameRate)
        } catch {
            return nil
        }
    }
}

// MARK: - ABLoopViewControllerDelegate

extension VideoPlayerViewController: ABLoopViewControllerDelegate {
    func didSelectABLoop(_ loop: ABLoop?) {
        // `setActiveLoop` already clears any active segment playlist, so the two modes are
        // mutually exclusive by construction. Clearing the other mode again here would
        // enqueue a second block on the same serial queue that nils the loop just set.
        abLoopManager.setActiveLoop(loop)
        // The boundary observer is what makes point B land on the frame instead of on the next
        // 1 Hz tick, so it has to be rebuilt for the loop that was just activated (or torn down,
        // when `loop` is nil).
        updateLoopBoundaryObserver()
        resumePlayer()
        resetControlsHiddenTimer()
    }

    func didSelectSegmentPlaylist(_ playlist: SegmentPlaylist?) {
        // `setActiveSegmentPlaylist` already clears any active A-B loop — see above.
        abLoopManager.setActiveSegmentPlaylist(playlist)
        // Activating a playlist deactivates the loop, so this removes the boundary observer.
        // Segment ends stay on the 1 Hz path: their boundaries move as the playlist advances,
        // and their precision was never advertised as frame-accurate.
        updateLoopBoundaryObserver()
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

