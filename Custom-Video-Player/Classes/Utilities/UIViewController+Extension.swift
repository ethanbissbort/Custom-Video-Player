import UIKit
import os

/// A library must not `print` into the host app's console; route diagnostics through
/// the unified log instead, matching `ABLoopManager`.
private let orientationLogger = Logger(subsystem: "com.customvideoplayer", category: "Orientation")

/// Extension to UIViewController providing a method to reset the device orientation.
extension UIViewController {

    /// Resets the device orientation to the specified orientation mask.
    ///
    /// Implemented with `UIWindowScene.requestGeometryUpdate(_:errorHandler:)` rather than the
    /// `UIDevice.current.setValue(_:forKey: "orientation")` trick: that is undocumented KVC
    /// against a read-only property, it has been a no-op since iOS 16, it can raise
    /// `NSUnknownKeyException`, and it is a known App Store rejection trigger.
    ///
    /// - Parameter orientation: The orientation mask to be set.
    func resetOrientation(_ orientation: UIInterfaceOrientationMask) {
        // Let UIKit re-read `supportedInterfaceOrientations` before the geometry request,
        // otherwise the system rejects a rotation this controller does not yet advertise.
        setNeedsUpdateOfSupportedInterfaceOrientations()

        guard let windowScene = orientationWindowScene else {
            orientationLogger.error("Orientation update skipped: no window scene available.")
            return
        }

        windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: orientation)) { error in
            // The system rejects requests that conflict with the app's declared orientations.
            // That is a configuration problem in the host app, never a reason to crash.
            orientationLogger.error("Orientation update failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The window scene to apply orientation changes to.
    ///
    /// Falls back to the app's foreground scene because `resetOrientation(_:)` is also called
    /// from `viewDidLoad`, before the view has a window.
    private var orientationWindowScene: UIWindowScene? {
        if let windowScene = viewIfLoaded?.window?.windowScene {
            return windowScene
        }
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }
}
