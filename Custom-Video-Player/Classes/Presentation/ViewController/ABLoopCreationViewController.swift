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

    private let titleLabel = UILabel().configure {
        $0.text = ABLoopConstants.Strings.createLoopTitle
        $0.font = FontUtility.helveticaNeueBold(ofSize: 20)
        $0.textColor = VideoPlayerColor(palette: .white).uiColor
        $0.textAlignment = .center
    }

    private let nameLabel = UILabel().configure {
        $0.text = ABLoopConstants.Strings.loopNameLabel
        $0.font = FontUtility.helveticaNeueRegular(ofSize: 14)
        $0.textColor = VideoPlayerColor(palette: .pearlWhite).uiColor
    }

    private let nameTextField = UITextField().configure {
        $0.placeholder = ABLoopConstants.Strings.loopNamePlaceholder
        $0.font = FontUtility.helveticaNeueRegular(ofSize: 16)
        $0.textColor = VideoPlayerColor(palette: .white).uiColor
        $0.backgroundColor = VideoPlayerColor(palette: .black).uiColor.withAlphaComponent(0.3)
        $0.layer.cornerRadius = ABLoopConstants.UI.cornerRadius
        $0.leftView = UIView(frame: CGRect(x: 0, y: 0, width: CGFloat.space12, height: 0))
        $0.leftViewMode = .always
    }

    private let pointALabel = UILabel().configure {
        $0.text = ABLoopConstants.Strings.pointALabel
        $0.font = FontUtility.helveticaNeueBold(ofSize: 16)
        $0.textColor = VideoPlayerColor(palette: .white).uiColor
    }

    private lazy var pointATimecodeInput = TimecodeInputView(frameRate: frameRate)

    private let setPointAButton = UIButton().configure {
        $0.setTitle(ABLoopConstants.Strings.setToCurrentTime, for: .normal)
        $0.titleLabel?.font = FontUtility.helveticaNeueRegular(ofSize: 14)
        $0.setTitleColor(VideoPlayerColor(palette: .white).uiColor, for: .normal)
        $0.backgroundColor = VideoPlayerColor(palette: .red).uiColor.withAlphaComponent(0.7)
        $0.layer.cornerRadius = ABLoopConstants.UI.smallCornerRadius
    }

    private let pointBLabel = UILabel().configure {
        $0.text = ABLoopConstants.Strings.pointBLabel
        $0.font = FontUtility.helveticaNeueBold(ofSize: 16)
        $0.textColor = VideoPlayerColor(palette: .white).uiColor
    }

    private lazy var pointBTimecodeInput = TimecodeInputView(frameRate: frameRate)

    private let setPointBButton = UIButton().configure {
        $0.setTitle(ABLoopConstants.Strings.setToCurrentTime, for: .normal)
        $0.titleLabel?.font = FontUtility.helveticaNeueRegular(ofSize: 14)
        $0.setTitleColor(VideoPlayerColor(palette: .white).uiColor, for: .normal)
        $0.backgroundColor = VideoPlayerColor(palette: .red).uiColor.withAlphaComponent(0.7)
        $0.layer.cornerRadius = ABLoopConstants.UI.smallCornerRadius
    }

    private let cancelButton = UIButton().configure {
        $0.setTitle(ABLoopConstants.Strings.cancel, for: .normal)
        $0.titleLabel?.font = FontUtility.helveticaNeueRegular(ofSize: 16)
        $0.setTitleColor(VideoPlayerColor(palette: .white).uiColor, for: .normal)
        $0.backgroundColor = VideoPlayerColor(palette: .black).uiColor.withAlphaComponent(0.5)
        $0.layer.cornerRadius = ABLoopConstants.UI.cornerRadius
    }

    private let createButton = UIButton().configure {
        $0.setTitle(ABLoopConstants.Strings.createLoop, for: .normal)
        $0.titleLabel?.font = FontUtility.helveticaNeueBold(ofSize: 16)
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
        dismiss(animated: true)
    }

    @objc private func createButtonTapped() {
        view.endEditing(true)

        guard let pointA = pointATimecodeInput.getTimecode(),
              let pointB = pointBTimecodeInput.getTimecode() else {
            showAlert(
                title: ABLoopConstants.Strings.invalidInputTitle,
                message: ABLoopConstants.Strings.invalidInputMessage
            )
            return
        }

        if let message = ABLoopValidation.validateLoopRange(pointA: pointA, pointB: pointB).errorMessage {
            showAlert(title: ABLoopConstants.Strings.invalidRangeTitle, message: message)
            return
        }

        if let message = durationErrorMessage(for: pointA) ?? durationErrorMessage(for: pointB) {
            showAlert(title: ABLoopConstants.Strings.durationExceededTitle, message: message)
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

        dismiss(animated: true)
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    @objc private func keyboardWillShow(notification: NSNotification) {
        if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue {
            let keyboardHeight = keyboardFrame.cgRectValue.height
            UIView.animate(withDuration: ABLoopConstants.Animation.duration) {
                self.containerView.transform = CGAffineTransform(
                    translationX: 0,
                    y: -keyboardHeight / ABLoopConstants.Animation.keyboardOffsetDivisor
                )
            }
        }
    }

    @objc private func keyboardWillHide(notification: NSNotification) {
        UIView.animate(withDuration: ABLoopConstants.Animation.duration) {
            self.containerView.transform = .identity
        }
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
        alert.addAction(UIAlertAction(title: ABLoopConstants.Strings.okAction, style: .default))
        present(alert, animated: true)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
