import Foundation
import UIKit

/// Extension to UIView providing a method to round specific corners of the view.
///
/// Deliberately `internal`: a `public extension UIView` injects this method into every view of
/// every app that links the library, which is not part of the player's contract.
extension UIView {

    /// Rounds the specified corners of the view with a given radius.
    ///
    /// - Parameters:
    ///   - corners: The corners to be rounded. Defaults to all four corners.
    ///   - cornerRadius: The radius for the corners.
    func roundCorners(
        corners: CACornerMask = [
            .layerMinXMaxYCorner,
            .layerMaxXMaxYCorner,
            .layerMinXMinYCorner,
            .layerMaxXMinYCorner
        ],
        cornerRadius: CGFloat
    ) {
        layer.maskedCorners = corners
        layer.masksToBounds = true
        layer.cornerRadius = cornerRadius
    }
}
