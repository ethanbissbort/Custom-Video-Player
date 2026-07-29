import Foundation
import os

/// A class for handling the resources associated with the custom video player.
final class CustomVideoPlayer {

    /// A library must not `print` into the host app's console; route diagnostics through
    /// the unified log instead, matching `ABLoopManager`.
    private static let logger = Logger(subsystem: "com.customvideoplayer", category: "Resources")

    /// The bundle containing the resources for the custom video player.
    ///
    /// A missing resource bundle degrades to the framework bundle instead of trapping: this is
    /// a `static let` touched while building views, so a consumer's Podfile misconfiguration
    /// would otherwise be a deterministic crash on first present. Everything downstream
    /// (see `NameableAsset`) already falls back to a clear color or an empty image.
    static let resourceBundle: Bundle = {
        #if SWIFT_PACKAGE
        // When using Swift Package Manager, use the module bundle.
        return Bundle.module
        #else
        // When using Cocoapods, locate the resource bundle manually.
        let myBundle = Bundle(for: CustomVideoPlayer.self)

        // Ensure the URL for the resource bundle is found.
        guard let resourceBundleURL = myBundle.url(forResource: "ResourcesBundle", withExtension: "bundle") else {
            CustomVideoPlayer.logger.error("ResourcesBundle.bundle not found; falling back to the framework bundle. Assets will be missing.")
            return myBundle
        }

        // Ensure the resource bundle is accessible.
        guard let resourceBundle = Bundle(url: resourceBundleURL) else {
            CustomVideoPlayer.logger.error("ResourcesBundle.bundle could not be opened; falling back to the framework bundle. Assets will be missing.")
            return myBundle
        }

        return resourceBundle
        #endif
    }()
}
