import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct HTTPDataResponse {
    let data: Data
    let response: HTTPURLResponse

    var bodyText: String {
        String(data: data, encoding: .utf8) ?? ""
    }
}

final class GradescopeHTTPClient {
    let baseURL: URL
    var urlSession: URLSession
    let cookieStorage: HTTPCookieStorage
    private(set) var csrfToken: String?
    private var storedCookies: [HTTPCookie] = []
    private var rawCookieHeader: String?
    #if canImport(WebKit)
    private var webKitBrowser: GradescopeWebKitBrowser?
    #endif

    init(baseURL: URL = DEFAULT_GRADESCOPE_BASE_URL) {
        self.baseURL = baseURL
        self.cookieStorage = HTTPCookieStorage.shared

        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = cookieStorage
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 60
        self.urlSession = URLSession(configuration: configuration)
    }

    func setCSRFToken(_ token: String?) {
        csrfToken = token
    }

    func setRawCookie(_ rawSetCookieHeader: String) {
        if let cookiePair = rawSetCookieHeader.split(separator: ";", maxSplits: 1).first {
            rawCookieHeader = String(cookiePair)
        }
    }

    func setCookieHeader(_ cookieHeader: String) {
        rawCookieHeader = cookieHeader
    }

    #if canImport(WebKit)
    @MainActor
    func attachWebKitBrowser(_ browser: GradescopeWebKitBrowser, csrfToken: String?) {
        self.webKitBrowser = browser
        self.csrfToken = csrfToken
    }
    #endif

    package var currentCookieHeader: String? {
        rawCookieHeader
    }

    func captureCookies(from response: HTTPURLResponse, url: URL) {
        storeCookies(from: response, url: url)
    }

    func get(_ path: String, authorized: Bool = false) async throws -> HTTPDataResponse {
        let response = try await send(method: "GET", path: path)
        if authorized {
            return try checkAuthorizedPage(response)
        }
        return response
    }

    func postForm(
        _ path: String,
        fields: [(String, String)],
        referer: URL? = nil
    ) async throws -> HTTPDataResponse {
        let body = Data(formURLEncodedString(fields).utf8)
        return try await send(
            method: "POST",
            path: path,
            headers: [
                "Content-Type": "application/x-www-form-urlencoded; charset=utf-8",
                "Referer": referer?.absoluteString,
            ],
            body: body
        )
    }

    func postWithQuery(
        _ path: String,
        queryItems: [(String, String)],
        referer: URL? = nil
    ) async throws -> HTTPDataResponse {
        let query = formURLEncodedString(queryItems)
        return try await send(
            method: "POST",
            path: "\(path)?\(query)",
            headers: [
                "Referer": referer?.absoluteString,
            ]
        )
    }

    func postMultipart(
        _ path: String,
        multipart: MultipartFormData,
        referer: URL? = nil
    ) async throws -> HTTPDataResponse {
        try await send(
            method: "POST",
            path: path,
            headers: [
                "Content-Type": multipart.contentType,
                "Referer": referer?.absoluteString,
            ],
            body: multipart.body
        )
    }

    func postJSON(_ path: String, jsonObject: Any) async throws -> HTTPDataResponse {
        let data = try JSONSerialization.data(withJSONObject: jsonObject)
        return try await send(
            method: "POST",
            path: path,
            headers: [
                "Content-Type": "application/json",
            ],
            body: data
        )
    }

    @discardableResult
    func send(
        method: String,
        path: String,
        headers: [String: String?] = [:],
        body: Data? = nil
    ) async throws -> HTTPDataResponse {
        let url = try resolvedURL(for: path)

        #if canImport(WebKit)
        if let webKitBrowser {
            let compactHeaders = headers.reduce(into: [String: String]()) { partial, pair in
                if let value = pair.value {
                    partial[pair.key] = value
                }
            }
            let webKitResponse = try await webKitBrowser.performRequest(
                url: url,
                method: method,
                headers: compactHeaders,
                body: body
            )
            let response = HTTPURLResponse(
                url: webKitResponse.finalURL ?? url,
                statusCode: webKitResponse.statusCode,
                httpVersion: nil,
                headerFields: webKitResponse.headers
            )!
            let data = Data(webKitResponse.body.utf8)
            return HTTPDataResponse(data: data, response: response)
        }
        #endif

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body

        if let csrfToken {
            request.setValue(csrfToken, forHTTPHeaderField: "X-CSRF-Token")
        }

        for (name, value) in headers {
            if let value {
                request.setValue(value, forHTTPHeaderField: name)
            }
        }

        applyCookies(to: &request)

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GradescopeError.parsingFailed("HTTPURLResponse")
        }
        storeCookies(from: httpResponse, url: url)
        return HTTPDataResponse(data: data, response: httpResponse)
    }

    func resolvedURL(for path: String) throws -> URL {
        if let directURL = URL(string: path), directURL.scheme != nil {
            return directURL
        }
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw GradescopeError.invalidParameters("Invalid URL path: \(path)")
        }
        return url
    }

    func resolvedURL(for path: String, queryItems: [(String, String)]) throws -> URL {
        let base = try resolvedURL(for: path)
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw GradescopeError.invalidParameters("Invalid URL path: \(path)")
        }
        components.queryItems = queryItems.map { URLQueryItem(name: $0.0, value: $0.1) }
        guard let url = components.url else {
            throw GradescopeError.invalidParameters("Invalid URL path: \(path)")
        }
        return url
    }

    func urlEncodedFormBody(_ fields: [(String, String)]) -> Data {
        Data(formURLEncodedString(fields).utf8)
    }

    func formURLEncodedString(_ fields: [(String, String)]) -> String {
        fields
            .map { "\(formEscape($0.0))=\(formEscape($0.1))" }
            .joined(separator: "&")
    }

    private func formEscape(_ string: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._*"))
        return string.unicodeScalars.map { scalar -> String in
            if allowed.contains(scalar) {
                return String(scalar)
            }
            if scalar == " " {
                return "+"
            }
            return scalar.utf8.map { String(format: "%%%02X", $0) }.joined()
        }.joined()
    }

    private func applyCookies(to request: inout URLRequest) {
        if let rawCookieHeader {
            request.setValue(rawCookieHeader, forHTTPHeaderField: "Cookie")
            return
        }

        if !storedCookies.isEmpty {
            let relevantCookies = storedCookies.filter { cookie in
                guard let host = request.url?.host else {
                    return false
                }
                return host.hasSuffix(cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")))
            }
            let fields = HTTPCookie.requestHeaderFields(with: relevantCookies)
            for (name, value) in fields {
                request.setValue(value, forHTTPHeaderField: name)
            }
        }
    }

    private func storeCookies(from response: HTTPURLResponse, url: URL) {
        let rawSetCookie = response.allHeaderFields.first { pair in
            String(describing: pair.key).lowercased() == "set-cookie"
        }.map { String(describing: $0.value) }
        if let rawSetCookie {
            setRawCookie(rawSetCookie)
        }

        let headers = response.allHeaderFields.reduce(into: [String: String]()) { partial, pair in
            let key = String(describing: pair.key)
            let value = String(describing: pair.value)
            if key.lowercased() == "set-cookie" {
                partial["Set-Cookie"] = value
            } else {
                partial[key] = value
            }
        }

        let cookies = HTTPCookie.cookies(withResponseHeaderFields: headers, for: url)
        for cookie in cookies {
            cookieStorage.setCookie(cookie)
            merge(cookie: cookie)
        }
    }

    private func merge(cookie: HTTPCookie) {
        if let index = storedCookies.firstIndex(where: {
            $0.name == cookie.name && $0.domain == cookie.domain && $0.path == cookie.path
        }) {
            storedCookies[index] = cookie
        } else {
            storedCookies.append(cookie)
        }
    }

    func checkAuthorizedPage(_ response: HTTPDataResponse) throws -> HTTPDataResponse {
        switch response.response.statusCode {
        case 200:
            return response
        case 401:
            if
                let json = try? JSONSerialization.jsonObject(with: response.data) as? [String: String],
                let message = json.values.first
            {
                if message == "You are not authorized to access this page." {
                    throw GradescopeError.notAuthorized
                }
                if message == "You must be logged in to access this page." {
                    throw GradescopeError.notLoggedIn
                }
            }
            throw GradescopeError.requestFailed(statusCode: 401, message: response.bodyText)
        case 404:
            throw GradescopeError.pageNotFound
        default:
            throw GradescopeError.requestFailed(
                statusCode: response.response.statusCode,
                message: response.bodyText
            )
        }
    }
}
