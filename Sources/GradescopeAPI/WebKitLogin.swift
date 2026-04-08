import Foundation
#if canImport(WebKit)
import WebKit

@MainActor
public extension GSConnection {
    func loginWithWebKit(_ email: String, _ password: String) async throws {
        let browser = GradescopeWebKitBrowser(baseURL: gradescopeBaseURL)
        let result = try await browser.login(email: email, password: password)
        client.attachWebKitBrowser(browser, csrfToken: result.csrfToken)
        authenticate(cookieHeader: result.cookieHeader, csrfToken: result.csrfToken)
    }

    func loginWithWebKit(email: String, password: String) async throws {
        try await loginWithWebKit(email, password)
    }
}

@MainActor
final class GradescopeWebKitBrowser: NSObject, WKNavigationDelegate {
    struct Result {
        let cookieHeader: String
        let csrfToken: String?
    }

    struct RequestResult {
        let statusCode: Int
        let finalURL: URL?
        let body: String
        let headers: [String: String]
    }

    private let baseURL: URL
    private let webView: WKWebView

    private var email = ""
    private var password = ""
    private var hasSubmittedCredentials = false
    private var continuation: CheckedContinuation<Result, Error>?
    private var timeoutTask: Task<Void, Never>?

    init(baseURL: URL) {
        self.baseURL = baseURL
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        self.webView.navigationDelegate = self
    }

    func login(email: String, password: String) async throws -> Result {
        self.email = email
        self.password = password
        self.hasSubmittedCredentials = false

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
                await self?.finish(with: .failure(GradescopeError.requestFailed(statusCode: 408, message: "WebKit login timed out")))
            }

            let request = URLRequest(url: baseURL.appendingPathComponent("login"))
            webView.load(request)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak self] in
            guard let self, let url = webView.url else {
                return
            }

            let path = url.path.lowercased()
            if path == "/account" || path.hasPrefix("/account/") {
                do {
                    let result = try await buildAuthenticatedResult()
                    await finish(with: .success(result))
                } catch {
                    await finish(with: .failure(error))
                }
                return
            }

            if path == "/login" {
                do {
                    if hasSubmittedCredentials {
                        let bodyText = try await pageBodyText()
                        if bodyText.localizedCaseInsensitiveContains("email")
                            && bodyText.localizedCaseInsensitiveContains("password")
                        {
                            await finish(with: .failure(GradescopeError.invalidCredentials))
                        }
                    } else {
                        hasSubmittedCredentials = true
                        try await submitLoginForm()
                    }
                } catch {
                    await finish(with: .failure(error))
                }
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor [weak self] in
            await self?.finish(with: .failure(error))
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor [weak self] in
            await self?.finish(with: .failure(error))
        }
    }

    private func submitLoginForm() async throws {
        let emailLiteral = try javascriptStringLiteral(email)
        let passwordLiteral = try javascriptStringLiteral(password)
        let script = """
        (function() {
            const form = document.querySelector('form[action="/login"]');
            const email = document.querySelector('input[name="session[email]"]');
            const password = document.querySelector('input[name="session[password]"]');
            if (!form || !email || !password) { return "missing-form"; }
            email.value = \(emailLiteral);
            email.dispatchEvent(new Event('input', { bubbles: true }));
            email.dispatchEvent(new Event('change', { bubbles: true }));
            password.value = \(passwordLiteral);
            password.dispatchEvent(new Event('input', { bubbles: true }));
            password.dispatchEvent(new Event('change', { bubbles: true }));
            form.submit();
            return "submitted";
        })();
        """

        let result = try await evaluateJavaScriptString(script)
        guard result == "submitted" else {
            throw GradescopeError.parsingFailed("Gradescope login form")
        }
    }

    func performRequest(
        url: URL,
        method: String,
        headers: [String: String],
        body: Data?
    ) async throws -> RequestResult {
        let urlLiteral = try javascriptStringLiteral(url.absoluteString)
        let methodLiteral = try javascriptStringLiteral(method)
        let headersLiteral = try jsonStringLiteral(headers)
        let bodyLiteral = try jsonStringLiteral(body?.base64EncodedString())

        let script = """
        (function() {
            const url = \(urlLiteral);
            const method = \(methodLiteral);
            const headers = \(headersLiteral);
            const bodyBase64 = \(bodyLiteral);
            const xhr = new XMLHttpRequest();
            xhr.open(method, url, false);
            xhr.withCredentials = true;
            for (const [key, value] of Object.entries(headers)) {
                xhr.setRequestHeader(key, value);
            }
            if (bodyBase64 !== null) {
                const binary = atob(bodyBase64);
                const bytes = Uint8Array.from(binary, c => c.charCodeAt(0));
                xhr.send(bytes);
            } else {
                xhr.send();
            }
            const responseHeaders = {};
            const rawHeaders = xhr.getAllResponseHeaders().trim().split(/\\r?\\n/);
            for (const line of rawHeaders) {
                if (!line) { continue; }
                const index = line.indexOf(":");
                if (index > 0) {
                    const key = line.slice(0, index).trim().toLowerCase();
                    const value = line.slice(index + 1).trim();
                    responseHeaders[key] = value;
                }
            }
            return JSON.stringify({
                statusCode: xhr.status,
                finalURL: xhr.responseURL,
                body: xhr.responseText,
                headers: responseHeaders
            });
        })();
        """

        guard let jsonText = try await evaluateJavaScriptString(script),
              let data = jsonText.data(using: .utf8) else {
            throw GradescopeError.parsingFailed("WebKit fetch response")
        }

        let payload = try JSONDecoder().decode(RequestResultDTO.self, from: data)
        return RequestResult(
            statusCode: payload.statusCode,
            finalURL: payload.finalURL.flatMap(URL.init(string:)),
            body: payload.body,
            headers: payload.headers
        )
    }

    private func buildAuthenticatedResult() async throws -> Result {
        let cookies = await allCookies()
            .filter { $0.domain.contains("gradescope.com") }
            .sorted { $0.name < $1.name }

        guard !cookies.isEmpty else {
            throw GradescopeError.notLoggedIn
        }

        let cookieHeader = cookies
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")

        let csrfToken = try await evaluateJavaScriptString(
            "document.querySelector('meta[name=\"csrf-token\"]')?.content || null;"
        )

        return Result(cookieHeader: cookieHeader, csrfToken: csrfToken)
    }

    private func allCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }

    private func pageBodyText() async throws -> String {
        try await evaluateJavaScriptString("document.body ? document.body.innerText : '';") ?? ""
    }

    private func evaluateJavaScriptString(_ script: String) async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: result as? String)
                }
            }
        }
    }

    private func javascriptStringLiteral(_ value: String) throws -> String {
        let data = try JSONEncoder().encode(value)
        return String(decoding: data, as: UTF8.self)
    }

    private func jsonStringLiteral<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        return String(decoding: data, as: UTF8.self)
    }

    private func finish(with result: Swift.Result<Result, Error>) async {
        timeoutTask?.cancel()
        timeoutTask = nil

        guard let continuation else {
            return
        }
        self.continuation = nil

        switch result {
        case .success(let success):
            continuation.resume(returning: success)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }

    private struct RequestResultDTO: Decodable {
        let statusCode: Int
        let finalURL: String?
        let body: String
        let headers: [String: String]
    }
}
#endif
