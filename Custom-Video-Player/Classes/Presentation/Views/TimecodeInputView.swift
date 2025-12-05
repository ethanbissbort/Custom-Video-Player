import UIKit
import SnapKit

/// Protocol for timecode input events
protocol TimecodeInputViewDelegate: AnyObject {
    func timecodeDidChange(_ timecode: TimePoint?)
}

/// Custom view for inputting precise timecodes with frame-level accuracy
class TimecodeInputView: UIView {
    weak var delegate: TimecodeInputViewDelegate?

    private var frameRate: Double = ABLoopConstants.defaultFrameRate

    // MARK: - UI Components

    private let hoursTextField = UITextField().configure {
        $0.keyboardType = .numberPad
        $0.textAlignment = .center
        $0.font = FontUtility.helveticaNeueRegular(ofSize: 16)
        $0.textColor = VideoPlayerColor(palette: .white).uiColor
        $0.backgroundColor = VideoPlayerColor(palette: .black).uiColor.withAlphaComponent(0.3)
        $0.layer.cornerRadius = 4
        $0.placeholder = "00"
    }

    private let minutesTextField = UITextField().configure {
        $0.keyboardType = .numberPad
        $0.textAlignment = .center
        $0.font = FontUtility.helveticaNeueRegular(ofSize: 16)
        $0.textColor = VideoPlayerColor(palette: .white).uiColor
        $0.backgroundColor = VideoPlayerColor(palette: .black).uiColor.withAlphaComponent(0.3)
        $0.layer.cornerRadius = 4
        $0.placeholder = "00"
    }

    private let secondsTextField = UITextField().configure {
        $0.keyboardType = .numberPad
        $0.textAlignment = .center
        $0.font = FontUtility.helveticaNeueRegular(ofSize: 16)
        $0.textColor = VideoPlayerColor(palette: .white).uiColor
        $0.backgroundColor = VideoPlayerColor(palette: .black).uiColor.withAlphaComponent(0.3)
        $0.layer.cornerRadius = 4
        $0.placeholder = "00"
    }

    private let framesTextField = UITextField().configure {
        $0.keyboardType = .numberPad
        $0.textAlignment = .center
        $0.font = FontUtility.helveticaNeueRegular(ofSize: 16)
        $0.textColor = VideoPlayerColor(palette: .white).uiColor
        $0.backgroundColor = VideoPlayerColor(palette: .black).uiColor.withAlphaComponent(0.3)
        $0.layer.cornerRadius = 4
        $0.placeholder = "00"
    }

    private let separator1 = UILabel().configure {
        $0.text = ":"
        $0.font = FontUtility.helveticaNeueBold(ofSize: 16)
        $0.textColor = VideoPlayerColor(palette: .white).uiColor
        $0.textAlignment = .center
    }

    private let separator2 = UILabel().configure {
        $0.text = ":"
        $0.font = FontUtility.helveticaNeueBold(ofSize: 16)
        $0.textColor = VideoPlayerColor(palette: .white).uiColor
        $0.textAlignment = .center
    }

    private let separator3 = UILabel().configure {
        $0.text = ":"
        $0.font = FontUtility.helveticaNeueBold(ofSize: 16)
        $0.textColor = VideoPlayerColor(palette: .white).uiColor
        $0.textAlignment = .center
    }

    private let formatLabel = UILabel().configure {
        $0.text = "HH:MM:SS:FF"
        $0.font = FontUtility.helveticaNeueLight(ofSize: 12)
        $0.textColor = VideoPlayerColor(palette: .pearlWhite).uiColor
        $0.textAlignment = .center
    }

    // MARK: - Initialization

    init(frameRate: Double = 30.0) {
        self.frameRate = frameRate
        super.init(frame: .zero)
        setupViews()
        setupDelegates()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
        setupDelegates()
    }

    // MARK: - Setup

    private func setupViews() {
        let stackView = UIStackView().configure {
            $0.axis = .horizontal
            $0.spacing = 8
            $0.alignment = .center
            $0.distribution = .fillEqually
        }

        addSubview(stackView)
        addSubview(formatLabel)

        stackView.addArrangedSubview(hoursTextField)
        stackView.addArrangedSubview(separator1)
        stackView.addArrangedSubview(minutesTextField)
        stackView.addArrangedSubview(separator2)
        stackView.addArrangedSubview(secondsTextField)
        stackView.addArrangedSubview(separator3)
        stackView.addArrangedSubview(framesTextField)

        stackView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.height.equalTo(40)
        }

        formatLabel.snp.makeConstraints { make in
            make.top.equalTo(stackView.snp.bottom).offset(4)
            make.centerX.equalToSuperview()
            make.bottom.equalToSuperview()
        }

        [hoursTextField, minutesTextField, secondsTextField, framesTextField].forEach { textField in
            textField.snp.makeConstraints { make in
                make.width.equalTo(50)
            }
        }
    }

    private func setupDelegates() {
        hoursTextField.delegate = self
        minutesTextField.delegate = self
        secondsTextField.delegate = self
        framesTextField.delegate = self

        hoursTextField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
        minutesTextField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
        secondsTextField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
        framesTextField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
    }

    // MARK: - Public Methods

    /// Sets the timecode value
    ///
    /// - Parameter timePoint: The TimePoint to display
    func setTimecode(_ timePoint: TimePoint) {
        frameRate = timePoint.frameRate
        hoursTextField.text = String(format: "%02d", timePoint.hours)
        minutesTextField.text = String(format: "%02d", timePoint.minutes)
        secondsTextField.text = String(format: "%02d", timePoint.seconds)
        framesTextField.text = String(format: "%02d", timePoint.frames)
    }

    /// Gets the current timecode value
    ///
    /// - Returns: TimePoint if valid, nil otherwise
    func getTimecode() -> TimePoint? {
        guard let hoursText = hoursTextField.text, !hoursText.isEmpty,
              let minutesText = minutesTextField.text, !minutesText.isEmpty,
              let secondsText = secondsTextField.text, !secondsText.isEmpty,
              let framesText = framesTextField.text, !framesText.isEmpty,
              let hours = Int(hoursText),
              let minutes = Int(minutesText),
              let seconds = Int(secondsText),
              let frames = Int(framesText),
              minutes < 60, seconds < 60, frames < Int(frameRate) else {
            return nil
        }

        return TimePoint(hours: hours, minutes: minutes, seconds: seconds, frames: frames, frameRate: frameRate)
    }

    /// Clears all input fields
    func clear() {
        hoursTextField.text = ""
        minutesTextField.text = ""
        secondsTextField.text = ""
        framesTextField.text = ""
    }

    /// Sets the frame rate
    ///
    /// - Parameter frameRate: The new frame rate
    func setFrameRate(_ frameRate: Double) {
        self.frameRate = frameRate
    }

    // MARK: - Actions

    @objc private func textFieldDidChange() {
        delegate?.timecodeDidChange(getTimecode())
    }
}

// MARK: - UITextFieldDelegate

extension TimecodeInputView: UITextFieldDelegate {
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        // Only allow numbers
        let allowedCharacters = CharacterSet.decimalDigits
        let characterSet = CharacterSet(charactersIn: string)
        guard allowedCharacters.isSuperset(of: characterSet) || string.isEmpty else {
            return false
        }

        // Calculate the new text
        let currentText = textField.text ?? ""
        guard let stringRange = Range(range, in: currentText) else { return false }
        let updatedText = currentText.replacingCharacters(in: stringRange, with: string)

        // Limit to 2 digits for all fields
        if updatedText.count > 2 {
            return false
        }

        // Validate ranges
        if let value = Int(updatedText), !updatedText.isEmpty {
            if textField == minutesTextField || textField == secondsTextField {
                return value < 60
            } else if textField == framesTextField {
                return value < Int(frameRate)
            }
        }

        return true
    }

    func textFieldDidBeginEditing(_ textField: UITextField) {
        textField.layer.borderWidth = 1
        textField.layer.borderColor = VideoPlayerColor(palette: .red).uiColor.cgColor
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        textField.layer.borderWidth = 0

        // Auto-pad with zero if single digit
        if let text = textField.text, text.count == 1 {
            textField.text = "0" + text
        }
    }
}
