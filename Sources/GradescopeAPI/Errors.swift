import Foundation

public enum GradescopeError: Error, LocalizedError, Equatable, Sendable {
    case invalidCredentials
    case notAuthorized
    case notLoggedIn
    case pageNotFound
    case invalidCourseID
    case invalidParameters(String)
    case noDatesProvided
    case invalidDateOrder
    case noSubmissionFound
    case unsupportedSubmissionType(String)
    case assignmentTitleInvalid(String)
    case requestFailed(statusCode: Int, message: String?)
    case parsingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid credentials."
        case .notAuthorized:
            return "You are not authorized to access this page."
        case .notLoggedIn:
            return "You must be logged in to access this page."
        case .pageNotFound:
            return "Page not Found"
        case .invalidCourseID:
            return "Invalid Course ID"
        case .invalidParameters(let message):
            return message
        case .noDatesProvided:
            return "At least one date must be provided"
        case .invalidDateOrder:
            return "Dates must be in order: release_date <= due_date <= late_due_date"
        case .noSubmissionFound:
            return "No submission found"
        case .unsupportedSubmissionType(let message):
            return message
        case .assignmentTitleInvalid(let title):
            return "Assignment title '\(title)' is invalid"
        case .requestFailed(let statusCode, let message):
            if let message, !message.isEmpty {
                return "Request failed with status \(statusCode): \(message)"
            }
            return "Request failed with status \(statusCode)"
        case .parsingFailed(let message):
            return "Failed to parse Gradescope response: \(message)"
        }
    }
}
