import AVFoundation

extension VideoPlayerViewController {

    /// Handles player errors that occur during initial load or runtime playback
    ///
    /// Must be called on the main thread — it ends up presenting UI. Every call site in this file
    /// and in `observeValue(forKeyPath:of:change:context:)` marshals via `runOnMainThread(_:)`
    /// first, because AVFoundation delivers these callbacks on arbitrary threads.
    ///
    /// - Parameter error: The error that occurred
    func handlePlayerError(_ error: Error?) {
        guard let error = error else {
            return
        }
        if error is URLError {
            setUpPlayerItemError(errorMessage: "Please check your internet connection. Seems to be offline!")
        } else if error is AVError {
            setUpPlayerItemError(errorMessage: "Video Player failed to load!")
        } else {
            setUpPlayerItemError(errorMessage: "Something went wrong. Please try again!")
        }
    }

    /// Called when playback fails to complete
    ///
    /// AVFoundation posts `AVPlayerItem` notifications on whichever thread produced them, so the
    /// entire UIKit-touching body is marshalled onto the main queue.
    ///
    /// - Parameter notification: Notification containing error information
    @objc func playerItemFailedToPlayToEndTime(notification: Notification) {
        runOnMainThread { [weak self] in
            guard let self = self else { return }
            self.activityIndicatorView.stopAnimating()
            if let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error {
                self.handlePlayerError(error)
            } else {
                self.setUpPlayerItemError(errorMessage: "Playback was interrupted. Please try again.")
            }
        }
    }

    /// Called when playback stalls (e.g., buffering)
    ///
    /// The indicator started here is stopped again by the `playbackLikelyToKeepUp` KVO observer in
    /// VideoPlayerViewController.swift — this notification has no "recovered" counterpart of its own.
    @objc func playerItemPlaybackStalled() {
        runOnMainThread { [weak self] in
            guard let self = self else { return }
            // Show loading indicator during buffering
            self.activityIndicatorView.startAnimating()

            // Reset controls hidden timer to keep controls visible during stall
            self.invalidateControlsHiddenTimer()
        }
    }

    /// Called when playback successfully reaches the end
    @objc func playerItemDidPlayToEndTime() {
        runOnMainThread { [weak self] in
            guard let self = self else { return }
            // Reset to beginning for non-live content
            guard let isLiveContent = self.viewModel.isLiveContent, !isLiveContent else { return }
            self.player?.seek(to: CMTime.zero)
            self.pausePlayer()
        }
    }

    /// Replaces the player with a full-screen error message.
    ///
    /// Must be called on the main thread; see `handlePlayerError(_:)`.
    func setUpPlayerItemError(errorMessage: String) {
        resetPlayerItems()
        let errorView = VideoPlayerErrorView(
            title: errorMessage,
            onBackButtonClicked: { [weak self] in
                guard let self = self else { return }
                self.coordinator.navigationController.dismiss(animated: true)
            }
        )
        view.addSubview(errorView)
        errorView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(CGFloat.space16)
            make.trailing.equalToSuperview().offset(-CGFloat.space16)
            make.top.bottom.equalToSuperview()
        }
    }
}
