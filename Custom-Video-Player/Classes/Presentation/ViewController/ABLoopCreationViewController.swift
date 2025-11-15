import UIKit
import AVFoundation
import SnapKit

/// Protocol for A-B loop creation delegate
protocol ABLoopCreationViewControllerDelegate: AnyObject {
    func didCreateABLoop(_ loop: ABLoop)
}

/// View controller for creating a new A-B loop
class ABLoopCreationViewController: UIViewController {
    // MARK: - Properties

    weak var delegate: ABLoopCreationViewControllerDelegate?
    private let frameRate: Double
    private let currentTime: CMTime
    private let videoIdentifier: String
    private let abLoopManager: ABLoopManager

    // MARK: - UI Components

    private let containerView = UIView().configure {
        $0.backgroundColor = VideoPlayerColor(palette: .black).uiColor.withAlphaComponent(0.95)
        $0.layer.cornerRadius = 12
    }

    private let titleLabel = UILabel().configure {
        $0.text = "Create A-B Loop"
        $0.font = FontUtility.helveticaNeueBold(ofSize: 20)
        $0.textColor = VideoPlayerColor(palette: .white).uiColor
        $0.textAlignment = .center
    }

    private let nameLabel = UILabel().configure {
        $0.text = "Loop Name (optional)"
        $0.font = FontUtility.helveticaNeueRegular(ofSize: 14)
        $0.textColor = VideoPlayerColor(palette: .pearlWhite).uiColor
    }

    private let nameTextField = UITextField().configure {
        $0.placeholder = "Enter loop name"
        $0.font = FontUtility.helveticaNeueRegular(ofSize: 16)
        $0.textColor = VideoPlayerColor(palette: .white).uiColor
        $0.backgroundColor = VideoPlayerColor(palette: .black).uiColor.withAlphaComponent(0.3)
        $0.layer.cornerRadius = 8
        $0.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 0))
        $0.leftViewMode = .always
    }

    private let pointALabel = UILabel().configure {
        $0.text = "Point A (Start)"
        $0.font = FontUtility.helveticaNeueBold(ofSize: 16)
        $0.textColor = VideoPlayerColor(palette: .white).uiColor
    }

    private lazy var pointATimecodeInput = TimecodeInputView(frameRate: frameRate)

    private let setPointAButton = UIButton().configure {
        $0.setTitle("Set to Current Time", for: .normal)
        $0.titleLabel?.font = FontUtility.helveticaNeueRegular(ofSize: 14)
        $0.setTitleColor(VideoPlayerColor(palette: .white).uiColor, for: .normal)
        $0.backgroundColor = VideoPlayerColor(palette: .red).uiColor.withAlphaComponent(0.7)
        $0.layer.cornerRadius = 6
    }

    private let pointBLabel = UILabel().configure {
        $0.text = "Point B (End)"
        $0.font = FontUtility.helveticaNeueBold(ofSize: 16)
        $0.textColor = VideoPlayerColor(palette: .white).uiColor
    }

    private lazy var pointBTimecodeInput = TimecodeInputView(frameRate: frameRate)

    private let setPointBButton = UIButton().configure {
        $0.setTitle("Set to Current Time", for: .normal)
        $0.titleLabel?.font = FontUtility.helveticaNeueRegular(ofSize: 14)
        $0.setTitleColor(VideoPlayerColor(palette: .white).uiColor, for: .normal)
        $0.backgroundColor = VideoPlayerColor(palette: .red).uiColor.withAlphaComponent(0.7)
        $0.layer.cornerRadius = 6
    }

    private let cancelButton = UIButton().configure {
        $0.setTitle("Cancel", for: .normal)
        $0.titleLabel?.font = FontUtility.helveticaNeueRegular(ofSize: 16)
        $0.setTitleColor(VideoPlayerColor(palette: .white).uiColor, for: .normal)
        $0.backgroundColor = VideoPlayerColor(palette: .black).uiColor.withAlphaComponent(0.5)
        $0.layer.cornerRadius = 8
    }

    private let createButton = UIButton().configure {
        $0.setTitle("Create Loop", for: .normal)
        $0.titleLabel?.font = FontUtility.helveticaNeueBold(ofSize: 16)
        $0.setTitleColor(VideoPlayerColor(palette: .white).uiColor, for: .normal)
        $0.backgroundColor = VideoPlayerColor(palette: .red).uiColor
        $0.layer.cornerRadius = 8
    }

    // MARK: - Initialization

    init(frameRate: Double, currentTime: CMTime, videoIdentifier: String, abLoopManager: ABLoopManager) {
        self.frameRate = frameRate
        self.currentTime = currentTime
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
            make.width.equalTo(500)
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
            make.height.equalTo(44)
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
            make.height.equalTo(36)
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
            make.height.equalTo(36)
        }

        cancelButton.snp.makeConstraints { make in
            make.top.equalTo(setPointBButton.snp.bottom).offset(CGFloat.space24)
            make.leading.equalToSuperview().offset(CGFloat.space24)
            make.width.equalTo(120)
            make.height.equalTo(44)
            make.bottom.equalToSuperview().offset(-CGFloat.space24)
        }

        createButton.snp.makeConstraints { make in
            make.top.equalTo(cancelButton.snp.top)
            make.trailing.equalToSuperview().offset(-CGFloat.space24)
            make.leading.equalTo(cancelButton.snp.trailing).offset(CGFloat.space16)
            make.height.equalTo(44)
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
        let timePoint = TimePoint(from: currentTime, frameRate: frameRate)
        pointATimecodeInput.setTimecode(timePoint)
    }

    @objc private func setPointBToCurrentTime() {
        let timePoint = TimePoint(from: currentTime, frameRate: frameRate)
        pointBTimecodeInput.setTimecode(timePoint)
    }

    @objc private func cancelButtonTapped() {
        dismiss(animated: true)
    }

    @objc private func createButtonTapped() {
        guard let pointA = pointATimecodeInput.getTimecode(),
              let pointB = pointBTimecodeInput.getTimecode() else {
            showAlert(title: "Invalid Input", message: "Please enter valid timecodes for both Point A and Point B.")
            return
        }

        // Validate that Point B is after Point A
        let timeA = pointA.toCMTime()
        let timeB = pointB.toCMTime()

        if timeB <= timeA {
            showAlert(title: "Invalid Range", message: "Point B must be after Point A.")
            return
        }

        let name = nameTextField.text?.isEmpty == false ? nameTextField.text : nil
        let abLoop = ABLoop(pointA: pointA, pointB: pointB, name: name)

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
            UIView.animate(withDuration: 0.3) {
                self.containerView.transform = CGAffineTransform(translationX: 0, y: -keyboardHeight / 4)
            }
        }
    }

    @objc private func keyboardWillHide(notification: NSNotification) {
        UIView.animate(withDuration: 0.3) {
            self.containerView.transform = .identity
        }
    }

    // MARK: - Helper Methods

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
