import AVFoundation
import SnapKit
import UIKit

/// Protocol for handling subtitle selection events.
protocol SubtitleSelectionDelegate: AnyObject {
    /// Called when a subtitle track is selected.
    func onSubtitleTrackSelected(subtitleTrack: AVMediaSelectionOption?)
    /// Called when the subtitle selection view is dismissed.
    func onDismissed()
}

/// View controller for selecting subtitles.
class SubtitleSelectionViewController: UIViewController {
    private static let cellIdentifier = "SubtitleCell"
    
    // MARK: - UI Components
    
    /// The main container view for the subtitle selection.
    private let popOverView = UIView().configure {
        $0.backgroundColor = VideoPlayerColor(palette: .black).uiColor
        $0.roundCorners(cornerRadius: CGFloat.space40 / 2)
    }
    
    /// Table view for displaying available subtitle options.
    private let tableView = UITableView().configure { tableView in
        tableView.register(SelectionCellView.self, forCellReuseIdentifier: cellIdentifier)
        tableView.backgroundColor = .clear
        tableView.showsVerticalScrollIndicator = false
    }
    
    /// The grabber view for indicating draggable area.
    private let grabberView = UIView().configure {
        $0.backgroundColor = VideoPlayerColor(palette: .white).uiColor.withAlphaComponent(0.5)
        $0.layer.cornerRadius = CGFloat.space6 / 2
    }
    
    /// Header label for the subtitle selection view.
    ///
    /// Scaled with `UIFontMetrics` and capped, because the sheet's height is fixed: the title has
    /// to grow with the user's Dynamic Type setting without pushing the table off the card.
    private let header = UILabel().configure {
        $0.textColor = VideoPlayerColor(palette: .pearlWhite).uiColor
        $0.text = CVPLocalized(
            "subtitles.title",
            value: "Subtitle",
            comment: "Title of the subtitle selection sheet"
        )
        $0.font = UIFontMetrics(forTextStyle: .headline).scaledFont(
            for: FontUtility.helveticaNeueMedium(ofSize: 16),
            maximumPointSize: 24
        )
        $0.adjustsFontForContentSizeCategory = true
        $0.accessibilityTraits = .header
    }
    
    // MARK: - Properties
    
    /// Delegate for handling subtitle selection events.
    weak var delegate: SubtitleSelectionDelegate?
    /// View model for managing subtitle selection logic.
    private let viewModel: SubtitleSelectionViewModel
    
    // MARK: - Initialization
    
    /// Initializes the subtitle selection view controller with a view model.
    init(viewModel: SubtitleSelectionViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }
    
    /// Required initializer. Returns nil to force initialization with the designated initializer.
    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        setupAccessibility()
        modalPresentationStyle = .popover
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // The sheet covers the player, so VoiceOver has to be moved into it explicitly; without
        // this, focus stays on the (now obscured) subtitles button.
        UIAccessibility.post(notification: .screenChanged, argument: header)
    }

    // MARK: - View Setup

    /// Sets up the main view and its subviews.
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
    
    /// Sets up gesture recognizers for dismissing the view.
    private func setupGestureRecognizers() {
        let overlayTapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissView))
        overlayTapGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(overlayTapGesture)
        
        let swipeDown = UISwipeGestureRecognizer(target: self, action: #selector(dismissView))
        swipeDown.direction = .down
        popOverView.addGestureRecognizer(swipeDown)
    }
    
    /// Sets up the subviews within the popover view.
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
    
    /// Sets up the table view for displaying subtitle options.
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
            make.height.equalTo(CGFloat.space128)
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
            "subtitles.list.accessibility",
            value: "Subtitle tracks",
            comment: "VoiceOver label for the list of subtitle tracks"
        )
    }

    // MARK: - Actions

    /// Dismisses the subtitle selection view.
    @objc private func dismissView() {
        // Reduce Motion asks for the transition itself to go away, not merely to be shortened.
        dismiss(animated: !UIAccessibility.isReduceMotionEnabled)
        delegate?.onDismissed()
    }

    /// Makes the VoiceOver escape gesture (a two-finger Z) close the sheet.
    ///
    /// The tap-to-dismiss overlay and the swipe-down gesture are both unreachable with VoiceOver
    /// on, so without this the sheet can only be left by picking a track.
    override func accessibilityPerformEscape() -> Bool {
        dismissView()
        return true
    }

    // MARK: - External Selection

    /// Moves the sheet's selection onto a track chosen outside it.
    ///
    /// Called by the player when closed captioning is enabled system-wide and a legible track was
    /// selected automatically, so opening the sheet shows what is actually playing.
    ///
    /// - Parameter option: The selected track, or `nil` for "Off".
    func selectTrack(_ option: AVMediaSelectionOption?) {
        viewModel.selectTrack(option)
        // Safe before the view loads: the table view is a stored property, so this neither forces
        // a view hierarchy into existence nor requires a window.
        tableView.reloadData()
    }
}

// MARK: - UITableViewDataSource, UITableViewDelegate

extension SubtitleSelectionViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        return viewModel.subtitleOptionsCount
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: SubtitleSelectionViewController.cellIdentifier, for: indexPath) as! SelectionCellView
        let subtitleLanguage = viewModel.subtitleOption(indexPath.row)
        let isSelected = indexPath.row == viewModel.selectedItemIndex
        cell.configureCell(title: subtitleLanguage, isSelected: isSelected)
        cell.selectionStyle = .none
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        viewModel.selectedItemIndex = indexPath.row
        tableView.reloadData()
        delegate?.onSubtitleTrackSelected(subtitleTrack: viewModel.subtitleTrack)
        dismissView()
    }
    
    func tableView(_: UITableView, heightForRowAt _: IndexPath) -> CGFloat {
        return CGFloat.space38
    }
}