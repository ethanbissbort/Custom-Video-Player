import Foundation

/// A structure representing the video quality with bitrate and resolution.
struct VideoQuality {
    let bitrate: Double
    let resolution: String
}

/// Extension to provide additional functionalities for arrays of VideoQuality.
extension [VideoQuality] {

    /// Sorts the video qualities by bitrate in descending order and inserts an "Auto" option at the beginning.
    ///
    /// An empty array is left empty. "Auto" only means anything next to the variants it can switch
    /// between, and the settings button is unhidden whenever the quality list is non-empty — so
    /// prepending it unconditionally turned an unparseable or empty manifest into a working-looking
    /// quality menu with a single bogus row.
    mutating func sortAndInsertAutoVideoQualityOption() {
        guard !isEmpty else { return }
        sort(by: { $0.bitrate > $1.bitrate })
        let autoQualityOption = VideoQuality(bitrate: Double.greatestFiniteMagnitude, resolution: "Auto")
        insert(autoQualityOption, at: 0)
    }
}

/// A helper class for handling M3U8 manifest data to fetch supported video qualities.
final class M3u8Helper {
    
    /// Constants used for parsing the M3U8 manifest.
    private enum Constants {
        static let bandwidth = "BANDWIDTH"
        static let resolution = "RESOLUTION"
    }

    /// An array to store the video qualities.
    private var qualities: [VideoQuality] = []

    /// Fetches supported video qualities from the provided M3U8 manifest data.
    ///
    /// - Parameter data: The M3U8 manifest data.
    /// - Returns: The supported qualities, highest bitrate first and led by an "Auto" entry, or an
    ///   empty array when the data declares no usable variant. Callers use emptiness to decide
    ///   whether to offer a quality menu at all, so an unparseable manifest must yield nothing.
    func fetchSupportedVideoQualities(with data: Data) -> [VideoQuality] {
        handleManifest(data: data)
        qualities.sortAndInsertAutoVideoQualityOption()
        return qualities
    }

    /// Handles the M3U8 manifest data by parsing it to extract video qualities.
    ///
    /// - Parameter data: The M3U8 manifest data.
    private func handleManifest(data: Data) {
        if let stringData = String(data: data, encoding: .utf8) {
            qualities = parse(stringData: stringData)
        }
    }

    /// Parses the string representation of the M3U8 manifest to extract video qualities.
    ///
    /// - Parameter stringData: The string representation of the M3U8 manifest.
    /// - Returns: An array of `VideoQuality` objects.
    private func parse(stringData: String) -> [VideoQuality] {
        var result: [VideoQuality] = []
        // Split on any newline so CRLF (\r\n) manifests don't leave a trailing
        // "\r" on the last attribute of each line, which would break parsing.
        let rows = stringData.components(separatedBy: .newlines)

        for row in rows {
            if let quality = quality(from: row) {
                if let index = result.firstIndex(where: { $0.resolution == quality.resolution }) {
                    if result[index].bitrate < quality.bitrate {
                        result.remove(at: index)
                        result.append(quality)
                    }
                } else {
                    result.append(quality)
                }
            }
        }
        return result
    }

    /// Extracts a `VideoQuality` object from a single row of the M3U8 manifest.
    ///
    /// - Parameter segments: A single row of the M3U8 manifest.
    /// - Returns: A `VideoQuality` object if parsing is successful, otherwise `nil`.
    private func quality(from segments: String) -> VideoQuality? {
        let dataSegments = attributes(from: segments)

        if let bandwidthValue = value(ofAttribute: Constants.bandwidth, in: dataSegments),
           let resolutionValue = value(ofAttribute: Constants.resolution, in: dataSegments),
           let bitrate = Double(bandwidthValue),
           let resolution = prettyResolution(from: resolutionValue) {
            return VideoQuality(bitrate: bitrate, resolution: resolution)
        }

        return nil
    }

    /// Splits a manifest row into its comma-separated attributes.
    ///
    /// Only commas outside of a quoted value separate attributes, so a quoted list such as
    /// `CODECS="avc1.4d401f,mp4a.40.2"` stays in one piece instead of fragmenting the row and
    /// corrupting the attributes read from it.
    ///
    /// - Parameter row: A single row of the M3U8 manifest.
    /// - Returns: The attributes of the row, still in `NAME=VALUE` form.
    private func attributes(from row: String) -> [String] {
        var result: [String] = []
        var current = ""
        var isQuoted = false

        for character in row {
            switch character {
            case "\"":
                isQuoted.toggle()
                current.append(character)
            case "," where !isQuoted:
                result.append(current)
                current = ""
            default:
                current.append(character)
            }
        }
        result.append(current)

        return result
    }

    /// Returns the value of the named attribute.
    ///
    /// The name is matched exactly, so `BANDWIDTH` never picks up the `AVERAGE-BANDWIDTH` of a
    /// variant that happens to list the average first — which would advertise the average
    /// bitrate as the peak one.
    ///
    /// - Parameters:
    ///   - attribute: The name of the attribute to look up.
    ///   - attributes: The attributes of a manifest row, in `NAME=VALUE` form.
    /// - Returns: The attribute's value stripped of whitespace and enclosing quotes, or `nil`.
    private func value(ofAttribute attribute: String, in attributes: [String]) -> String? {
        for segment in attributes {
            let components = segment.components(separatedBy: "=")
            guard components.count > 1, name(from: components[0]) == attribute else { continue }
            // Re-join so a value that legitimately contains "=" survives intact.
            let attributeValue = components.dropFirst().joined(separator: "=")
            return attributeValue
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }

        return nil
    }

    /// Normalises the name side of an attribute so it can be compared exactly.
    ///
    /// The first attribute of a row carries its tag (`#EXT-X-STREAM-INF:BANDWIDTH`), which is
    /// dropped here along with any surrounding whitespace.
    ///
    /// - Parameter rawName: The text preceding the attribute's first "=".
    /// - Returns: The bare attribute name.
    private func name(from rawName: String) -> String {
        let trimmed = rawName.trimmingCharacters(in: .whitespaces)
        guard let tagSeparatorIndex = trimmed.lastIndex(of: ":") else { return trimmed }
        return String(trimmed[trimmed.index(after: tagSeparatorIndex)...])
    }

    /// Converts a resolution string from the M3U8 manifest into a more readable format.
    ///
    /// - Parameter resolution: The resolution string from the manifest.
    /// - Returns: A formatted resolution string, or `nil` if the format is invalid.
    private func prettyResolution(from resolution: String) -> String? {
        let resolutionSegments = resolution.lowercased().components(separatedBy: "x")

        if resolutionSegments.count > 1 {
            return resolutionSegments[1] + "p"
        }

        return nil
    }
}
