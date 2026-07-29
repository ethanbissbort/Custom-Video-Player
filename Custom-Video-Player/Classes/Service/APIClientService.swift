import Foundation

/// Error types for network requests made by `APIClientService`.
enum APIClientError: LocalizedError {
    case unacceptableStatusCode(Int)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .unacceptableStatusCode(let statusCode):
            return "The server responded with HTTP status code \(statusCode)."
        case .emptyResponse:
            return "The server returned neither data nor an error."
        }
    }
}

/// A service class for making network requests.
final class APIClientService {

    /// Constants used when building requests.
    private enum Constants {
        static let timeout: TimeInterval = 15
        static let acceptableStatusCodes = 200..<300
    }

    /// Makes a data request from the specified URL.
    ///
    /// A non-2xx response is reported as a failure: URLSession treats a 404 or 403 as a
    /// successful transfer, so without this check an HTML error page would be handed to the
    /// manifest parser and surface as a bogus, "Auto"-only quality menu.
    ///
    /// - Parameters:
    ///   - url: The URL to request data from.
    ///   - completion: A closure to be executed when the request finishes, containing a `Result` enum with either the requested data or an error.
    func requestData(from url: URL, completion: @escaping (Result<Data, Error>) -> Void) {
        let session = URLSession.shared

        var request = URLRequest(url: url)
        request.timeoutInterval = Constants.timeout

        let task = session.dataTask(with: request) { data, response, error in
            let result: Result<Data, Error>

            if let error = error {
                result = .failure(error)
            } else if let httpResponse = response as? HTTPURLResponse,
                      !Constants.acceptableStatusCodes.contains(httpResponse.statusCode) {
                result = .failure(APIClientError.unacceptableStatusCode(httpResponse.statusCode))
            } else if let data = data {
                result = .success(data)
            } else {
                // If no data or error is received, report it rather than silently succeeding.
                result = .failure(APIClientError.emptyResponse)
            }

            DispatchQueue.main.async {
                completion(result)
            }
        }
        task.resume()
    }
}
