import UIKit
import AVFoundation
import SnapKit

/// Protocol for A-B loop creation delegate
protocol ABLoopCreationViewControllerDelegate: AnyObject {
    func didCreateABLoop(_ loop: ABLoop)
}

/// View controller for creating a new A-B loop
///
/// All input checking is delegated to `ABLoopValidation` rather than re-implemented here,
/// so the A-B loop and segment playlist flows reject the same inputs with the same
/// wording — including the duration bound, which is what stops a user from saving a loop
/// whose point B is past the end of the video and can therefore never fire.
class ABLoopCreationViewController: UIViewController {
    // MARK: - Properties

    weak var delegate: ABLoopCreationViewControllerDelegate?
    private let frameRate: Double
    private let currentTime: CMTime

    /// Duration of the video being edited, or an indefinite time when it is unknown.
    ///
    /// Live streams and assets whose duration has not loaded yet report a non-numeric
    /// `CMTime`; the bounds check is skipped in that case rather than rejecting every
    /// timecode against a meaningless bound.
    private let duration: CMTime
    private let videoIdentifier: String
    private let abLoopManager: ABLoopManager

    // MARK: - UI Components

    private let containerView = UIView().configure {
        $0.backgroundColor = VideoPlayerColor(palette: .black).uiColor.withAlphaComponent(0.95)
        $0.layer.cornerRadius = ABLoopConstants.UI.cornerRadius
    }

    /// Dynamic Type is applied with a cap throughout this dialog: it sizes itself to its content,
    /// so text may grow, but an uncapped accessibility size would push the buttons off screen.
    private let titleLabel = UILabel().configure {
        $0.text = CVPLocalized(
            "abloop.createTitle",
            value: "Create A-B Loop",
            comment: "Title of the dialog for creating an A-B loop"
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
            "abloop.nameLabel",
            value: "Loop Name (optional)",
            comment: "Field label above the A-B loop name text field"
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
            "abloop.namePlaceholder",
            value: "Loop name (optional)",
            comment: "Placeholder in the A-B loop name text field"
        )
        $0.accessibilityLabel = CVPLocalized(
            "abloop.nameLabel",
            value: "Loop Name (optional)",
            comment: "Field label above the A-B loop name text field"
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

    private let pointALabel = UILabel().configure {
        $0.text = CVPLocalized("abloop.pointA", value: "Point A", comment: "Label for the loop's start point")
        $0.font = UIFontMetrics(forTextStyle: .headline).scaledFont(
            for: FontUtility.helveticaNeueBold(ofSize: 16),
            maximumPointSize: 22
        )
        $0.adjustsFontForContentSizeCategory = true
        $0.textColor = VideoPlayerColor(palette: .white).uiColor
    }

    private lazy var pointATimecodeInput = TimecodeInputView(frameRate: frameRate)

    /// "Set to Current Time" appears twice, so each button says which point it sets — a VoiceOver
    /// user swiping through the form otherwise hears the same sentence twice with nothing to tell
    /// the two apart.
    private let setPointAButton = UIButton().configure {
        $0.setTitle(
            CVPLocalized(
                "abloop.setToCurrentTime",
                value: "Set to Current Time",
                comment: "Button that copies the playhead position into a timecode field"
            ),
            for: .normal
        )
        $0.accessibilityLabel = CVPLocalized(
            "abloop.setPointA.accessibility",
            value: "Set point A to the current playback time",
            comment: "VoiceOver label for the button that sets point A"
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

    private let pointBLabel = UILabel().configure {
        $0.text = CVPLocalized("abloop.pointB", value: "Point B", comment: "Label for the loop's end point")
        $0.font = UIFontMetrics(forTextStyle: .headline).scaledFont(
            for: FontUtility.helveticaNeueBold(ofSize: 16),
            maximumPointSize: 22
        )
        $0.adjustsFontForContentSizeCategory = true
        $0.textColor = VideoPlayerColor(palette: .white).uiColor
    }

    private lazy var pointBTimecodeInput = TimecodeInputView(frameRate: frameRate)

    private let setPointBButton = UIButton().configure {
        $0.setTitle(
            CVPLocalized(
                "abloop.setToCurrentTime",
                value: "Set to Current Time",
                comment: "Button that copies the playhead position into a timecode field"
            ),
            for: .normal
        )
        $0.accessibilityLabel = CVPLocalized(
            "abloop.setPointB.accessibility",
            value: "Set point B to the current playback time",
            comment: "VoiceOver label for the button that sets point B"
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

    private let createButton = UIButton().configure {
        $0.setTitle(
            CVPLocalized("abloop.createLoop", value: "Create Loop", comment: "Button that saves the new A-B loop"),
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

    /// Initializes the creation dialog
    ///
    /// - Parameters:
    ///   - frameRate: Frame rate of the video, used for frame-accurate timecode entry
    ///   - currentTime: Playhead position used by the "Set to Current Time" buttons
    ///   - duration: Duration of the video, or an indefinite time when it is unknown
    ///   - videoIdentifier: Identifier of the video the loop is created for
    ///   - abLoopManager: Manager the created loop is stored in
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
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        setupActions()
        setupKeyboardHandling()
        // The dialog covers everything behind it, so VoiceOver must not be able to wander into
        // the panel it was opened from.
        containerView.accessibilityViewIsModal = true
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
        containerView.addSubview(pointALabel)
        containerView.addSubview(pointATimecodeInput)
        containerView.addSubview(setPointAButton)
        containerView.addSubview(pointBLabel)
        containerView.addSubview(pointBTimecodeInput)
        containerView.addSubview(setPointBButton)
        containerView.addSubview(cancelButton)
        containerView.addSubview(createButton)

        containerView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.equalTo(ABLoopConstants.UI.creationDialogWidth)
        }

        titleLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(CGFloat.space24)
            make.leading.trailing.equalToSuperview().inset(CGFloat.space24)
        }

        nameLabel.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(CGFloat.space24)
            make.leading.trailing.equalToSuperview().inset(CGFloat.space24)
        }

        nameTextField.snp.makeConstraints { make in
            make.top.equalTo(nameLabel.snp.bottom).offset(CGFloat.space8)
            make.leading.trailing.equalToSuperview().inset(CGFloat.space24)
            make.height.equalTo(ABLoopConstants.UI.buttonHeight)
        }

        pointALabel.snp.makeConstraints { make in
            make.top.equalTo(nameTextField.snp.bottom).offset(CGFloat.space24)
            make.leading.trailing.equalToSuperview().inset(CGFloat.space24)
        }

        pointATimecodeInput.snp.makeConstraints { make in
            make.top.equalTo(pointALabel.snp.bottom).offset(CGFloat.space8)
            make.leading.trailing.equalToSuperview().inset(CGFloat.space24)
        }

        setPointAButton.snp.makeConstraints { make in
            make.top.equalTo(pointATimecodeInput.snp.bottom).offset(CGFloat.space8)
            make.leading.trailing.equalToSuperview().inset(CGFloat.space24)
            make.height.equalTo(ABLoopConstants.UI.smallButtonHeight)
        }

        pointBLabel.snp.makeConstraints { make in
            make.top.equalTo(setPointAButton.snp.bottom).offset(CGFloat.space24)
            make.leading.trailing.equalToSuperview().inset(CGFloat.space24)
        }

        pointBTimecodeInput.snp.makeConstraints { make in
            make.top.equalTo(pointBLabel.snp.bottom).offset(CGFloat.space8)
            make.leading.trailing.equalToSuperview().inset(CGFloat.space24)
        }

        setPointBButton.snp.makeConstraints { make in
            make.top.equalTo(pointBTimecodeInput.snp.bottom).offset(CGFloat.space8)
            make.leading.trailing.equalToSuperview().inset(CGFloat.space24)
            make.height.equalTo(ABLoopConstants.UI.smallButtonHeight)
        }

        cancelButton.snp.makeConstraints { make in
            make.top.equalTo(setPointBButton.snp.bottom).offset(CGFloat.space24)
            make.leading.equalToSuperview().offset(CGFloat.space24)
            make.width.equalTo(120)
            make.height.equalTo(ABLoopConstants.UI.buttonHeight)
            make.bottom.equalToSuperview().offset(-CGFloat.space24)
        }

        createButton.snp.makeConstraints { make in
            make.top.equalTo(cancelButton.snp.top)
            make.trailing.equalToSuperview().offset(-CGFloat.space24)
            make.leading.equalTo(cancelButton.snp.trailing).offset(CGFloat.space16)
            make.height.equalTo(ABLoopConstants.UI.buttonHeight)
        }
    }

    private func setupActions() {
        setPointAButton.addTarget(self, action: #selector(setPointAToCurrentTime), for: .touchUpInside)
        setPointBButton.addTarget(self, action: #selector(setPointBToCurrentTime), for: .touchUpInside)
        cancelButton.addTarget(self, action: #selector(cancelButtonTapped), for: .touchUpInside)
        createButton.addTarget(self, action: #selector(createButtonTapped), for: .touchUpInside)
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
        view.addGestureRecognizer(tapGesture)
    }

    // MARK: - Actions

    @objc private func setPointAToCurrentTime() {
        // `TimePoint(from:)` converts through `Int(CMTimeGetSeconds(_:))`, which traps on
        // the NaN a non-numeric time produces, so an unknown playhead is ignored instead.
        guard currentTime.isNumeric else { return }
        pointATimecodeInput.setTimecode(TimePoint(from: currentTime, frameRate: frameRate))
    }

    @objc private func setPointBToCurrentTime() {
        guard currentTime.isNumeric else { return }
        pointBTimecodeInput.setTimecode(TimePoint(from: currentTime, frameRate: frameRate))
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

    @objc private func createButtonTapped() {
        view.endEditing(true)

        guard let pointA = pointATimecodeInput.getTimecode(),
              let pointB = pointBTimecodeInput.getTimecode() else {
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

        if let message = ABLoopValidation.validateLoopRange(pointA: pointA, pointB: pointB).errorMessage {
            showAlert(
                title: CVPLocalized(
                    "validation.invalidRangeTitle",
                    value: "Invalid Range",
                    comment: "Title of the alert shown when point B does not come after point A"
                ),
                message: message
            )
            return
        }

        if let message = durationErrorMessage(for: pointA) ?? durationErrorMessage(for: pointB) {
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

        let trimmedName = nameTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let abLoop = ABLoop(
            pointA: pointA,
            pointB: pointB,
            name: trimmedName.isEmpty ? nil : trimmedName,
            videoIdentifier: videoIdentifier
        )

        abLoopManager.addABLoop(abLoop, for: videoIdentifier)
        delegate?.didCreateABLoop(abLoop)

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
    /// - Parameter point: Point to bounds-check
    /// - Returns: An error message, or nil when the point is in range or the duration is unknown
    private func durationErrorMessage(for point: TimePoint) -> String? {
        guard duration.isNumeric, duration > .zero else {
            return nil
        }
        return ABLoopValidation.validateTimePointWithinDuration(point, duration: duration).errorMessage
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
