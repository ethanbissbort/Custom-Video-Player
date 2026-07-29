import AVFoundation
import SnapKit
import UIKit

/// A protocol for handling quality selection events.
protocol QualitySelectionDelegate: AnyObject {
    /// Notifies the delegate when a quality setting is selected.
    ///
    /// - Parameter index: The index of the selected quality setting.
    func onQualitySettingSelected(didSelectRowAt index: Int)
    
    /// Notifies the delegate when the selection view is dismissed.
    func onDismissed()
}

/// A view controller for selecting video quality settings.
class QualitySelectionViewController: UIViewController {
    private static let cellIdentifier = "QualityCell"
    
    private let popOverView = UIView().configure {
        $0.backgroundColor = VideoPlayerColor(palette: .black).uiColor
        $0.roundCorners(cornerRadius: CGFloat.space40 / 2)
    }
    
    private let tableView = UITableView().configure { tableView in
        tableView.register(SelectionCellView.self, forCellReuseIdentifier: cellIdentifier)
        tableView.backgroundColor = .clear
        tableView.showsVerticalScrollIndicator = false
    }
    
    private let grabberView = UIView().configure {
        $0.backgroundColor = VideoPlayerColor(palette: .white).uiColor.withAlphaComponent(0.5)
        $0.layer.cornerRadius = CGFloat.space6 / 2
    }
    
    /// Scaled with `UIFontMetrics` and capped: the sheet's height is fixed, so the title has to
    /// follow the user's Dynamic Type setting without pushing the table off the card.
    private let header = UILabel().configure {
        $0.textColor = VideoPlayerColor(palette: .pearlWhite).uiColor
        $0.text = CVPLocalized(
            "quality.title",
            value: "Qualities",
            comment: "Title of the video quality selection sheet"
        )
        $0.font = UIFontMetrics(forTextStyle: .headline).scaledFont(
            for: FontUtility.helveticaNeueMedium(ofSize: 16),
            maximumPointSize: 24
        )
        $0.adjustsFontForContentSizeCategory = true
        $0.accessibilityTraits = .header
    }
    
    weak var delegate: QualitySelectionDelegate?
    private let viewModel: QualitySelectionViewModel
    
    init(viewModel: QualitySelectionViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        setupAccessibility()
        modalPresentationStyle = .popover
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // The sheet covers the player, so VoiceOver has to be moved into it explicitly; without
        // this, focus stays on the (now obscured) settings button.
        UIAccessibility.post(notification: .screenChanged, argument: header)
    }

    /// Intentionally empty. The host app detects landscape-capable controllers via
    /// `responds(to: Selector("shouldForceLandscape"))` (see the Example AppDelegate), so this
    /// method's mere presence is what matters — do not remove it.
    @objc func shouldForceLandscape() {}
    
    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        view.addSubview(popOverView)
        popOverView.snp.makeConstraints { make in
            make.width.equalTo(375)
            make.centerX.equalToSuperview()
            make.bottom.equalToSuperview().offset(-CGFloat.space40)
            make.top.greaterThanOrEqualToSuperview().offset(CGFloat.space40)
        }
        
        setupPopOverView()
        setupGestureRecognizers()
    }
    
    private func setupGestureRecognizers() {
        let overlayTapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissView))
        overlayTapGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(overlayTapGesture)
        
        let swipeDown = UISwipeGestureRecognizer(target: self, action: #selector(dismissView))
        swipeDown.direction = UISwipeGestureRecognizer.Direction.down
        popOverView.addGestureRecognizer(swipeDown)
    }
    
    private func setupPopOverView() {
        popOverView.addSubview(grabberView)
        popOverView.addSubview(header)
        popOverView.addSubview(tableView)
        
        grabberView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalToSuperview().offset(CGFloat.space8)
            make.width.equalTo(44)
            make.height.equalTo(CGFloat.space6)
        }
        
        header.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(grabberView.snp.bottom).offset(CGFloat.space40 / 2)
        }
        setupTableView()
    }
    
    private func setupTableView() {
        tableView.dataSource = self
        tableView.separatorStyle = .none
        tableView.backgroundColor = .clear
        tableView.showsVerticalScrollIndicator = false
        tableView.delegate = self
        
        tableView.snp.makeConstraints { make in
            make.top.equalTo(header.snp.bottom).offset(CGFloat.space16)
            make.leading.equalToSuperview().offset(CGFloat.space24)
            make.trailing.equalToSuperview().offset(-CGFloat.space24)
            make.bottom.equalToSuperview().offset(-CGFloat.space8)
            make.height.equalTo(240)
        }
    }
    
    /// Wires up the accessibility affordances the sheet's visual design implies but does not
    /// expose: the card is modal, the grabber is decorative, and the only way out is a tap on the
    /// dimmed area or a swipe down — neither of which a VoiceOver user can perform.
    private func setupAccessibility() {
        popOverView.accessibilityViewIsModal = true
        grabberView.isAccessibilityElement = false
        grabberView.accessibilityElementsHidden = true
        tableView.accessibilityLabel = CVPLocalized(
            "quality.list.accessibility",
            value: "Video qualities",
            comment: "VoiceOver label for the list of video qualities"
        )
    }

    @objc private func dismissView() {
        // Reduce Motion asks for the transition itself to go away, not merely to be shortened.
        dismiss(animated: !UIAccessibility.isReduceMotionEnabled)
        delegate?.onDismissed()
    }

    /// Makes the VoiceOver escape gesture (a two-finger Z) close the sheet.
    ///
    /// The tap-to-dismiss overlay and the swipe-down gesture are both unreachable with VoiceOver
    /// on, so without this the sheet can only be left by picking a quality.
    override func accessibilityPerformEscape() -> Bool {
        dismissView()
        return true
    }
}

// MARK: - UITableViewDataSource, UITableViewDelegate

extension QualitySelectionViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        return viewModel.supportedResolutions.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: QualitySelectionViewController.cellIdentifier, for: indexPath) as! SelectionCellView
        let qualitySetting = viewModel.supportedResolutions[indexPath.row]
        let isSelected = indexPath.row == viewModel.selectedItemIndex
        cell.configureCell(title: qualitySetting, isSelected: isSelected)
        cell.selectionStyle = .none
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        viewModel.selectedItemIndex = indexPath.row
        tableView.reloadData()
        delegate?.onQualitySettingSelected(didSelectRowAt: indexPath.row)
        dismissView()
    }

    func tableView(_: UITableView, heightForRowAt _:IndexPath) -> CGFloat {
        return CGFloat.space38
    }
}
