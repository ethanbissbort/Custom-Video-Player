import UIKit

/// A protocol for assets that have a name and optionally a namespace.
protocol NameableAsset: RawRepresentable where RawValue == String {
    var namespace: String? { get }
}

extension NameableAsset where RawValue == String {
    /// Default implementation for the namespace property. Returns nil by default.
    var namespace: String? { nil }
}

extension UIColor {
    /// Convenience initializer to create a UIColor from a NameableAsset.
    ///
    /// - Parameter color: The NameableAsset representing the color.
    convenience init<T: NameableAsset>(_ color: T) {
        var name = color.rawValue
        if let namespace = color.namespace {
            name = "\(namespace)/\(name)"
        }
        let resourceBundle = CustomVideoPlayer.resourceBundle
        let resolvedColor: UIColor?
        if #available(iOS 13, *) {
            resolvedColor = UIColor(named: name, in: resourceBundle, compatibleWith: .current)
        } else {
            resolvedColor = UIColor(named: name, in: resourceBundle, compatibleWith: nil)
        }
        // Fall back to a clear color rather than crashing if the asset is missing.
        self.init(cgColor: (resolvedColor ?? .clear).cgColor)
    }
}

extension UIImage {
    /// Convenience initializer to create a UIImage from a NameableAsset.
    ///
    /// - Parameters:
    ///   - image: The NameableAsset representing the image.
    ///   - resourceBundle: The bundle containing the image resources.
    convenience init<T: NameableAsset>(_ image: T, resourceBundle: Bundle) {
        var name = image.rawValue
        if let namespace = image.namespace {
            name = "\(namespace)/\(name)"
        }
        let resolvedImage: UIImage?
        if #available(iOS 13, *) {
            resolvedImage = UIImage(named: name, in: resourceBundle, compatibleWith: .current)
        } else {
            resolvedImage = UIImage(named: name, in: resourceBundle, compatibleWith: nil)
        }
        // Fall back to an empty image rather than crashing if the asset is missing.
        if let resolvedImage = resolvedImage, let cgImage = resolvedImage.cgImage {
            self.init(cgImage: cgImage, scale: resolvedImage.scale, orientation: resolvedImage.imageOrientation)
        } else {
            self.init()
        }
    }
}
