import SnapKit
import UIKit

class VideoPlayerErrorView: UIView {
    // MARK: - View Components

    private let errorTitle = UILabel().configure {
        $0.numberOfLines = 0
        $0.font = UIFontMetrics(forTextStyle: .title3)
            .scaledFont(for: FontUtility.helveticaNeueMedium(ofSize: 20))
        $0.adjustsFontForContentSizeCategory = true
        $0.textColor = VideoPlayerColor(palette: .white).uiColor
        $0.lineBreakMode = .byWordWrapping
        $0.textAlignment = .center
    }

    private let backButton = UIButton().configure {
        $0.setImage(VideoPlayerImage.backButton.uiImage, for: .normal)
    }

    /// Dynamic spacing based on screen height.
    private let dynamicSpacing: CGFloat = UIScreen.main.bounds.height * 0.055

    /// The smallest hit area the HIG allows for a control, in points.
    private static let minimumTouchTarget: CGFloat = 44

    // MARK: - Callback
    private let onBackButtonClicked: () -> Void

    // MARK: - Initialization
    
    /// Initializes the error view with a title and callback for the back button.
    ///
    /// - Parameters:
    ///   - title: The title to be displayed as the error message.
    ///   - onBackButtonClicked: A closure to be executed when the back button is tapped.
    init(title: String, onBackButtonClicked: @escaping () -> Void) {
        errorTitle.text = title
        self.onBackButtonClicked = onBackButtonClicked
        super.init(frame: .zero)
        setupView()
    }

    /// Unsupported initializer from Interface Builder.
    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - View Setup
    
    /// Sets up the appearance and layout of the error view's subviews.
    private func setupView() {
        addSubview(backButton)
        addSubview(errorTitle)

        backButton.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(CGFloat.space24)
            make.leading.equalToSuperview().offset(dynamicSpacing)
            // The artwork is smaller than the minimum hit area, so the button is grown around it.
            make.width.greaterThanOrEqualTo(VideoPlayerErrorView.minimumTouchTarget)
            make.height.greaterThanOrEqualTo(VideoPlayerErrorView.minimumTouchTarget)
        }

        errorTitle.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.centerY.equalToSuperview()
            // Message text scaled up for Dynamic Type wraps inside the view rather than running
            // off both edges of the screen.
            make.leading.greaterThanOrEqualToSuperview().offset(CGFloat.space24)
            make.trailing.lessThanOrEqualToSuperview().offset(-CGFloat.space24)
        }

        backButton.addTarget(self, action: #selector(onBackButtonTap), for: .touchUpInside)

        setUpAccessibility()
    }

    // MARK: - Accessibility

    /// Names the back button and makes the message itself readable by VoiceOver.
    ///
    /// The button is drawn from a PDF asset, so without a label VoiceOver announces the asset file
    /// name ("back_button"). The message is static text that carries the whole point of the
    /// screen, so it is also what focus moves to when the view appears.
    private func setUpAccessibility() {
        backButton.accessibilityLabel = CVPLocalized(
            "player.back.accessibility",
            value: "Back",
            comment: "VoiceOver label for the button that leaves the player."
        )

        errorTitle.isAccessibilityElement = true
        errorTitle.accessibilityTraits.insert(.staticText)
    }

    /// Moves VoiceOver focus to the error message once the view is on screen.
    ///
    /// Playback failures replace the whole player, and without this announcement focus stays on
    /// whatever the user was last touching — a control that no longer exists.
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        UIAccessibility.post(notification: .screenChanged, argument: errorTitle)
    }

    // MARK: - Action Handling
    
    /// Handles the action when the back button is tapped.
    @objc private func onBackButtonTap() {
        onBackButtonClicked()
    }
}
