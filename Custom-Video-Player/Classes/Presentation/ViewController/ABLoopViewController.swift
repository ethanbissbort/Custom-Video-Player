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
    private let abLoopManager: ABLoopManager
    private let videoIdentifier: String
    private let frameRate: Double
    private var currentPlayerTime: CMTime

    private var abLoops: [ABLoop] = []
    private var segmentPlaylists: [SegmentPlaylist] = []
    private var selectedMode: Mode = .abLoop

    private enum Mode {
        case abLoop
        case segmentPlaylist
    }

    // MARK: - UI Components

    private let containerView = UIView().configure {
        $0.backgroundColor = VideoPlayerColor(palette: .black).uiColor.withAlphaComponent(0.95)
        $0.layer.cornerRadius = 12
    }

    private let titleLabel = UILabel().configure {
        $0.text = "A-B Loop & Segments"
        $0.font = FontUtility.helveticaNeueBold(ofSize: 20)
        $0.textColor = VideoPlayerColor(palette: .white).uiColor
        $0.textAlignment = .center
    }

    private let closeButton = UIButton().configure {
        $0.setTitle("✕", for: .normal)
        $0.titleLabel?.font = FontUtility.helveticaNeueBold(ofSize: 24)
        $0.setTitleColor(VideoPlayerColor(palette: .white).uiColor, for: .normal)
    }

    private let segmentedControl = UISegmentedControl(items: ["A-B Loops", "Segment Playlists"]).configure {
        $0.selectedSegmentIndex = 0
        $0.backgroundColor = VideoPlayerColor(palette: .black).uiColor.withAlphaComponent(0.5)
        $0.selectedSegmentTintColor = VideoPlayerColor(palette: .red).uiColor
        $0.setTitleTextAttributes([.foregroundColor: VideoPlayerColor(palette: .white).uiColor], for: .normal)
        $0.setTitleTextAttributes([.foregroundColor: VideoPlayerColor(palette: .white).uiColor], for: .selected)
    }

    private let tableView = UITableView().configure {
        $0.backgroundColor = .clear
        $0.separatorStyle = .singleLine
        $0.separatorColor = VideoPlayerColor(palette: .pearlWhite).uiColor.withAlphaComponent(0.3)
    }

    private let createABLoopButton = UIButton().configure {
        $0.setTitle("+ Create New A-B Loop", for: .normal)
        $0.titleLabel?.font = FontUtility.helveticaNeueRegular(ofSize: 16)
        $0.setTitleColor(VideoPlayerColor(palette: .white).uiColor, for: .normal)
        $0.backgroundColor = VideoPlayerColor(palette: .red).uiColor
        $0.layer.cornerRadius = 8
    }

    private let stopLoopButton = UIButton().configure {
        $0.setTitle("Stop Loop", for: .normal)
        $0.titleLabel?.font = FontUtility.helveticaNeueRegular(ofSize: 16)
        $0.setTitleColor(VideoPlayerColor(palette: .white).uiColor, for: .normal)
        $0.backgroundColor = VideoPlayerColor(palette: .black).uiColor.withAlphaComponent(0.5)
        $0.layer.cornerRadius = 8
        $0.isHidden = true
    }

    // MARK: - Initialization

    init(abLoopManager: ABLoopManager, videoIdentifier: String, frameRate: Double, currentTime: CMTime) {
        self.abLoopManager = abLoopManager
        self.videoIdentifier = videoIdentifier
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
        loadData()
    }

    // MARK: - Setup

    private func setupViews() {
        view.backgroundColor = UIColor.black.withAlphaComponent(0.7)

        view.addSubview(containerView)
        containerView.addSubview(titleLabel)
        containerView.addSubview(closeButton)
        containerView.addSubview(segmentedControl)
        containerView.addSubview(tableView)
        containerView.addSubview(createABLoopButton)
        containerView.addSubview(stopLoopButton)

        containerView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.equalTo(600)
            make.height.equalTo(500)
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
            make.bottom.equalTo(createABLoopButton.snp.top).offset(-CGFloat.space16)
        }

        stopLoopButton.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(CGFloat.space16)
            make.bottom.equalToSuperview().offset(-CGFloat.space16)
            make.height.equalTo(44)
            make.width.equalTo(120)
        }

        createABLoopButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-CGFloat.space16)
            make.bottom.equalToSuperview().offset(-CGFloat.space16)
            make.height.equalTo(44)
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
        createABLoopButton.addTarget(self, action: #selector(createButtonTapped), for: .touchUpInside)
        stopLoopButton.addTarget(self, action: #selector(stopLoopButtonTapped), for: .touchUpInside)
        segmentedControl.addTarget(self, action: #selector(segmentedControlChanged), for: .valueChanged)

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped))
        tapGesture.delegate = self
        view.addGestureRecognizer(tapGesture)
    }

    private func loadData() {
        abLoops = abLoopManager.getABLoops(for: videoIdentifier)
        segmentPlaylists = abLoopManager.getSegmentPlaylists(for: videoIdentifier)
        tableView.reloadData()
        updateStopButtonVisibility()
    }

    private func updateStopButtonVisibility() {
        let hasActiveLoop = abLoopManager.getActiveLoop() != nil
        let hasActivePlaylist = abLoopManager.getActiveSegmentPlaylist() != nil
        stopLoopButton.isHidden = !hasActiveLoop && !hasActivePlaylist
    }

    // MARK: - Actions

    @objc private func closeButtonTapped() {
        dismiss(animated: true)
    }

    @objc private func createButtonTapped() {
        if selectedMode == .abLoop {
            showCreateABLoopDialog()
        } else {
            showCreateSegmentPlaylistDialog()
        }
    }

    @objc private func stopLoopButtonTapped() {
        delegate?.didSelectABLoop(nil)
        delegate?.didSelectSegmentPlaylist(nil)
        updateStopButtonVisibility()
    }

    @objc private func segmentedControlChanged() {
        selectedMode = segmentedControl.selectedSegmentIndex == 0 ? .abLoop : .segmentPlaylist
        tableView.reloadData()
        createABLoopButton.setTitle(
            selectedMode == .abLoop ? "+ Create New A-B Loop" : "+ Create Segment Playlist",
            for: .normal
        )
    }

    @objc private func backgroundTapped(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: view)
        if !containerView.frame.contains(location) {
            dismiss(animated: true)
        }
    }

    // MARK: - Helper Methods

    private func showCreateABLoopDialog() {
        let alert = ABLoopCreationViewController(
            frameRate: frameRate,
            currentTime: currentPlayerTime,
            videoIdentifier: videoIdentifier,
            abLoopManager: abLoopManager
        )
        alert.delegate = self
        alert.modalPresentationStyle = .overFullScreen
        alert.modalTransitionStyle = .crossDissolve
        present(alert, animated: true)
    }

    private func showCreateSegmentPlaylistDialog() {
        // This would open a more complex UI for creating segment playlists
        // For now, we'll show a simple alert
        let alert = UIAlertController(title: "Create Segment Playlist", message: "This feature allows you to create a playlist of video segments. Add multiple A-B points to create a custom viewing sequence.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    func updateCurrentTime(_ time: CMTime) {
        currentPlayerTime = time
    }
}

// MARK: - UITableViewDelegate, UITableViewDataSource

extension ABLoopViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return selectedMode == .abLoop ? abLoops.count : segmentPlaylists.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ABLoopCell", for: indexPath) as! ABLoopTableViewCell

        if selectedMode == .abLoop {
            let loop = abLoops[indexPath.row]
            let isActive = abLoopManager.getActiveLoop()?.id == loop.id
            cell.configure(with: loop, isActive: isActive)
        } else {
            let playlist = segmentPlaylists[indexPath.row]
            let isActive = abLoopManager.getActiveSegmentPlaylist()?.id == playlist.id
            cell.configure(with: playlist, isActive: isActive)
        }

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        if selectedMode == .abLoop {
            let loop = abLoops[indexPath.row]
            delegate?.didSelectABLoop(loop)
            delegate?.didRequestSeek(to: loop.pointA.toCMTime())
        } else {
            let playlist = segmentPlaylists[indexPath.row]
            delegate?.didSelectSegmentPlaylist(playlist)
            if let firstSegment = playlist.segments.first {
                delegate?.didRequestSeek(to: firstSegment.startPoint.toCMTime())
            }
        }

        updateStopButtonVisibility()
        tableView.reloadData()
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            if selectedMode == .abLoop {
                let loop = abLoops[indexPath.row]
                abLoopManager.removeABLoop(withId: loop.id, for: videoIdentifier)
                abLoops.remove(at: indexPath.row)
            } else {
                let playlist = segmentPlaylists[indexPath.row]
                abLoopManager.removeSegmentPlaylist(withId: playlist.id, for: videoIdentifier)
                segmentPlaylists.remove(at: indexPath.row)
            }
            tableView.deleteRows(at: [indexPath], with: .fade)
            updateStopButtonVisibility()
        }
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 60
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
        loadData()
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
        $0.layer.cornerRadius = 4
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
            make.width.height.equalTo(8)
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

    func configure(with loop: ABLoop, isActive: Bool) {
        titleLabel.text = loop.name ?? "A-B Loop"
        detailLabel.text = "\(loop.pointA.toString()) → \(loop.pointB.toString())"
        activeIndicator.isHidden = !isActive
    }

    func configure(with playlist: SegmentPlaylist, isActive: Bool) {
        titleLabel.text = playlist.name
        detailLabel.text = "\(playlist.segments.count) segment(s)"
        activeIndicator.isHidden = !isActive
    }
}
