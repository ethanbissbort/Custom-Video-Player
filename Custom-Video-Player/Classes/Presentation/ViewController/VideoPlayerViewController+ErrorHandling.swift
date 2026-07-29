import AVFoundation
import UIKit

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
            setUpPlayerItemError(errorMessage: CVPLocalized(
                "error.network",
                value: "Please check your internet connection and try again.",
                comment: "Full-screen playback error shown when the device appears to be offline"
            ))
        } else if error is AVError {
            setUpPlayerItemError(errorMessage: CVPLocalized(
                "error.playback",
                value: "This video could not be played.",
                comment: "Full-screen playback error shown when AVFoundation cannot play the item"
            ))
        } else {
            setUpPlayerItemError(errorMessage: CVPLocalized(
                "error.title",
                value: "Something went wrong. Please try again!",
                comment: "Full-screen playback error shown for an unrecognised failure"
            ))
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
                self.setUpPlayerItemError(errorMessage: CVPLocalized(
                    "error.interrupted",
                    value: "Playback was interrupted. Please try again.",
                    comment: "Full-screen playback error shown when playback stops short of the end"
                ))
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

        // The player is gone and the whole screen is now this error, so VoiceOver has to be told
        // to re-read it — otherwise focus stays on a transport control that no longer exists and
        // the user is never told why playback stopped.
        UIAccessibility.post(notification: .screenChanged, argument: errorView)
    }
}
