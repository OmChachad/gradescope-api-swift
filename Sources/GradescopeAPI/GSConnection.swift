import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public final class GSConnection {
    let client: GradescopeHTTPClient

    public let gradescopeBaseURL: URL
    public private(set) var loggedIn = false
    public private(set) var account: Account?

    public var session: URLSession {
        client.urlSession
    }

    public init(gradescopeBaseURL: URL = DEFAULT_GRADESCOPE_BASE_URL) {
        self.gradescopeBaseURL = gradescopeBaseURL
        self.client = GradescopeHTTPClient(baseURL: gradescopeBaseURL)
    }

    @MainActor
    public func login(_ email: String, _ password: String) async throws {
        #if canImport(WebKit)
        return try await loginWithWebKit(email, password)
        #else
        return try await loginWithURLSessionTransport(email, password)
        #endif
    }

    private func loginWithURLSessionTransport(_ email: String, _ password: String) async throws {
        let cookieStorage = HTTPCookieStorage()
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = cookieStorage
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        let session = URLSession(configuration: configuration)

        let homepageURL = gradescopeBaseURL
        let (homepageData, homepageURLResponse) = try await session.data(from: homepageURL)
        let homepageBody = String(data: homepageData, encoding: .utf8) ?? ""
        guard let authenticityToken = GradescopeParsers.loginAuthenticityToken(from: homepageBody) else {
            throw GradescopeError.parsingFailed("login authenticity token")
        }
        guard let homepageResponse = homepageURLResponse as? HTTPURLResponse else {
            throw GradescopeError.parsingFailed("HTTPURLResponse")
        }
        let rawLoginCookie = homepageResponse.allHeaderFields.first { pair in
            String(describing: pair.key).lowercased() == "set-cookie"
        }.map { String(describing: $0.value) }
        if let rawSetCookie = rawLoginCookie {
            client.setRawCookie(rawSetCookie)
        }

        let query = client.formURLEncodedString([
            ("utf8", "✓"),
            ("session[email]", email),
            ("session[password]", password),
            ("session[remember_me]", "0"),
            ("commit", "Log In"),
            ("session[remember_me_sso]", "0"),
            ("authenticity_token", authenticityToken),
        ])

        let loginURL = URL(string: "\(gradescopeBaseURL.absoluteString)/login?\(query)")!
        var request = URLRequest(url: loginURL)
        request.httpMethod = "POST"
        if let rawLoginCookie,
           let cookiePair = rawLoginCookie.split(separator: ";", maxSplits: 1).first {
            request.setValue(String(cookiePair), forHTTPHeaderField: "Cookie")
        }

        let (data, urlResponse) = try await session.data(for: request)
        guard let response = urlResponse as? HTTPURLResponse else {
            throw GradescopeError.parsingFailed("HTTPURLResponse")
        }
        let bodyText = String(data: data, encoding: .utf8) ?? ""

        guard
            let finalURL = response.url,
            finalURL.absoluteString.contains("/account"),
            let csrfToken = GradescopeParsers.csrfToken(from: bodyText)
        else {
            throw GradescopeError.invalidCredentials
        }

        client.urlSession = session
        client.captureCookies(from: homepageResponse, url: homepageURL)
        client.captureCookies(from: response, url: loginURL)
        client.setCSRFToken(csrfToken)
        loggedIn = true
        account = Account(client: client)
    }

    @MainActor
    public func login(email: String, password: String) async throws {
        try await login(email, password)
    }

    public func authenticate(cookieHeader: String, csrfToken: String? = nil) {
        client.setCookieHeader(cookieHeader)
        client.setCSRFToken(csrfToken)
        loggedIn = true
        account = Account(client: client)
    }

    package func debugFetchHTML(path: String) async throws -> String {
        let response = try await client.get(path)
        return response.bodyText
    }
}

public extension GSConnection {
    func getExtensions(courseID: String, assignmentID: String) async throws -> [String: Extension] {
        let response = try await client.get(
            "/courses/\(courseID)/assignments/\(assignmentID)/extensions"
        )
        guard response.response.statusCode == 200 else {
            throw GradescopeError.requestFailed(
                statusCode: response.response.statusCode,
                message: response.bodyText
            )
        }
        return try GradescopeParsers.extensions(from: response.bodyText)
    }

    func updateStudentExtension(
        courseID: String,
        assignmentID: String,
        userID: String,
        releaseDate: Date? = nil,
        dueDate: Date? = nil,
        lateDueDate: Date? = nil
    ) async throws -> Bool {
        let dates = [releaseDate, dueDate, lateDueDate].compactMap { $0 }
        guard !dates.isEmpty else {
            throw GradescopeError.noDatesProvided
        }
        guard dates == dates.sorted() else {
            throw GradescopeError.invalidDateOrder
        }

        var settings: [String: Any] = ["visible": true]
        if let releaseDate {
            settings["release_date"] = [
                "type": "absolute",
                "value": GradescopeDateParser.utcJSONString(releaseDate),
            ]
        }
        if let dueDate {
            settings["due_date"] = [
                "type": "absolute",
                "value": GradescopeDateParser.utcJSONString(dueDate),
            ]
        }
        if let lateDueDate {
            settings["hard_due_date"] = [
                "type": "absolute",
                "value": GradescopeDateParser.utcJSONString(lateDueDate),
            ]
        }

        let response = try await client.postJSON(
            "/courses/\(courseID)/assignments/\(assignmentID)/extensions",
            jsonObject: [
                "override": [
                    "user_id": userID,
                    "settings": settings,
                ],
            ]
        )
        return response.response.statusCode == 200
    }

    func updateAssignmentDate(
        courseID: String,
        assignmentID: String,
        releaseDate: Date? = nil,
        dueDate: Date? = nil,
        lateDueDate: Date? = nil,
        timeZone: TimeZone = .current
    ) async throws -> Bool {
        let editPath = "/courses/\(courseID)/assignments/\(assignmentID)/edit"
        let postPath = "/courses/\(courseID)/assignments/\(assignmentID)"
        let editPage = try await client.get(editPath)
        guard let authenticityToken = GradescopeParsers.loginAuthenticityToken(from: editPage.bodyText)
            ?? HTML.firstMatch(
                "<input\\b[^>]*name\\s*=\\s*([\"'])authenticity_token\\1[^>]*value\\s*=\\s*([\"'])(.*?)\\2",
                in: editPage.bodyText,
                group: 3
            )
        else {
            throw GradescopeError.parsingFailed("assignment edit authenticity token")
        }

        let multipart = MultipartFormData(
            parts: [
                .init(name: "utf8", filename: nil, mimeType: nil, data: Data("✓".utf8)),
                .init(name: "_method", filename: nil, mimeType: nil, data: Data("patch".utf8)),
                .init(name: "authenticity_token", filename: nil, mimeType: nil, data: Data(authenticityToken.utf8)),
                .init(
                    name: "assignment[release_date_string]",
                    filename: nil,
                    mimeType: nil,
                    data: Data((releaseDate.map { GradescopeDateParser.assignmentFormString($0, timeZone: timeZone) } ?? "").utf8)
                ),
                .init(
                    name: "assignment[due_date_string]",
                    filename: nil,
                    mimeType: nil,
                    data: Data((dueDate.map { GradescopeDateParser.assignmentFormString($0, timeZone: timeZone) } ?? "").utf8)
                ),
                .init(
                    name: "assignment[allow_late_submissions]",
                    filename: nil,
                    mimeType: nil,
                    data: Data((lateDueDate == nil ? "0" : "1").utf8)
                ),
                .init(
                    name: "assignment[hard_due_date_string]",
                    filename: nil,
                    mimeType: nil,
                    data: Data((lateDueDate.map { GradescopeDateParser.assignmentFormString($0, timeZone: timeZone) } ?? "").utf8)
                ),
                .init(name: "commit", filename: nil, mimeType: nil, data: Data("Save".utf8)),
            ]
        )

        let response = try await client.postMultipart(
            postPath,
            multipart: multipart,
            referer: try client.resolvedURL(for: editPath)
        )
        guard (200..<300).contains(response.response.statusCode) else {
            throw GradescopeError.requestFailed(
                statusCode: response.response.statusCode,
                message: response.bodyText
            )
        }
        return response.response.statusCode == 200
    }

    func updateAssignmentTitle(
        courseID: String,
        assignmentID: String,
        assignmentName: String
    ) async throws -> Bool {
        let editPath = "/courses/\(courseID)/assignments/\(assignmentID)/edit"
        let postPath = "/courses/\(courseID)/assignments/\(assignmentID)"
        let editPage = try await client.get(editPath)
        guard let authenticityToken = HTML.firstMatch(
            "<input\\b[^>]*name\\s*=\\s*([\"'])authenticity_token\\1[^>]*value\\s*=\\s*([\"'])(.*?)\\2",
            in: editPage.bodyText,
            group: 3
        ) else {
            throw GradescopeError.parsingFailed("assignment edit authenticity token")
        }

        let multipart = MultipartFormData(
            parts: [
                .init(name: "utf8", filename: nil, mimeType: nil, data: Data("✓".utf8)),
                .init(name: "_method", filename: nil, mimeType: nil, data: Data("patch".utf8)),
                .init(name: "authenticity_token", filename: nil, mimeType: nil, data: Data(authenticityToken.utf8)),
                .init(name: "assignment[title]", filename: nil, mimeType: nil, data: Data(assignmentName.utf8)),
                .init(name: "commit", filename: nil, mimeType: nil, data: Data("Save".utf8)),
            ]
        )

        let response = try await client.postMultipart(
            postPath,
            multipart: multipart,
            referer: try client.resolvedURL(for: editPath)
        )
        guard (200..<300).contains(response.response.statusCode) else {
            throw GradescopeError.requestFailed(
                statusCode: response.response.statusCode,
                message: response.bodyText
            )
        }

        if response.bodyText.contains("form--requiredFieldStar") && response.bodyText.contains("Title") {
            throw GradescopeError.assignmentTitleInvalid(assignmentName)
        }

        return response.response.statusCode == 200
    }

    func updateAutograderImageName(
        courseID: String,
        assignmentID: String,
        imageName: String
    ) async throws -> Bool {
        let editPath = "/courses/\(courseID)/assignments/\(assignmentID)/configure_autograder"
        let postPath = "/courses/\(courseID)/assignments/\(assignmentID)"
        let editPage = try await client.get(editPath)
        guard let authenticityToken = HTML.firstMatch(
            "<input\\b[^>]*name\\s*=\\s*([\"'])authenticity_token\\1[^>]*value\\s*=\\s*([\"'])(.*?)\\2",
            in: editPage.bodyText,
            group: 3
        ) else {
            throw GradescopeError.parsingFailed("autograder authenticity token")
        }

        let multipart = MultipartFormData(
            parts: [
                .init(name: "utf8", filename: nil, mimeType: nil, data: Data("✓".utf8)),
                .init(name: "_method", filename: nil, mimeType: nil, data: Data("patch".utf8)),
                .init(name: "authenticity_token", filename: nil, mimeType: nil, data: Data(authenticityToken.utf8)),
                .init(name: "source_page", filename: nil, mimeType: nil, data: Data("configure_autograder".utf8)),
                .init(name: "assignment[image_name]", filename: nil, mimeType: nil, data: Data(imageName.utf8)),
            ]
        )

        let response = try await client.postMultipart(
            postPath,
            multipart: multipart,
            referer: try client.resolvedURL(for: editPath)
        )
        guard (200..<300).contains(response.response.statusCode) else {
            throw GradescopeError.requestFailed(
                statusCode: response.response.statusCode,
                message: response.bodyText
            )
        }

        return response.response.statusCode == 200
            && !response.bodyText.contains("Docker image not found in your current course!")
    }

    func uploadAssignment(
        courseID: String,
        assignmentID: String,
        files: [UploadFile],
        leaderboardName: String? = nil
    ) async throws -> URL? {
        let coursePath = "/courses/\(courseID)"
        let uploadPath = "/courses/\(courseID)/assignments/\(assignmentID)/submissions"
        let coursePage = try await client.get(coursePath)
        guard let csrfToken = GradescopeParsers.csrfToken(from: coursePage.bodyText) else {
            throw GradescopeError.parsingFailed("course page csrf token")
        }

        var parts: [MultipartFormData.Part] = [
            .init(name: "utf8", filename: nil, mimeType: nil, data: Data("✓".utf8)),
            .init(name: "authenticity_token", filename: nil, mimeType: nil, data: Data(csrfToken.utf8)),
            .init(name: "submission[method]", filename: nil, mimeType: nil, data: Data("upload".utf8)),
        ]

        for file in files {
            parts.append(
                .init(
                    name: "submission[files][]",
                    filename: file.filename,
                    mimeType: file.mimeType,
                    data: file.data
                )
            )
        }

        if let leaderboardName {
            parts.append(
                .init(
                    name: "submission[leaderboard_name]",
                    filename: nil,
                    mimeType: nil,
                    data: Data(leaderboardName.utf8)
                )
            )
        }

        let response = try await client.postMultipart(
            uploadPath,
            multipart: MultipartFormData(parts: parts),
            referer: try client.resolvedURL(for: coursePath)
        )

        let courseURL = try client.resolvedURL(for: coursePath)
        guard let finalURL = response.response.url else {
            return nil
        }

        if finalURL == courseURL || finalURL.absoluteString.hasSuffix("/submissions") {
            return nil
        }
        return finalURL
    }

    func uploadAssignment(
        courseID: String,
        assignmentID: String,
        leaderboardName: String? = nil,
        files: UploadFile...
    ) async throws -> URL? {
        try await uploadAssignment(
            courseID: courseID,
            assignmentID: assignmentID,
            files: files,
            leaderboardName: leaderboardName
        )
    }
}
