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

    private let hoursTextField = TimecodeInputView.makeTimeTextField()

    private let minutesTextField = TimecodeInputView.makeTimeTextField()

    private let secondsTextField = TimecodeInputView.makeTimeTextField()

    private let framesTextField = TimecodeInputView.makeTimeTextField()

    private let separator1 = TimecodeInputView.makeSeparatorLabel()

    private let separator2 = TimecodeInputView.makeSeparatorLabel()

    private let separator3 = TimecodeInputView.makeSeparatorLabel()

    /// The row of fields and separators.
    ///
    /// Held as a property rather than built locally so its layout direction can be pinned: a
    /// timecode reads hours-first left-to-right in every locale, the same way a clock face does.
    private let fieldsStackView = UIStackView().configure {
        $0.axis = .horizontal
        $0.spacing = CGFloat.space8
        $0.alignment = .center
        $0.distribution = .fillEqually
        $0.semanticContentAttribute = .forceLeftToRight
    }

    /// The smallest hit area the HIG allows for a control, in points.
    private static let minimumTouchTarget: CGFloat = 44

    /// Creates a numeric text field styled for a timecode component.
    private static func makeTimeTextField() -> UITextField {
        UITextField().configure {
            $0.keyboardType = .numberPad
            $0.textAlignment = .center
            $0.font = UIFontMetrics(forTextStyle: .body)
                .scaledFont(for: FontUtility.helveticaNeueRegular(ofSize: 16))
            $0.adjustsFontForContentSizeCategory = true
            $0.textColor = VideoPlayerColor(palette: .white).uiColor
            $0.backgroundColor = VideoPlayerColor(palette: .black).uiColor.withAlphaComponent(0.3)
            $0.layer.cornerRadius = 4
            $0.placeholder = "00"
        }
    }

    /// Creates a ":" separator label used between timecode components.
    ///
    /// Hidden from assistive technology: read out one at a time the colons are noise, and each
    /// field names the unit it holds.
    private static func makeSeparatorLabel() -> UILabel {
        UILabel().configure {
            $0.text = ":"
            $0.font = UIFontMetrics(forTextStyle: .body)
                .scaledFont(for: FontUtility.helveticaNeueBold(ofSize: 16))
            $0.adjustsFontForContentSizeCategory = true
            $0.textColor = VideoPlayerColor(palette: .white).uiColor
            $0.textAlignment = .center
            $0.isAccessibilityElement = false
        }
    }

    /// The "HH:MM:SS:FF" hint under the fields. Purely visual — see `makeSeparatorLabel()`.
    private let formatLabel = UILabel().configure {
        $0.text = CVPLocalized(
            "abloop.timecodeFormat",
            value: "HH:MM:SS:FF",
            comment: "Placeholder showing the order of the timecode fields: hours, minutes, seconds, frames."
        )
        $0.font = UIFontMetrics(forTextStyle: .caption1)
            .scaledFont(for: FontUtility.helveticaNeueLight(ofSize: 12))
        $0.adjustsFontForContentSizeCategory = true
        $0.textColor = VideoPlayerColor(palette: .pearlWhite).uiColor
        $0.textAlignment = .center
        $0.isAccessibilityElement = false
    }

    // MARK: - Initialization

    init(frameRate: Double = 30.0) {
        self.frameRate = frameRate
        super.init(frame: .zero)
        setupViews()
        setupDelegates()
        setUpAccessibility()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
        setupDelegates()
        setUpAccessibility()
    }

    // MARK: - Setup

    private func setupViews() {
        addSubview(fieldsStackView)
        addSubview(formatLabel)

        fieldsStackView.addArrangedSubview(hoursTextField)
        fieldsStackView.addArrangedSubview(separator1)
        fieldsStackView.addArrangedSubview(minutesTextField)
        fieldsStackView.addArrangedSubview(separator2)
        fieldsStackView.addArrangedSubview(secondsTextField)
        fieldsStackView.addArrangedSubview(separator3)
        fieldsStackView.addArrangedSubview(framesTextField)

        fieldsStackView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            // A minimum rather than a fixed height: the fields are the row's touch targets, and
            // text scaled up for Dynamic Type has to be able to grow the row instead of clipping.
            make.height.greaterThanOrEqualTo(TimecodeInputView.minimumTouchTarget)
        }

        formatLabel.snp.makeConstraints { make in
            make.top.equalTo(fieldsStackView.snp.bottom).offset(CGFloat.space4)
            make.centerX.equalToSuperview()
            make.bottom.equalToSuperview()
        }

        [hoursTextField, minutesTextField, secondsTextField, framesTextField].forEach { textField in
            textField.snp.makeConstraints { make in
                make.width.greaterThanOrEqualTo(50)
            }
        }
    }

    // MARK: - Accessibility

    /// Names each timecode field for VoiceOver.
    ///
    /// Four adjacent, identically styled "00" fields are indistinguishable to a VoiceOver user:
    /// the ":" separators and the "HH:MM:SS:FF" hint that tell a sighted user which is which are
    /// purely visual, so each field has to name its own unit. The row is marked as a semantic
    /// group so entering it announces what the fields together represent.
    private func setUpAccessibility() {
        fieldsStackView.accessibilityContainerType = .semanticGroup
        fieldsStackView.accessibilityLabel = CVPLocalized(
            "abloop.timecodeField.accessibility",
            value: "Timecode, hours minutes seconds frames",
            comment: "VoiceOver label for the timecode entry row as a whole."
        )

        hoursTextField.accessibilityLabel = CVPLocalized(
            "abloop.hours.accessibility", value: "Hours", comment: "VoiceOver label for the hours field of a timecode."
        )
        minutesTextField.accessibilityLabel = CVPLocalized(
            "abloop.minutes.accessibility", value: "Minutes", comment: "VoiceOver label for the minutes field of a timecode."
        )
        secondsTextField.accessibilityLabel = CVPLocalized(
            "abloop.seconds.accessibility", value: "Seconds", comment: "VoiceOver label for the seconds field of a timecode."
        )
        framesTextField.accessibilityLabel = CVPLocalized(
            "abloop.frames.accessibility", value: "Frames", comment: "VoiceOver label for the frames field of a timecode."
        )
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
