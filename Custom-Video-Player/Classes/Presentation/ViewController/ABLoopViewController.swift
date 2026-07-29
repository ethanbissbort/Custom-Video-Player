import UIKit
import AVFoundation
import SnapKit

/// Protocol for A-B loop view controller delegate
protocol ABLoopViewControllerDelegate: AnyObject {
    func didSelectABLoop(_ loop: ABLoop?)
    func didSelectSegmentPlaylist(_ playlist: SegmentPlaylist?)
    func didRequestSeek(to time: CMTime)
}

/// View controller for managing A-B loops and segment playlists
class ABLoopViewController: UIViewController {
    // MARK: - Properties

    weak var delegate: ABLoopViewControllerDelegate?
    private let viewModel: ABLoopViewModel
    private let frameRate: Double
    private var currentPlayerTime: CMTime

    /// Duration of the video being edited, or an indefinite time when it is unknown.
    ///
    /// Supplied by the presenter when it knows the value; otherwise resolved lazily from
    /// the presenting player — see `resolvedDuration`. Creation dialogs use it to reject
    /// points past the end of the video, which would otherwise produce a loop that looks
    /// normal, activates, and never fires.
    private var videoDuration: CMTime

    // MARK: - UI Components

    private let containerView = UIView().configure {
        $0.backgroundColor = VideoPlayerColor(palette: .black).uiColor.withAlphaComponent(0.95)
        $0.layer.cornerRadius = ABLoopConstants.UI.cornerRadius
    }

    /// Dynamic Type is capped here (and on the other labels in this panel) because the container
    /// has a fixed height: text has to follow the user's size setting without spilling out of it.
    private let titleLabel = UILabel().configure {
        $0.text = CVPLocalized(
            "abloop.panel.title",
            value: "A-B Loop & Segments",
            comment: "Title of the panel listing saved A-B loops and segment playlists"
        )
        $0.font = UIFontMetrics(forTextStyle: .title3).scaledFont(
            for: FontUtility.helveticaNeueBold(ofSize: 20),
            maximumPointSize: 28
        )
        $0.adjustsFontForContentSizeCategory = true
        $0.textColor = VideoPlayerColor(palette: .white).uiColor
        $0.textAlignment = .center
        $0.numberOfLines = 0
        $0.accessibilityTraits = .header
    }

    /// The glyph is decorative — "✕" is read out as "multiplication sign" — so the button carries
    /// a real label for VoiceOver.
    private let closeButton = UIButton().configure {
        $0.setTitle("✕", for: .normal)
        $0.titleLabel?.font = FontUtility.helveticaNeueBold(ofSize: 24)
        $0.setTitleColor(VideoPlayerColor(palette: .white).uiColor, for: .normal)
        $0.accessibilityLabel = CVPLocalized(
            "abloop.close.accessibility",
            value: "Close",
            comment: "VoiceOver label for the button that closes the A-B loop panel"
        )
    }

    private lazy var segmentedControl: UISegmentedControl = {
        let control = UISegmentedControl(items: [
            CVPLocalized("abloop.title", value: "A-B Loops", comment: "Segmented control tab listing A-B loops"),
            CVPLocalized(
                "abloop.segment.title",
                value: "Segment Playlists",
                comment: "Segmented control tab listing segment playlists"
            )
        ])
        control.accessibilityLabel = CVPLocalized(
            "abloop.mode.accessibility",
            value: "List to show",
            comment: "VoiceOver label for the control that switches between loops and playlists"
        )
        control.selectedSegmentIndex = 0
        control.backgroundColor = VideoPlayerColor(palette: .black).uiColor.withAlphaComponent(0.5)
        control.selectedSegmentTintColor = VideoPlayerColor(palette: .red).uiColor
        control.setTitleTextAttributes([.foregroundColor: VideoPlayerColor(palette: .white).uiColor], for: .normal)
        control.setTitleTextAttributes([.foregroundColor: VideoPlayerColor(palette: .white).uiColor], for: .selected)
        return control
    }()

    private let tableView = UITableView().configure {
        $0.backgroundColor = .clear
        $0.separatorStyle = .singleLine
        $0.separatorColor = VideoPlayerColor(palette: .pearlWhite).uiColor.withAlphaComponent(0.3)
    }

    private let createButton = UIButton().configure {
        $0.titleLabel?.font = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: FontUtility.helveticaNeueRegular(ofSize: 16),
            maximumPointSize: 22
        )
        $0.titleLabel?.adjustsFontForContentSizeCategory = true
        $0.setTitleColor(VideoPlayerColor(palette: .white).uiColor, for: .normal)
        $0.backgroundColor = VideoPlayerColor(palette: .red).uiColor
        $0.layer.cornerRadius = ABLoopConstants.UI.cornerRadius
    }

    private let stopLoopButton = UIButton().configure {
        $0.setTitle(
            CVPLocalized("abloop.stopLoop", value: "Stop Loop", comment: "Button that deactivates the running loop"),
            for: .normal
        )
        $0.titleLabel?.font = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: FontUtility.helveticaNeueRegular(ofSize: 16),
            maximumPointSize: 22
        )
        $0.titleLabel?.adjustsFontForContentSizeCategory = true
        $0.setTitleColor(VideoPlayerColor(palette: .white).uiColor, for: .normal)
        $0.backgroundColor = VideoPlayerColor(palette: .black).uiColor.withAlphaComponent(0.5)
        $0.layer.cornerRadius = ABLoopConstants.UI.cornerRadius
        $0.isHidden = true
    }

    // MARK: - Initialization

    /// Initializes the A-B loop panel
    ///
    /// - Parameters:
    ///   - abLoopManager: Manager backing the listed loops and playlists
    ///   - videoIdentifier: Identifier of the video being edited
    ///   - frameRate: Frame rate of the video, used for frame-accurate timecode entry
    ///   - currentTime: Playhead position at the moment the panel opened
    ///   - duration: Duration of the video. Defaulted so existing call sites keep
    ///     compiling; when it is left unspecified the panel falls back to reading the
    ///     duration off the presenting player.
    init(
        abLoopManager: ABLoopManager,
        videoIdentifier: String,
        frameRate: Double,
        currentTime: CMTime,
        duration: CMTime = .indefinite
    ) {
        self.viewModel = ABLoopViewModel(abLoopManager: abLoopManager, videoIdentifier: videoIdentifier)
        self.frameRate = frameRate
        self.currentPlayerTime = currentTime
        self.videoDuration = duration
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        setupTableView()
        setupActions()
        setupAccessibility()
        updateUI()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // A panel presented over the player is a new screen as far as VoiceOver is concerned;
        // without this, focus stays on the transport control the user came from.
        UIAccessibility.post(notification: .screenChanged, argument: titleLabel)
    }

    // MARK: - Setup

    private func setupViews() {
        view.backgroundColor = UIColor.black.withAlphaComponent(0.7)

        view.addSubview(containerView)
        containerView.addSubview(titleLabel)
        containerView.addSubview(closeButton)
        containerView.addSubview(segmentedControl)
        containerView.addSubview(tableView)
        containerView.addSubview(createButton)
        containerView.addSubview(stopLoopButton)

        containerView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.equalTo(ABLoopConstants.UI.containerWidth)
            make.height.equalTo(ABLoopConstants.UI.containerHeight)
        }

        titleLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(CGFloat.space16)
            make.leading.equalToSuperview().offset(CGFloat.space48)
            make.trailing.equalToSuperview().offset(-CGFloat.space48)
        }

        closeButton.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(CGFloat.space16)
            make.trailing.equalToSuperview().offset(-CGFloat.space16)
            make.width.height.equalTo(32)
        }

        segmentedControl.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(CGFloat.space16)
            make.leading.equalToSuperview().offset(CGFloat.space16)
            make.trailing.equalToSuperview().offset(-CGFloat.space16)
            make.height.equalTo(32)
        }

        tableView.snp.makeConstraints { make in
            make.top.equalTo(segmentedControl.snp.bottom).offset(CGFloat.space16)
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(createButton.snp.top).offset(-CGFloat.space16)
        }

        stopLoopButton.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(CGFloat.space16)
            make.bottom.equalToSuperview().offset(-CGFloat.space16)
            make.height.equalTo(ABLoopConstants.UI.buttonHeight)
            make.width.equalTo(120)
        }

        createButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-CGFloat.space16)
            make.bottom.equalToSuperview().offset(-CGFloat.space16)
            make.height.equalTo(ABLoopConstants.UI.buttonHeight)
            make.width.equalTo(200)
        }
    }

    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(ABLoopTableViewCell.self, forCellReuseIdentifier: "ABLoopCell")
    }

    /// Exposes what the panel's visual design implies: the card is modal, and the dimmed backdrop
    /// that dismisses it on tap is invisible to VoiceOver, so escape has to be provided explicitly
    /// (see `accessibilityPerformEscape()`).
    private func setupAccessibility() {
        containerView.accessibilityViewIsModal = true
        // The table's label depends on the selected mode and is set in `updateUI()`.
    }

    private func setupActions() {
        closeButton.addTarget(self, action: #selector(closeButtonTapped), for: .touchUpInside)
        createButton.addTarget(self, action: #selector(createButtonTapped), for: .touchUpInside)
        stopLoopButton.addTarget(self, action: #selector(stopLoopButtonTapped), for: .touchUpInside)
        segmentedControl.addTarget(self, action: #selector(segmentedControlChanged), for: .valueChanged)

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped))
        tapGesture.delegate = self
        view.addGestureRecognizer(tapGesture)
    }

    // MARK: - UI Updates

    private func updateUI() {
        createButton.setTitle(createButtonTitle, for: .normal)
        stopLoopButton.isHidden = !viewModel.hasActiveLoopOrPlaylist
        // The table shows a different collection in each mode, so its VoiceOver label has to
        // follow the segmented control rather than being set once.
        tableView.accessibilityLabel = listAccessibilityLabel
        tableView.reloadData()
    }

    /// Localized title for the create button in the current mode.
    ///
    /// Deliberately resolved here rather than through `ABLoopViewModel.createButtonTitle`: the
    /// view model's version returns the untranslated constant.
    private var createButtonTitle: String {
        switch viewModel.currentMode {
        case .abLoop:
            return CVPLocalized(
                "abloop.create",
                value: "Create New A-B Loop",
                comment: "Button that opens the A-B loop creation dialog"
            )
        case .segmentPlaylist:
            return CVPLocalized(
                "abloop.createSegmentPlaylist",
                value: "Create Segment Playlist",
                comment: "Button that opens the segment playlist creation dialog"
            )
        }
    }

    /// VoiceOver label for the list, matching whichever collection is on screen.
    private var listAccessibilityLabel: String {
        switch viewModel.currentMode {
        case .abLoop:
            return CVPLocalized(
                "abloop.list.accessibility",
                value: "Saved A-B loops",
                comment: "VoiceOver label for the list of saved A-B loops"
            )
        case .segmentPlaylist:
            return CVPLocalized(
                "abloop.segmentList.accessibility",
                value: "Saved segment playlists",
                comment: "VoiceOver label for the list of saved segment playlists"
            )
        }
    }

    // MARK: - Actions

    @objc private func closeButtonTapped() {
        dismissPanel()
    }

    /// Single dismissal path, so the Reduce Motion decision is made in exactly one place.
    private func dismissPanel() {
        dismiss(animated: !UIAccessibility.isReduceMotionEnabled)
    }

    /// Makes the VoiceOver escape gesture (a two-finger Z) close the panel.
    ///
    /// The backdrop tap that dismisses it is not reachable with VoiceOver on, and the close
    /// button can be a long swipe away from wherever focus happens to be.
    override func accessibilityPerformEscape() -> Bool {
        dismissPanel()
        return true
    }

    @objc private func createButtonTapped() {
        switch viewModel.currentMode {
        case .abLoop:
            presentABLoopCreationDialog()
        case .segmentPlaylist:
            presentSegmentPlaylistCreationDialog()
        }
    }

    @objc private func stopLoopButtonTapped() {
        delegate?.didSelectABLoop(nil)
        delegate?.didSelectSegmentPlaylist(nil)
        updateUI()
    }

    @objc private func segmentedControlChanged() {
        let newMode: ABLoopViewMode = segmentedControl.selectedSegmentIndex == 0 ? .abLoop : .segmentPlaylist
        viewModel.switchMode(to: newMode)
        updateUI()
    }

    @objc private func backgroundTapped(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: view)
        if !containerView.frame.contains(location) {
            dismissPanel()
        }
    }

    // MARK: - Helper Methods

    private func presentABLoopCreationDialog() {
        refreshPlaybackState()

        let creationViewController = ABLoopCreationViewController(
            frameRate: frameRate,
            currentTime: currentPlayerTime,
            duration: resolvedDuration,
            videoIdentifier: viewModel.videoIdentifier,
            abLoopManager: viewModel.abLoopManager
        )
        creationViewController.delegate = self
        creationViewController.modalPresentationStyle = .overFullScreen
        // A cross dissolve is the gentlest of the built-in transitions, and it is skipped outright
        // under Reduce Motion by presenting without animation.
        creationViewController.modalTransitionStyle = .crossDissolve
        present(creationViewController, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    private func presentSegmentPlaylistCreationDialog() {
        refreshPlaybackState()

        let creationViewController = SegmentPlaylistCreationViewController(
            frameRate: frameRate,
            currentTime: currentPlayerTime,
            duration: resolvedDuration,
            videoIdentifier: viewModel.videoIdentifier,
            abLoopManager: viewModel.abLoopManager
        )
        creationViewController.delegate = self
        present(creationViewController, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    /// Updates the current player time (called from parent when time changes)
    ///
    /// Also called from `refreshPlaybackState()` immediately before a creation dialog is
    /// opened, so "Set to Current Time" reflects the playhead now rather than whenever the
    /// panel happened to be opened.
    ///
    /// - Parameter time: The new playhead position
    func updateCurrentTime(_ time: CMTime) {
        currentPlayerTime = time
    }

    /// Updates the known duration of the video being edited
    ///
    /// - Parameter duration: The video's duration
    func updateVideoDuration(_ duration: CMTime) {
        videoDuration = duration
    }

    // MARK: - Playback State

    /// The player driving the video this panel edits, when it can be reached.
    ///
    /// The panel is presented by the player view controller, so walking the presentation
    /// chain is the one way back to live playback state that does not require the
    /// presenter to push updates in. Every hop is optional and read-only: a different
    /// presentation arrangement simply yields nil, and the panel falls back to the values
    /// it was constructed with.
    private var presentingPlayer: AVPlayer? {
        var candidate: UIViewController? = presentingViewController
        while let viewController = candidate {
            if let playerViewController = viewController as? VideoPlayerViewController {
                return playerViewController.player
            }
            candidate = viewController.presentingViewController
        }
        return nil
    }

    /// The duration to bounds-check timecodes against.
    ///
    /// Prefers whatever the presenter supplied and falls back to the presenting player's
    /// current item. An indefinite result means "unknown" — live streams and assets that
    /// have not loaded their duration yet — and callers skip the bound entirely.
    private var resolvedDuration: CMTime {
        if videoDuration.isNumeric {
            return videoDuration
        }
        guard let itemDuration = presentingPlayer?.currentItem?.duration, itemDuration.isNumeric else {
            return .indefinite
        }
        return itemDuration
    }

    /// Re-reads the playhead (and duration, if still unknown) from the presenting player.
    ///
    /// Called before opening a creation dialog. Together with dismissing the panel on
    /// selection — see `tableView(_:didSelectRowAt:)` — this removes the window in which a
    /// created loop could pick up a timestamp captured when the panel first opened.
    private func refreshPlaybackState() {
        guard let player = presentingPlayer else { return }

        let time = player.currentTime()
        if time.isNumeric {
            updateCurrentTime(time)
        }

        if !videoDuration.isNumeric,
           let itemDuration = player.currentItem?.duration,
           itemDuration.isNumeric {
            updateVideoDuration(itemDuration)
        }
    }
}

// MARK: - UITableViewDelegate, UITableViewDataSource

extension ABLoopViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return viewModel.itemCount
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ABLoopCell", for: indexPath) as! ABLoopTableViewCell

        switch viewModel.currentMode {
        case .abLoop:
            if let loop = viewModel.getABLoop(at: indexPath.row) {
                let displayInfo = viewModel.displayString(for: loop)
                let isActive = viewModel.isABLoopActive(at: indexPath.row)
                cell.configure(title: displayInfo.title, detail: displayInfo.detail, isActive: isActive)
            }
        case .segmentPlaylist:
            if let playlist = viewModel.getSegmentPlaylist(at: indexPath.row) {
                let displayInfo = viewModel.displayString(for: playlist)
                let isActive = viewModel.isSegmentPlaylistActive(at: indexPath.row)
                cell.configure(title: displayInfo.title, detail: displayInfo.detail, isActive: isActive)
            }
        }

        return cell
    }

    /// Activates the selected loop or playlist and closes the panel.
    ///
    /// Dismissing is part of the contract, not a nicety: the delegate resumes playback, so
    /// leaving the panel open would let it float over a moving playhead while still holding
    /// the timestamp it was constructed with. Closing here means a creation dialog is
    /// always opened from a freshly presented panel.
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        switch viewModel.currentMode {
        case .abLoop:
            guard let loop = viewModel.getABLoop(at: indexPath.row) else { return }
            delegate?.didSelectABLoop(loop)
            delegate?.didRequestSeek(to: loop.pointA.toCMTime())
        case .segmentPlaylist:
            guard let playlist = viewModel.getSegmentPlaylist(at: indexPath.row) else { return }
            delegate?.didSelectSegmentPlaylist(playlist)
            if let firstSegment = playlist.segments.first {
                delegate?.didRequestSeek(to: firstSegment.startPoint.toCMTime())
            }
        }

        updateUI()
        dismissPanel()
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }

        switch viewModel.currentMode {
        case .abLoop:
            viewModel.removeABLoop(at: indexPath.row)
        case .segmentPlaylist:
            viewModel.removeSegmentPlaylist(at: indexPath.row)
        }

        tableView.deleteRows(at: [indexPath], with: .fade)
        updateUI()
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return ABLoopConstants.UI.cellHeight
    }
}

// MARK: - UIGestureRecognizerDelegate

extension ABLoopViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        return touch.view == view
    }
}

// MARK: - ABLoopCreationViewControllerDelegate

extension ABLoopViewController: ABLoopCreationViewControllerDelegate {
    func didCreateABLoop(_ loop: ABLoop) {
        viewModel.loadData()
        updateUI()
    }
}

// MARK: - SegmentPlaylistCreationViewControllerDelegate

extension ABLoopViewController: SegmentPlaylistCreationViewControllerDelegate {
    /// Reloads the list so a freshly saved playlist appears — and is therefore
    /// selectable — without the panel having to be reopened.
    func didCreateSegmentPlaylist(_ playlist: SegmentPlaylist) {
        viewModel.loadData()
        updateUI()
    }
}

// MARK: - ABLoopTableViewCell

class ABLoopTableViewCell: UITableViewCell {
    private let titleLabel = UILabel().configure {
        $0.font = UIFontMetrics(forTextStyle: .headline).scaledFont(
            for: FontUtility.helveticaNeueBold(ofSize: 16),
            maximumPointSize: 22
        )
        $0.adjustsFontForContentSizeCategory = true
        $0.textColor = VideoPlayerColor(palette: .white).uiColor
    }

    private let detailLabel = UILabel().configure {
        $0.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(
            for: FontUtility.helveticaNeueLight(ofSize: 14),
            maximumPointSize: 20
        )
        $0.adjustsFontForContentSizeCategory = true
        $0.textColor = VideoPlayerColor(palette: .pearlWhite).uiColor
    }

    private let activeIndicator = UIView().configure {
        $0.backgroundColor = VideoPlayerColor(palette: .red).uiColor
        $0.layer.cornerRadius = ABLoopConstants.UI.activeIndicatorSize / 2
        $0.isHidden = true
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        contentView.addSubview(activeIndicator)
        contentView.addSubview(titleLabel)
        contentView.addSubview(detailLabel)

        activeIndicator.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(CGFloat.space16)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(ABLoopConstants.UI.activeIndicatorSize)
        }

        titleLabel.snp.makeConstraints { make in
            make.leading.equalTo(activeIndicator.snp.trailing).offset(CGFloat.space12)
            make.trailing.equalToSuperview().offset(-CGFloat.space16)
            make.top.equalToSuperview().offset(CGFloat.space12)
        }

        detailLabel.snp.makeConstraints { make in
            make.leading.equalTo(titleLabel.snp.leading)
            make.trailing.equalTo(titleLabel.snp.trailing)
            make.top.equalTo(titleLabel.snp.bottom).offset(4)
        }
    }

    func configure(title: String, detail: String, isActive: Bool) {
        titleLabel.text = title
        detailLabel.text = detail
        activeIndicator.isHidden = !isActive

        // The row is read as a single element: two separate labels plus a coloured dot would make
        // a VoiceOver user swipe three times to learn what one row says, and the dot — the only
        // thing marking the running loop — carries no text at all.
        isAccessibilityElement = true
        accessibilityTraits = .button
        let components: [String?] = [
            title,
            detail,
            isActive ? CVPLocalized(
                "abloop.active.accessibility",
                value: "Active",
                comment: "VoiceOver suffix marking the loop or playlist that is currently running"
            ) : nil,
        ]
        accessibilityLabel = components.compactMap { $0 }.joined(separator: ", ")
    }
}
