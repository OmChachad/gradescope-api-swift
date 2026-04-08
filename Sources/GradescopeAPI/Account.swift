import Foundation

public final class Account {
    let client: GradescopeHTTPClient

    init(client: GradescopeHTTPClient) {
        self.client = client
    }

    public func getCourses() async throws -> CoursesByRole {
        let response = try await client.get("/account")
        guard response.response.statusCode == 200 else {
            throw GradescopeError.requestFailed(
                statusCode: response.response.statusCode,
                message: response.bodyText
            )
        }
        return GradescopeParsers.courses(from: response.bodyText)
    }

    public func getCourseUsers(_ courseID: String) async throws -> [Member]? {
        guard !courseID.isEmpty else {
            throw GradescopeError.invalidCourseID
        }

        do {
            let response = try await client.get(
                "/courses/\(courseID)/memberships",
                authorized: true
            )
            return GradescopeParsers.courseMembers(from: response.bodyText, courseID: courseID)
        } catch is GradescopeError {
            return nil
        }
    }

    public func getAssignments(_ courseID: String) async throws -> [Assignment] {
        guard !courseID.isEmpty else {
            throw GradescopeError.invalidCourseID
        }

        let response: HTTPDataResponse
        do {
            response = try await client.get(
                "/courses/\(courseID)/assignments",
                authorized: true
            )
        } catch GradescopeError.notAuthorized {
            response = try await client.get(
                "/courses/\(courseID)",
                authorized: true
            )
        }

        return GradescopeParsers.assignments(from: response.bodyText)
    }

    public func getAssignmentSubmissions(
        courseID: String,
        assignmentID: String
    ) async throws -> [String: [String]] {
        guard !courseID.isEmpty, !assignmentID.isEmpty else {
            throw GradescopeError.invalidParameters("One or more invalid parameters")
        }

        let reviewPath = "/courses/\(courseID)/assignments/\(assignmentID)/review_grades"
        let response = try await client.get(reviewPath, authorized: true)
        let submissionIDs = GradescopeParsers.submissionIDs(from: response.bodyText)

        var result: [String: [String]] = [:]
        for submissionID in submissionIDs {
            let files = try await getSubmissionFiles(
                courseID: courseID,
                assignmentID: assignmentID,
                submissionID: submissionID
            )
            result[submissionID] = files
        }
        return result
    }

    public func getAssignmentSubmission(
        studentEmail: String,
        courseID: String,
        assignmentID: String
    ) async throws -> [String] {
        guard !studentEmail.isEmpty, !courseID.isEmpty, !assignmentID.isEmpty else {
            throw GradescopeError.invalidParameters("One or more invalid parameters")
        }

        let reviewPath = "/courses/\(courseID)/assignments/\(assignmentID)/review_grades"
        let response = try await client.get(reviewPath, authorized: true)
        guard let submissionID = GradescopeParsers.submissionID(for: studentEmail, in: response.bodyText) else {
            throw GradescopeError.noSubmissionFound
        }

        return try await getSubmissionFiles(
            courseID: courseID,
            assignmentID: assignmentID,
            submissionID: submissionID
        )
    }

    public func getAssignmentGraders(
        courseID: String,
        questionID: String
    ) async throws -> Set<String> {
        guard !courseID.isEmpty, !questionID.isEmpty else {
            throw GradescopeError.invalidParameters("One or more invalid parameters")
        }

        let response = try await client.get(
            "/courses/\(courseID)/questions/\(questionID)/submissions",
            authorized: true
        )
        return GradescopeParsers.graders(from: response.bodyText)
    }

    private func getSubmissionFiles(
        courseID: String,
        assignmentID: String,
        submissionID: String
    ) async throws -> [String] {
        let path = "/courses/\(courseID)/assignments/\(assignmentID)/submissions/\(submissionID).json?content=react&only_keys[]=text_files&only_keys[]=file_comments"
        let response = try await client.get(path)
        guard response.response.statusCode == 200 else {
            throw GradescopeError.requestFailed(
                statusCode: response.response.statusCode,
                message: response.bodyText
            )
        }
        return try GradescopeParsers.submissionFiles(from: response.data)
    }
}
