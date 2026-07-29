import UIKit
import AVFoundation
import SnapKit

/// Protocol for segment playlist creation delegate
protocol SegmentPlaylistCreationViewControllerDelegate: AnyObject {
    func didCreateSegmentPlaylist(_ playlist: SegmentPlaylist)
}

/// View controller for creating a new segment playlist
///
/// A playlist is assembled one segment at a time: each segment is a start/end pair entered
/// through `TimecodeInputView` (which validates every keystroke against the video's frame
/// rate), appended to an ordered list that can be reordered or pruned, and finally stored
/// through `ABLoopManager.addSegmentPlaylist(_:for:)`.
///
/// Segments carry no user-supplied name. Their display name is derived from `order`, so it
/// stays correct after a reorder instead of describing where a segment used to sit.
///
/// Input checking is delegated to `ABLoopValidation` — the same rules the A-B loop dialog
/// applies, including the video-duration bound.
final class SegmentPlaylistCreationViewController: UIViewController {
    // MARK: - Properties

    weak var delegate: SegmentPlaylistCreationViewControllerDelegate?

    private let frameRate: Double
    private let currentTime: CMTime

    /// Duration of the video being edited, or an indefinite time when it is unknown.
    ///
    /// See `durationErrorMessage(for:)` for why an unknown duration skips the check.
    private let duration: CMTime
    private let videoIdentifier: String
    private let abLoopManager: ABLoopManager

    /// Segments added so far, always renumbered so `order` matches the row index.
    ///
    /// `ABLoopValidation.validateSegmentPlaylist(_:)` requires exactly that, and keeping
    /// the invariant here means a reorder can never produce a playlist that fails to save.
    private var segments: [PlaybackSegment] = []

    private let segmentCellReuseIdentifier = "SegmentPlaylistSegmentCell"

    // MARK: - UI Components

    private let containerView = UIView().configure {
        $0.backgroundColor = VideoPlayerColor(palette: .black).uiColor.withAlphaComponent(0.95)
        $0.layer.cornerRadius = ABLoopConstants.UI.cornerRadius
    }

    /// Dynamic Type is applied with a cap throughout this dialog: its container has a fixed
    /// height, so text follows the user's size setting but cannot push the segment list out of it.
    private let titleLabel = UILabel().configure {
        $0.text = CVPLocalized(
            "segment.createTitle",
            value: "Create Segment Playlist",
            comment: "Title of the dialog for creating a segment playlist"
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

    private let nameLabel = UILabel().configure {
        $0.text = CVPLocalized(
            "segment.nameLabel",
            value: "Playlist Name (optional)",
            comment: "Field label above the playlist name text field"
        )
        $0.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(
            for: FontUtility.helveticaNeueRegular(ofSize: 14),
            maximumPointSize: 20
        )
        $0.adjustsFontForContentSizeCategory = true
        $0.textColor = VideoPlayerColor(palette: .pearlWhite).uiColor
        $0.numberOfLines = 0
    }

    private let nameTextField = UITextField().configure {
        $0.placeholder = CVPLocalized(
            "segment.name",
            value: "Playlist name",
            comment: "Placeholder in the playlist name text field"
        )
        $0.accessibilityLabel = CVPLocalized(
            "segment.nameLabel",
            value: "Playlist Name (optional)",
            comment: "Field label above the playlist name text field"
        )
        $0.font = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: FontUtility.helveticaNeueRegular(ofSize: 16),
            maximumPointSize: 22
        )
        $0.adjustsFontForContentSizeCategory = true
        $0.textColor = VideoPlayerColor(palette: .white).uiColor
        $0.backgroundColor = VideoPlayerColor(palette: .black).uiColor.withAlphaComponent(0.3)
        $0.layer.cornerRadius = ABLoopConstants.UI.cornerRadius
        $0.leftView = UIView(frame: CGRect(x: 0, y: 0, width: CGFloat.space12, height: 0))
        $0.leftViewMode = .always
    }

    private let loopingLabel = UILabel().configure {
        $0.text = CVPLocalized(
            "segment.loopPlaylist",
            value: "Loop playlist",
            comment: "Label for the switch that repeats the playlist from the start"
        )
        $0.font = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: FontUtility.helveticaNeueRegular(ofSize: 16),
            maximumPointSize: 22
        )
        $0.adjustsFontForContentSizeCategory = true
        $0.textColor = VideoPlayerColor(palette: .white).uiColor
        $0.numberOfLines = 0
    }

    /// The switch sits next to a separate label, which VoiceOver has no way to associate with it,
    /// so it carries the same text itself.
    private let loopingSwitch = UISwitch().configure {
        $0.onTintColor = VideoPlayerColor(palette: .red).uiColor
        $0.isOn = false
        $0.accessibilityLabel = CVPLocalized(
            "segment.loopPlaylist",
            value: "Loop playlist",
            comment: "Label for the switch that repeats the playlist from the start"
        )
    }

    private let startLabel = UILabel().configure {
        $0.text = CVPLocalized("segment.start", value: "Start", comment: "Label for a segment's start timecode")
        $0.font = UIFontMetrics(forTextStyle: .headline).scaledFont(
            for: FontUtility.helveticaNeueBold(ofSize: 16),
            maximumPointSize: 22
        )
        $0.adjustsFontForContentSizeCategory = true
        $0.textColor = VideoPlayerColor(palette: .white).uiColor
    }

    private lazy var startTimecodeInput = TimecodeInputView(frameRate: frameRate)

    /// "Set to Current Time" appears twice, so each button says which end of the segment it sets.
    private let setStartButton = UIButton().configure {
        $0.setTitle(
            CVPLocalized(
                "abloop.setToCurrentTime",
                value: "Set to Current Time",
                comment: "Button that copies the playhead position into a timecode field"
            ),
            for: .normal
        )
        $0.accessibilityLabel = CVPLocalized(
            "segment.setStart.accessibility",
            value: "Set the segment start to the current playback time",
            comment: "VoiceOver label for the button that sets a segment's start"
        )
        $0.titleLabel?.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(
            for: FontUtility.helveticaNeueRegular(ofSize: 14),
            maximumPointSize: 20
        )
        $0.titleLabel?.adjustsFontForContentSizeCategory = true
        $0.setTitleColor(VideoPlayerColor(palette: .white).uiColor, for: .normal)
        $0.backgroundColor = VideoPlayerColor(palette: .red).uiColor.withAlphaComponent(0.7)
        $0.layer.cornerRadius = ABLoopConstants.UI.smallCornerRadius
    }

    private let endLabel = UILabel().configure {
        $0.text = CVPLocalized("segment.end", value: "End", comment: "Label for a segment's end timecode")
        $0.font = UIFontMetrics(forTextStyle: .headline).scaledFont(
            for: FontUtility.helveticaNeueBold(ofSize: 16),
            maximumPointSize: 22
        )
        $0.adjustsFontForContentSizeCategory = true
        $0.textColor = VideoPlayerColor(palette: .white).uiColor
    }

    private lazy var endTimecodeInput = TimecodeInputView(frameRate: frameRate)

    private let setEndButton = UIButton().configure {
        $0.setTitle(
            CVPLocalized(
                "abloop.setToCurrentTime",
                value: "Set to Current Time",
                comment: "Button that copies the playhead position into a timecode field"
            ),
            for: .normal
        )
        $0.accessibilityLabel = CVPLocalized(
            "segment.setEnd.accessibility",
            value: "Set the segment end to the current playback time",
            comment: "VoiceOver label for the button that sets a segment's end"
        )
        $0.titleLabel?.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(
            for: FontUtility.helveticaNeueRegular(ofSize: 14),
            maximumPointSize: 20
        )
        $0.titleLabel?.adjustsFontForContentSizeCategory = true
        $0.setTitleColor(VideoPlayerColor(palette: .white).uiColor, for: .normal)
        $0.backgroundColor = VideoPlayerColor(palette: .red).uiColor.withAlphaComponent(0.7)
        $0.layer.cornerRadius = ABLoopConstants.UI.smallCornerRadius
    }

    private let addSegmentButton = UIButton().configure {
        $0.setTitle(
            CVPLocalized(
                "segment.addSegment",
                value: "Add Segment",
                comment: "Button that appends the entered start and end to the playlist"
            ),
            for: .normal
        )
        $0.titleLabel?.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: FontUtility.helveticaNeueBold(ofSize: 15),
            maximumPointSize: 21
        )
        $0.titleLabel?.adjustsFontForContentSizeCategory = true
        $0.setTitleColor(VideoPlayerColor(palette: .white).uiColor, for: .normal)
        $0.backgroundColor = VideoPlayerColor(palette: .red).uiColor.withAlphaComponent(0.7)
        $0.layer.cornerRadius = ABLoopConstants.UI.smallCornerRadius
    }

    private let segmentsHeaderLabel = UILabel().configure {
        $0.text = CVPLocalized("segment.header", value: "Segments", comment: "Header above the segment list")
        $0.font = UIFontMetrics(forTextStyle: .headline).scaledFont(
            for: FontUtility.helveticaNeueBold(ofSize: 16),
            maximumPointSize: 22
        )
        $0.adjustsFontForContentSizeCategory = true
        $0.textColor = VideoPlayerColor(palette: .white).uiColor
        $0.accessibilityTraits = .header
    }

    private let tableView = UITableView().configure {
        $0.backgroundColor = .clear
        $0.separatorStyle = .singleLine
        $0.separatorColor = VideoPlayerColor(palette: .pearlWhite).uiColor.withAlphaComponent(0.3)
    }

    private let emptyStateLabel = UILabel().configure {
        $0.text = CVPLocalized(
            "segment.empty",
            value: "No segments yet. Add a start and end point above.",
            comment: "Shown in place of the segment list while the playlist is empty"
        )
        $0.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(
            for: FontUtility.helveticaNeueLight(ofSize: 14),
            maximumPointSize: 20
        )
        $0.adjustsFontForContentSizeCategory = true
        $0.textColor = VideoPlayerColor(palette: .pearlWhite).uiColor
        $0.textAlignment = .center
        $0.numberOfLines = 0
    }

    private let cancelButton = UIButton().configure {
        $0.setTitle(
            CVPLocalized("abloop.cancel", value: "Cancel", comment: "Button that closes a dialog without saving"),
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
    }

    private let saveButton = UIButton().configure {
        $0.setTitle(
            CVPLocalized("segment.save", value: "Save Playlist", comment: "Button that saves the new playlist"),
            for: .normal
        )
        $0.titleLabel?.font = UIFontMetrics(forTextStyle: .headline).scaledFont(
            for: FontUtility.helveticaNeueBold(ofSize: 16),
            maximumPointSize: 22
        )
        $0.titleLabel?.adjustsFontForContentSizeCategory = true
        $0.setTitleColor(VideoPlayerColor(palette: .white).uiColor, for: .normal)
        $0.backgroundColor = VideoPlayerColor(palette: .red).uiColor
        $0.layer.cornerRadius = ABLoopConstants.UI.cornerRadius
    }

    // MARK: - Initialization

    /// Initializes the segment playlist creation dialog
    ///
    /// - Parameters:
    ///   - frameRate: Frame rate of the video, used for frame-accurate timecode entry
    ///   - currentTime: Playhead position used by the "Set to Current Time" buttons
    ///   - duration: Duration of the video, or an indefinite time when it is unknown
    ///   - videoIdentifier: Identifier of the video the playlist is created for
    ///   - abLoopManager: Manager the created playlist is stored in
    init(
        frameRate: Double,
        currentTime: CMTime,
        duration: CMTime,
        videoIdentifier: String,
        abLoopManager: ABLoopManager
    ) {
        // A bogus frame rate would make every frame value invalid, so fall back to the
        // library default rather than presenting an unusable dialog.
        self.frameRate = ABLoopValidation.validateFrameRate(frameRate).isValid
            ? frameRate
            : ABLoopConstants.defaultFrameRate
        self.currentTime = currentTime
        self.duration = duration
        self.videoIdentifier = videoIdentifier
        self.abLoopManager = abLoopManager
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
        setupKeyboardHandling()
        setupAccessibility()
        updateSegmentList()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Announce the new screen and land focus on its title rather than on whichever element
        // happens to be first in the layout.
        UIAccessibility.post(notification: .screenChanged, argument: titleLabel)
    }

    // MARK: - Setup

    private func setupViews() {
        view.backgroundColor = UIColor.black.withAlphaComponent(0.7)

        view.addSubview(containerView)
        containerView.addSubview(titleLabel)
        containerView.addSubview(nameLabel)
        containerView.addSubview(nameTextField)
        containerView.addSubview(loopingLabel)
        containerView.addSubview(loopingSwitch)
        containerView.addSubview(startLabel)
        containerView.addSubview(startTimecodeInput)
        containerView.addSubview(setStartButton)
        containerView.addSubview(endLabel)
        containerView.addSubview(endTimecodeInput)
        containerView.addSubview(setEndButton)
        containerView.addSubview(addSegmentButton)
        containerView.addSubview(segmentsHeaderLabel)
        containerView.addSubview(tableView)
        containerView.addSubview(emptyStateLabel)
        containerView.addSubview(cancelButton)
        containerView.addSubview(saveButton)

        containerView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.equalTo(ABLoopConstants.UI.segmentPlaylistDialogWidth)
            make.height.equalTo(ABLoopConstants.UI.segmentPlaylistDialogHeight)
        }

        titleLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(CGFloat.space24)
            make.leading.trailing.equalToSuperview().inset(CGFloat.space24)
        }

        nameLabel.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(CGFloat.space16)
            make.leading.trailing.equalToSuperview().inset(CGFloat.space24)
        }

        nameTextField.snp.makeConstraints { make in
            make.top.equalTo(nameLabel.snp.bottom).offset(CGFloat.space8)
            make.leading.trailing.equalToSuperview().inset(CGFloat.space24)
            make.height.equalTo(ABLoopConstants.UI.buttonHeight)
        }

        loopingLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(CGFloat.space24)
            make.centerY.equalTo(loopingSwitch.snp.centerY)
        }

        loopingSwitch.snp.makeConstraints { make in
            make.top.equalTo(nameTextField.snp.bottom).offset(CGFloat.space16)
            make.trailing.equalToSuperview().offset(-CGFloat.space24)
        }

        // Start and end are laid out as two columns so the segment list below keeps room.
        startLabel.snp.makeConstraints { make in
            make.top.equalTo(loopingSwitch.snp.bottom).offset(CGFloat.space16)
            make.leading.equalToSuperview().offset(CGFloat.space24)
            make.trailing.equalTo(containerView.snp.centerX).offset(-CGFloat.space8)
        }

        startTimecodeInput.snp.makeConstraints { make in
            make.top.equalTo(startLabel.snp.bottom).offset(CGFloat.space8)
            make.leading.equalTo(startLabel.snp.leading)
            make.trailing.equalTo(startLabel.snp.trailing)
        }

        setStartButton.snp.makeConstraints { make in
            make.top.equalTo(startTimecodeInput.snp.bottom).offset(CGFloat.space8)
            make.leading.equalTo(startLabel.snp.leading)
            make.trailing.equalTo(startLabel.snp.trailing)
            make.height.equalTo(ABLoopConstants.UI.smallButtonHeight)
        }

        endLabel.snp.makeConstraints { make in
            make.top.equalTo(startLabel.snp.top)
            make.leading.equalTo(containerView.snp.centerX).offset(CGFloat.space8)
            make.trailing.equalToSuperview().offset(-CGFloat.space24)
        }

        endTimecodeInput.snp.makeConstraints { make in
            make.top.equalTo(endLabel.snp.bottom).offset(CGFloat.space8)
            make.leading.equalTo(endLabel.snp.leading)
            make.trailing.equalTo(endLabel.snp.trailing)
        }

        setEndButton.snp.makeConstraints { make in
            make.top.equalTo(endTimecodeInput.snp.bottom).offset(CGFloat.space8)
            make.leading.equalTo(endLabel.snp.leading)
            make.trailing.equalTo(endLabel.snp.trailing)
            make.height.equalTo(ABLoopConstants.UI.smallButtonHeight)
        }

        addSegmentButton.snp.makeConstraints { make in
            make.top.equalTo(setStartButton.snp.bottom).offset(CGFloat.space12)
            make.leading.trailing.equalToSuperview().inset(CGFloat.space24)
            make.height.equalTo(ABLoopConstants.UI.smallButtonHeight)
        }

        segmentsHeaderLabel.snp.makeConstraints { make in
            make.top.equalTo(addSegmentButton.snp.bottom).offset(CGFloat.space16)
            make.leading.trailing.equalToSuperview().inset(CGFloat.space24)
        }

        tableView.snp.makeConstraints { make in
            make.top.equalTo(segmentsHeaderLabel.snp.bottom).offset(CGFloat.space8)
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(cancelButton.snp.top).offset(-CGFloat.space16)
        }

        emptyStateLabel.snp.makeConstraints { make in
            make.centerY.equalTo(tableView.snp.centerY)
            make.leading.trailing.equalToSuperview().inset(CGFloat.space24)
        }

        cancelButton.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(CGFloat.space24)
            make.bottom.equalToSuperview().offset(-CGFloat.space24)
            make.width.equalTo(120)
            make.height.equalTo(ABLoopConstants.UI.buttonHeight)
        }

        saveButton.snp.makeConstraints { make in
            make.top.equalTo(cancelButton.snp.top)
            make.leading.equalTo(cancelButton.snp.trailing).offset(CGFloat.space16)
            make.trailing.equalToSuperview().offset(-CGFloat.space24)
            make.height.equalTo(ABLoopConstants.UI.buttonHeight)
        }
    }

    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(ABLoopTableViewCell.self, forCellReuseIdentifier: segmentCellReuseIdentifier)
        // Permanent edit mode is what surfaces the reorder grips and the delete controls
        // together; rows are never "selected" here, they are only rearranged or removed.
        tableView.allowsSelection = false
        tableView.allowsSelectionDuringEditing = false
        tableView.setEditing(true, animated: false)
    }

    /// Exposes what the dialog's visual design implies: it covers the panel behind it, so VoiceOver
    /// must not be able to wander back into it, and the segment list needs a name of its own.
    private func setupAccessibility() {
        containerView.accessibilityViewIsModal = true
        tableView.accessibilityLabel = CVPLocalized(
            "segment.list.accessibility",
            value: "Segments in this playlist",
            comment: "VoiceOver label for the list of segments being assembled"
        )
    }

    private func setupActions() {
        setStartButton.addTarget(self, action: #selector(setStartToCurrentTime), for: .touchUpInside)
        setEndButton.addTarget(self, action: #selector(setEndToCurrentTime), for: .touchUpInside)
        addSegmentButton.addTarget(self, action: #selector(addSegmentButtonTapped), for: .touchUpInside)
        cancelButton.addTarget(self, action: #selector(cancelButtonTapped), for: .touchUpInside)
        saveButton.addTarget(self, action: #selector(saveButtonTapped), for: .touchUpInside)
    }

    private func setupKeyboardHandling() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tapGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(tapGesture)
    }

    // MARK: - UI Updates

    /// Reflects `segments` in the table, the empty state, and the save button.
    private func updateSegmentList() {
        emptyStateLabel.isHidden = !segments.isEmpty
        saveButton.isEnabled = !segments.isEmpty
        saveButton.alpha = segments.isEmpty ? 0.5 : 1
        tableView.reloadData()
    }

    /// Rewrites `order` so it matches each segment's position in the list.
    ///
    /// Called after every insertion, deletion and move; `ABLoopValidation` rejects a
    /// playlist whose sorted orders are not 0, 1, 2, …
    private func renumberSegments() {
        segments = segments.enumerated().map { index, segment in
            PlaybackSegment(
                id: segment.id,
                startPoint: segment.startPoint,
                endPoint: segment.endPoint,
                order: index,
                name: segment.name
            )
        }
    }

    // MARK: - Actions

    @objc private func setStartToCurrentTime() {
        // `TimePoint(from:)` converts through `Int(CMTimeGetSeconds(_:))`, which traps on
        // the NaN a non-numeric time produces, so an unknown playhead is ignored instead.
        guard currentTime.isNumeric else { return }
        startTimecodeInput.setTimecode(TimePoint(from: currentTime, frameRate: frameRate))
    }

    @objc private func setEndToCurrentTime() {
        guard currentTime.isNumeric else { return }
        endTimecodeInput.setTimecode(TimePoint(from: currentTime, frameRate: frameRate))
    }

    @objc private func addSegmentButtonTapped() {
        view.endEditing(true)

        guard let startPoint = startTimecodeInput.getTimecode(),
              let endPoint = endTimecodeInput.getTimecode() else {
            showAlert(
                title: CVPLocalized(
                    "validation.invalidTitle",
                    value: "Invalid Input",
                    comment: "Title of the alert shown when a timecode cannot be read"
                ),
                message: CVPLocalized(
                    "validation.invalidTimecodes",
                    value: "Please enter valid timecodes.",
                    comment: "Alert message shown when a timecode cannot be read"
                )
            )
            return
        }

        if let message = ABLoopValidation.validateLoopRange(pointA: startPoint, pointB: endPoint).errorMessage {
            showAlert(
                title: CVPLocalized(
                    "validation.invalidRangeTitle",
                    value: "Invalid Range",
                    comment: "Title of the alert shown when the end does not come after the start"
                ),
                message: message
            )
            return
        }

        if let message = durationErrorMessage(for: startPoint) ?? durationErrorMessage(for: endPoint) {
            showAlert(
                title: CVPLocalized(
                    "validation.beyondDurationTitle",
                    value: "Beyond Video End",
                    comment: "Title of the alert shown when a point lies past the end of the video"
                ),
                message: message
            )
            return
        }

        segments.append(
            PlaybackSegment(startPoint: startPoint, endPoint: endPoint, order: segments.count)
        )

        startTimecodeInput.clear()
        endTimecodeInput.clear()
        updateSegmentList()

        // Adding a segment only changes a list further down the dialog, which a VoiceOver user
        // never sees; without an announcement the button appears to do nothing at all.
        UIAccessibility.post(
            notification: .announcement,
            argument: String(
                format: CVPLocalized(
                    "segment.added.accessibility",
                    value: "Segment %d added",
                    comment: "Announced after a segment is appended; %d is its 1-based position"
                ),
                segments.count
            )
        )
    }

    @objc private func cancelButtonTapped() {
        dismissDialog()
    }

    /// Single dismissal path, so the Reduce Motion decision is made in exactly one place.
    private func dismissDialog() {
        dismiss(animated: !UIAccessibility.isReduceMotionEnabled)
    }

    /// Makes the VoiceOver escape gesture (a two-finger Z) cancel the dialog.
    override func accessibilityPerformEscape() -> Bool {
        dismissDialog()
        return true
    }

    @objc private func saveButtonTapped() {
        view.endEditing(true)

        let trimmedName = nameTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let defaultName = CVPLocalized(
            "segment.defaultName",
            value: "Segment Playlist",
            comment: "Name given to a playlist the user did not name"
        )
        let playlist = SegmentPlaylist(
            name: trimmedName.isEmpty ? defaultName : trimmedName,
            segments: segments,
            videoIdentifier: videoIdentifier,
            isLooping: loopingSwitch.isOn
        )

        if let message = ABLoopValidation.validateSegmentPlaylist(playlist).errorMessage {
            showAlert(
                title: CVPLocalized(
                    "validation.invalidPlaylistTitle",
                    value: "Invalid Playlist",
                    comment: "Title of the alert shown when a playlist cannot be saved"
                ),
                message: message
            )
            return
        }

        abLoopManager.addSegmentPlaylist(playlist, for: videoIdentifier)
        delegate?.didCreateSegmentPlaylist(playlist)

        dismissDialog()
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    @objc private func keyboardWillShow(notification: NSNotification) {
        if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue {
            let keyboardHeight = keyboardFrame.cgRectValue.height
            UIView.animate(withDuration: keyboardAnimationDuration) {
                self.containerView.transform = CGAffineTransform(
                    translationX: 0,
                    y: -keyboardHeight / ABLoopConstants.Animation.keyboardOffsetDivisor
                )
            }
        }
    }

    @objc private func keyboardWillHide(notification: NSNotification) {
        UIView.animate(withDuration: keyboardAnimationDuration) {
            self.containerView.transform = .identity
        }
    }

    /// Duration for the keyboard-avoidance shift.
    ///
    /// Zero under Reduce Motion: the dialog still has to move out of the keyboard's way, but it
    /// does so instantly rather than sliding.
    private var keyboardAnimationDuration: TimeInterval {
        UIAccessibility.isReduceMotionEnabled ? 0 : ABLoopConstants.Animation.duration
    }

    // MARK: - Helper Methods

    /// Returns the message to show when a point lies past the end of the video
    ///
    /// A live stream, or an asset whose duration has not loaded yet, reports a
    /// non-numeric `CMTime`; there is no bound to check in that case, so entry is allowed
    /// rather than rejected against a meaningless value.
    ///
    /// - Parameter point: Point to bounds-check
    /// - Returns: An error message, or nil when the point is in range or the duration is unknown
    private func durationErrorMessage(for point: TimePoint) -> String? {
        guard duration.isNumeric, duration > .zero else {
            return nil
        }
        return ABLoopValidation.validateTimePointWithinDuration(point, duration: duration).errorMessage
    }

    /// Returns the row title and detail text for a segment
    ///
    /// - Parameter segment: Segment to describe
    /// - Returns: Title and detail strings for the cell
    private func displayString(for segment: PlaybackSegment) -> (title: String, detail: String) {
        let title = segment.name ?? String(
            format: CVPLocalized(
                "segment.rowTitle",
                value: "Segment %d",
                comment: "Segment row title; %d is the segment's 1-based position in the playlist"
            ),
            segment.order + 1
        )
        let detail = "\(segment.startPoint.toString()) → \(segment.endPoint.toString())"
        return (title, detail)
    }

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(
            title: CVPLocalized("validation.ok", value: "OK", comment: "Button that dismisses a validation alert"),
            style: .default
        ))
        present(alert, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - UITableViewDelegate, UITableViewDataSource

extension SegmentPlaylistCreationViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return segments.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: segmentCellReuseIdentifier,
            for: indexPath
        )

        guard let segmentCell = cell as? ABLoopTableViewCell, indexPath.row < segments.count else {
            return cell
        }

        let displayInfo = displayString(for: segments[indexPath.row])
        segmentCell.configure(title: displayInfo.title, detail: displayInfo.detail, isActive: false)
        return segmentCell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return ABLoopConstants.UI.cellHeight
    }

    func tableView(
        _ tableView: UITableView,
        editingStyleForRowAt indexPath: IndexPath
    ) -> UITableViewCell.EditingStyle {
        return .delete
    }

    func tableView(
        _ tableView: UITableView,
        commit editingStyle: UITableViewCell.EditingStyle,
        forRowAt indexPath: IndexPath
    ) {
        guard editingStyle == .delete, indexPath.row < segments.count else { return }

        segments.remove(at: indexPath.row)
        renumberSegments()
        // Every remaining row's ordinal shifts, so the table is reloaded wholesale rather
        // than animating a single deletion against stale titles.
        updateSegmentList()
    }

    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        return true
    }

    func tableView(
        _ tableView: UITableView,
        moveRowAt sourceIndexPath: IndexPath,
        to destinationIndexPath: IndexPath
    ) {
        guard sourceIndexPath.row < segments.count, destinationIndexPath.row < segments.count else {
            return
        }

        let moved = segments.remove(at: sourceIndexPath.row)
        segments.insert(moved, at: destinationIndexPath.row)
        renumberSegments()

        // The table has already animated the move, so reloading is deferred out of the
        // move callback; reloading inside it fights the in-flight animation.
        DispatchQueue.main.async { [weak self] in
            self?.updateSegmentList()
        }
    }
}
