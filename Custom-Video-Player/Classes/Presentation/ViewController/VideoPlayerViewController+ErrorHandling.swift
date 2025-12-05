import AVFoundation

extension VideoPlayerViewController {

    /// Handles player errors that occur during initial load or runtime playback
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
    /// - Parameter notification: Notification containing error information
    @objc func playerItemFailedToPlayToEndTime(notification: Notification) {
        activityIndicatorView.stopAnimating()
        if let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error {
            handlePlayerError(error)
        } else {
            setUpPlayerItemError(errorMessage: "Playback was interrupted. Please try again.")
        }
    }

    /// Called when playback stalls (e.g., buffering)
    @objc func playerItemPlaybackStalled() {
        // Show loading indicator during buffering
        activityIndicatorView.startAnimating()

        // Reset controls hidden timer to keep controls visible during stall
        invalidateControlsHiddenTimer()
    }

    /// Called when playback successfully reaches the end
    @objc func playerItemDidPlayToEndTime() {
        // Reset to beginning for non-live content
        guard let isLiveContent = viewModel.isLiveContent, !isLiveContent else { return }
        player?.seek(to: CMTime.zero)
        pausePlayer()
    }
    
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
