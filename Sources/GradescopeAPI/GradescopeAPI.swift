import Foundation

public func getExtensions(
    connection: GSConnection,
    courseID: String,
    assignmentID: String
) async throws -> [String: Extension] {
    try await connection.getExtensions(courseID: courseID, assignmentID: assignmentID)
}

public func updateStudentExtension(
    connection: GSConnection,
    courseID: String,
    assignmentID: String,
    userID: String,
    releaseDate: Date? = nil,
    dueDate: Date? = nil,
    lateDueDate: Date? = nil
) async throws -> Bool {
    try await connection.updateStudentExtension(
        courseID: courseID,
        assignmentID: assignmentID,
        userID: userID,
        releaseDate: releaseDate,
        dueDate: dueDate,
        lateDueDate: lateDueDate
    )
}

public func updateAssignmentDate(
    connection: GSConnection,
    courseID: String,
    assignmentID: String,
    releaseDate: Date? = nil,
    dueDate: Date? = nil,
    lateDueDate: Date? = nil,
    timeZone: TimeZone = .current
) async throws -> Bool {
    try await connection.updateAssignmentDate(
        courseID: courseID,
        assignmentID: assignmentID,
        releaseDate: releaseDate,
        dueDate: dueDate,
        lateDueDate: lateDueDate,
        timeZone: timeZone
    )
}

public func updateAssignmentTitle(
    connection: GSConnection,
    courseID: String,
    assignmentID: String,
    assignmentName: String
) async throws -> Bool {
    try await connection.updateAssignmentTitle(
        courseID: courseID,
        assignmentID: assignmentID,
        assignmentName: assignmentName
    )
}

public func updateAutograderImageName(
    connection: GSConnection,
    courseID: String,
    assignmentID: String,
    imageName: String
) async throws -> Bool {
    try await connection.updateAutograderImageName(
        courseID: courseID,
        assignmentID: assignmentID,
        imageName: imageName
    )
}

public func uploadAssignment(
    connection: GSConnection,
    courseID: String,
    assignmentID: String,
    files: [UploadFile],
    leaderboardName: String? = nil
) async throws -> URL? {
    try await connection.uploadAssignment(
        courseID: courseID,
        assignmentID: assignmentID,
        files: files,
        leaderboardName: leaderboardName
    )
}
