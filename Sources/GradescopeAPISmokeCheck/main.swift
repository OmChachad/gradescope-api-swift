import Foundation
import GradescopeAPI

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("Smoke check failed: \(message)\n", stderr)
        exit(1)
    }
}

func runSmokeChecks() throws {
    let tokenHTML = """
    <html>
      <body>
        <form action="/login">
          <input type="hidden" name="authenticity_token" value="token-123">
        </form>
        <meta name="csrf-token" content="csrf-456">
      </body>
    </html>
    """
    expect(GradescopeParsers.loginAuthenticityToken(from: tokenHTML) == "token-123", "auth token parse")
    expect(GradescopeParsers.csrfToken(from: tokenHTML) == "csrf-456", "csrf parse")

    let coursesHTML = """
    <div id="account-show">
      <button class="js-createNewCourse">Create Course</button>
      <div class="courseList">
        <div class="courseList--term">
          Fall 2024
          <a href="/courses/753413">
            <h3 class="courseBox--shortname">CS 101</h3>
            <div class="courseBox--name">Intro to Testing</div>
            <div class="courseBox--assignments">5 Assignments</div>
          </a>
        </div>
      </div>
      <h2 class="pageHeading">Student Courses</h2>
      <div class="courseList">
        <div class="courseList--term">
          Spring 2025
          <a href="/courses/888999">
            <h3 class="courseBox--shortname">MATH 9</h3>
            <div class="courseBox--name">Discrete Math</div>
            <div class="courseBox--assignments">9 Assignments</div>
          </a>
        </div>
      </div>
    </div>
    """
    let courses = GradescopeParsers.courses(from: coursesHTML)
    expect(courses.instructor["753413"]?.name == "CS 101", "instructor course parse")
    expect(courses.student["888999"]?.fullName == "Discrete Math", "student course parse")

    let assignmentsProps = """
    {"table_data":[
      {"type":"section"},
      {"type":"assignment","url":"/courses/753413/assignments/4330410","title":"HW 1","submission_window":{"release_date":"2024-04-15T00:00:00Z","due_date":"2024-04-16T00:00:00Z","hard_due_date":"2024-04-17T00:00:00Z"},"total_points":100}
    ]}
    """
    let instructorAssignmentsHTML = """
    <div data-react-class="AssignmentsTable" data-react-props="\(assignmentsProps.replacingOccurrences(of: "\"", with: "&quot;"))"></div>
    """
    let instructorAssignments = GradescopeParsers.instructorAssignments(from: instructorAssignmentsHTML)
    expect(instructorAssignments.count == 1, "instructor assignment count")
    expect(instructorAssignments.first?.assignmentID == "4330410", "instructor assignment id")

    let studentAssignmentsHTML = """
    <table>
      <tr role="row"><th>Name</th><th>Status</th><th>Dates</th></tr>
      <tr role="row">
        <th>
          <a href="/courses/753413/assignments/4455030/submissions/1">Project 1</a>
        </th>
        <td>9 / 10</td>
        <td>
          <time class="submissionTimeChart--releaseDate" datetime="2024-04-15T00:00:00Z"></time>
          <time class="submissionTimeChart--dueDate" datetime="2024-04-16T00:00:00Z"></time>
          <time class="submissionTimeChart--dueDate" datetime="2024-04-17T00:00:00Z"></time>
        </td>
      </tr>
    </table>
    """
    let studentAssignments = GradescopeParsers.studentAssignments(from: studentAssignmentsHTML)
    expect(studentAssignments.first?.assignmentID == "4455030", "student assignment id")
    expect(studentAssignments.first?.grade == 9, "student assignment grade")
    expect(studentAssignments.first?.maxGrade == 10, "student assignment max grade")

    let memberJSON = """
    {"full_name":"Ada Lovelace","first_name":"Ada","last_name":"Lovelace","sid":"N123"}
    """.replacingOccurrences(of: "\"", with: "&quot;")
    let membersHTML = """
    <table class="js-rosterTable">
      <thead>
        <tr><th>Name</th><th>Email</th><th>Role</th><th>Submissions</th></tr>
      </thead>
      <tbody>
        <tr class="rosterRow">
          <td>
            <button class="rosterCell--editIcon" data-cm="\(memberJSON)" data-email="ada@example.com" data-role="0" data-sections="A"></button>
            <button class="js-rosterName" data-url="/courses/753413/gradebook.json?user_id=6515875">Ada</button>
          </td>
          <td>ada@example.com</td>
          <td>Student</td>
          <td>4</td>
        </tr>
      </tbody>
    </table>
    """
    let members = GradescopeParsers.courseMembers(from: membersHTML, courseID: "753413")
    expect(members.first?.fullName == "Ada Lovelace", "member full name")
    expect(members.first?.userID == "6515875", "member user id")

    let reviewHTML = """
    <table>
      <tr>
        <td class="table--primaryLink"><a href="/courses/753413/assignments/4330410/submissions/111">Submission</a></td>
        <td>student@example.com</td>
      </tr>
    </table>
    """
    expect(GradescopeParsers.submissionIDs(from: reviewHTML) == ["111"], "submission ids")
    expect(GradescopeParsers.submissionID(for: "student@example.com", in: reviewHTML) == "111", "submission lookup")

    let gradersHTML = """
    <table>
      <tr><td>Student A</td><td>Question 1</td><td>Grader One</td></tr>
      <tr><td>Student B</td><td>Question 1</td><td></td></tr>
      <tr><td>Student C</td><td>Question 1</td><td>Grader Two</td></tr>
    </table>
    """
    expect(GradescopeParsers.graders(from: gradersHTML) == Set(["Grader One", "Grader Two"]), "graders parse")

    let submissionJSON = """
    {"text_files":[{"file":{"url":"https://example.com/a.pdf"}},{"file":{"url":"https://example.com/b.pdf"}}]}
    """
    let files = try GradescopeParsers.submissionFiles(from: Data(submissionJSON.utf8))
    expect(files == ["https://example.com/a.pdf", "https://example.com/b.pdf"], "submission files parse")

    let extensionProps = """
    {"override":{"user_id":6515875,"settings":{"release_date":{"value":"2024-04-15T12:00:00"},"due_date":{"value":"2024-04-16T12:00:00"},"hard_due_date":{"value":"2024-04-17T12:00:00"}}},"timezone":{"identifier":"America/New_York"},"deletePath":"/delete/1","studentName":"Grace Hopper"}
    """.replacingOccurrences(of: "\"", with: "&quot;")
    let extensionsHTML = """
    <table class="table js-overridesTable">
      <tbody>
        <tr>
          <td><div data-react-class="EditExtension" data-react-props="\(extensionProps)"></div></td>
        </tr>
      </tbody>
    </table>
    """
    let extensions = try GradescopeParsers.extensions(from: extensionsHTML)
    expect(extensions["6515875"]?.name == "Grace Hopper", "extension name")
    expect(extensions["6515875"]?.deletePath == "/delete/1", "extension delete path")

    let multipart = MultipartFormData(
        parts: [
            .init(name: "utf8", filename: nil, mimeType: nil, data: Data("✓".utf8)),
            .init(name: "submission[files][]", filename: "hello.txt", mimeType: "text/plain", data: Data("hello".utf8)),
        ],
        boundary: "boundary-test"
    )
    let multipartBody = String(decoding: multipart.body, as: UTF8.self)
    expect(multipart.contentType.contains("boundary-test"), "multipart content type")
    expect(multipartBody.contains("filename=\"hello.txt\""), "multipart filename")
}

do {
    try runSmokeChecks()
    print("GradescopeAPI smoke checks passed.")
} catch {
    fputs("Smoke check failed with error: \(error)\n", stderr)
    exit(1)
}
