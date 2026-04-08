import Foundation

public let DEFAULT_GRADESCOPE_BASE_URL = URL(string: "https://www.gradescope.com")!

public struct CoursesByRole: Codable, Equatable, Sendable {
    public var student: [String: Course]
    public var instructor: [String: Course]

    public init(
        student: [String: Course] = [:],
        instructor: [String: Course] = [:]
    ) {
        self.student = student
        self.instructor = instructor
    }
}

public struct Course: Codable, Equatable, Sendable {
    public let name: String
    public let fullName: String
    public let semester: String
    public let year: String
    public let numGradesPublished: String?
    public let numAssignments: String?

    public init(
        name: String,
        fullName: String,
        semester: String,
        year: String,
        numGradesPublished: String? = nil,
        numAssignments: String? = nil
    ) {
        self.name = name
        self.fullName = fullName
        self.semester = semester
        self.year = year
        self.numGradesPublished = numGradesPublished
        self.numAssignments = numAssignments
    }
}

public struct Assignment: Codable, Equatable, Sendable {
    public let assignmentID: String?
    public let name: String
    public let releaseDate: Date?
    public let dueDate: Date?
    public let lateDueDate: Date?
    public let submissionsStatus: String?
    public let grade: Double?
    public let maxGrade: Double?

    public init(
        assignmentID: String?,
        name: String,
        releaseDate: Date?,
        dueDate: Date?,
        lateDueDate: Date?,
        submissionsStatus: String?,
        grade: Double?,
        maxGrade: Double?
    ) {
        self.assignmentID = assignmentID
        self.name = name
        self.releaseDate = releaseDate
        self.dueDate = dueDate
        self.lateDueDate = lateDueDate
        self.submissionsStatus = submissionsStatus
        self.grade = grade
        self.maxGrade = maxGrade
    }
}

public struct Member: Codable, Equatable, Sendable {
    public let fullName: String?
    public let firstName: String?
    public let lastName: String?
    public let sid: String?
    public let email: String?
    public let role: String?
    public let userID: String?
    public let numSubmissions: Int
    public let sections: String?
    public let courseID: String

    public init(
        fullName: String?,
        firstName: String?,
        lastName: String?,
        sid: String?,
        email: String?,
        role: String?,
        userID: String?,
        numSubmissions: Int,
        sections: String?,
        courseID: String
    ) {
        self.fullName = fullName
        self.firstName = firstName
        self.lastName = lastName
        self.sid = sid
        self.email = email
        self.role = role
        self.userID = userID
        self.numSubmissions = numSubmissions
        self.sections = sections
        self.courseID = courseID
    }
}

public struct Extension: Codable, Equatable, Sendable {
    public let name: String
    public let releaseDate: Date?
    public let dueDate: Date?
    public let lateDueDate: Date?
    public let deletePath: String

    public init(
        name: String,
        releaseDate: Date?,
        dueDate: Date?,
        lateDueDate: Date?,
        deletePath: String
    ) {
        self.name = name
        self.releaseDate = releaseDate
        self.dueDate = dueDate
        self.lateDueDate = lateDueDate
        self.deletePath = deletePath
    }
}

public struct UploadFile: Equatable, Sendable {
    public let filename: String
    public let data: Data
    public let mimeType: String

    public init(filename: String, data: Data, mimeType: String = "application/octet-stream") {
        self.filename = filename
        self.data = data
        self.mimeType = mimeType
    }

    public init(fileURL: URL, mimeType: String? = nil) throws {
        self.filename = fileURL.lastPathComponent
        self.data = try Data(contentsOf: fileURL)
        self.mimeType = mimeType ?? MIMEType.infer(from: fileURL.pathExtension)
    }
}

enum MIMEType {
    static func infer(from pathExtension: String) -> String {
        let ext = pathExtension.lowercased()
        switch ext {
        case "txt":
            return "text/plain"
        case "md":
            return "text/markdown"
        case "py":
            return "text/x-python"
        case "pdf":
            return "application/pdf"
        case "json":
            return "application/json"
        case "zip":
            return "application/zip"
        default:
            return "application/octet-stream"
        }
    }
}
