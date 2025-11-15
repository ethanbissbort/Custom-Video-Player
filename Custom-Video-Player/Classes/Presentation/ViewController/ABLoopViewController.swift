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

    // MARK: - UI Components

    private let containerView = UIView().configure {
        $0.backgroundColor = VideoPlayerColor(palette: .black).uiColor.withAlphaComponent(0.95)
        $0.layer.cornerRadius = ABLoopConstants.UI.cornerRadius
    }

    private let titleLabel = UILabel().configure {
        $0.text = ABLoopConstants.Strings.abLoopTitle
        $0.font = FontUtility.helveticaNeueBold(ofSize: 20)
        $0.textColor = VideoPlayerColor(palette: .white).uiColor
        $0.textAlignment = .center
    }

    private let closeButton = UIButton().configure {
        $0.setTitle("✕", for: .normal)
        $0.titleLabel?.font = FontUtility.helveticaNeueBold(ofSize: 24)
        $0.setTitleColor(VideoPlayerColor(palette: .white).uiColor, for: .normal)
    }

    private lazy var segmentedControl: UISegmentedControl = {
        let control = UISegmentedControl(items: [
            ABLoopConstants.Strings.abLoopsSegment,
            ABLoopConstants.Strings.segmentPlaylistsSegment
        ])
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
        $0.titleLabel?.font = FontUtility.helveticaNeueRegular(ofSize: 16)
        $0.setTitleColor(VideoPlayerColor(palette: .white).uiColor, for: .normal)
        $0.backgroundColor = VideoPlayerColor(palette: .red).uiColor
        $0.layer.cornerRadius = ABLoopConstants.UI.cornerRadius
    }

    private let stopLoopButton = UIButton().configure {
        $0.setTitle(ABLoopConstants.Strings.stopLoop, for: .normal)
        $0.titleLabel?.font = FontUtility.helveticaNeueRegular(ofSize: 16)
        $0.setTitleColor(VideoPlayerColor(palette: .white).uiColor, for: .normal)
        $0.backgroundColor = VideoPlayerColor(palette: .black).uiColor.withAlphaComponent(0.5)
        $0.layer.cornerRadius = ABLoopConstants.UI.cornerRadius
        $0.isHidden = true
    }

    // MARK: - Initialization

    init(abLoopManager: ABLoopManager, videoIdentifier: String, frameRate: Double, currentTime: CMTime) {
        self.viewModel = ABLoopViewModel(abLoopManager: abLoopManager, videoIdentifier: videoIdentifier)
        self.frameRate = frameRate
        self.currentPlayerTime = currentTime
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
        updateUI()
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
        createButton.setTitle(viewModel.createButtonTitle, for: .normal)
        stopLoopButton.isHidden = !viewModel.hasActiveLoopOrPlaylist
        tableView.reloadData()
    }

    // MARK: - Actions

    @objc private func closeButtonTapped() {
        dismiss(animated: true)
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
            dismiss(animated: true)
        }
    }

    // MARK: - Helper Methods

    private func presentABLoopCreationDialog() {
        let alert = ABLoopCreationViewController(
            frameRate: frameRate,
            currentTime: currentPlayerTime,
            videoIdentifier: viewModel.videoIdentifier,
            abLoopManager: viewModel.abLoopManager
        )
        alert.delegate = self
        alert.modalPresentationStyle = .overFullScreen
        alert.modalTransitionStyle = .crossDissolve
        present(alert, animated: true)
    }

    private func presentSegmentPlaylistCreationDialog() {
        let alert = UIAlertController(
            title: "Create Segment Playlist",
            message: "This feature allows you to create a playlist of video segments. Add multiple A-B points to create a custom viewing sequence.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    /// Updates the current player time (called from parent when time changes)
    func updateCurrentTime(_ time: CMTime) {
        currentPlayerTime = time
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

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        switch viewModel.currentMode {
        case .abLoop:
            if let loop = viewModel.getABLoop(at: indexPath.row) {
                delegate?.didSelectABLoop(loop)
                delegate?.didRequestSeek(to: loop.pointA.toCMTime())
            }
        case .segmentPlaylist:
            if let playlist = viewModel.getSegmentPlaylist(at: indexPath.row) {
                delegate?.didSelectSegmentPlaylist(playlist)
                if let firstSegment = playlist.segments.first {
                    delegate?.didRequestSeek(to: firstSegment.startPoint.toCMTime())
                }
            }
        }

        updateUI()
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

// MARK: - ABLoopTableViewCell

class ABLoopTableViewCell: UITableViewCell {
    private let titleLabel = UILabel().configure {
        $0.font = FontUtility.helveticaNeueBold(ofSize: 16)
        $0.textColor = VideoPlayerColor(palette: .white).uiColor
    }

    private let detailLabel = UILabel().configure {
        $0.font = FontUtility.helveticaNeueLight(ofSize: 14)
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
    }
}
