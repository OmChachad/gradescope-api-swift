import Foundation
import GradescopeAPI
#if canImport(AppKit)
import AppKit
#endif

extension GSConnection: @unchecked Sendable {}
extension Account: @unchecked Sendable {}

@main
struct GradescopeAPIWebKitCheck {
    static func main() async {
        let environment = ProcessInfo.processInfo.environment
        guard
            let email = environment["GRADESCOPE_EMAIL"],
            let password = environment["GRADESCOPE_PASSWORD"],
            !email.isEmpty,
            !password.isEmpty
        else {
            fputs("Missing GRADESCOPE_EMAIL or GRADESCOPE_PASSWORD\n", stderr)
            exit(2)
        }

        do {
            let connection = await MainActor.run { () -> GSConnection in
                #if canImport(AppKit)
                _ = NSApplication.shared
                #endif
                return GSConnection()
            }
            try await connection.loginWithWebKit(email, password)
            guard let account = connection.account else {
                throw GradescopeError.notLoggedIn
            }

            let courses = try await account.getCourses()
            let accountHTML = try await connection.debugFetchHTML(path: "/account")
            try accountHTML.write(to: URL(fileURLWithPath: "/tmp/gradescope-account.html"), atomically: true, encoding: .utf8)
            print("WEBKIT_LOGIN_OK")
            print("INSTRUCTOR_COUNT=\(courses.instructor.count)")
            print("STUDENT_COUNT=\(courses.student.count)")
            print("HAS_ACCOUNT_SHOW=\(accountHTML.contains("account-show"))")
            print("HAS_COURSE_LIST=\(accountHTML.contains("courseList"))")
            print("HAS_COURSE_BOX=\(accountHTML.contains("courseBox"))")
            let snippet = accountHTML
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .prefix(1200)
            print("ACCOUNT_SNIPPET=\(snippet)")

            for (id, course) in courses.instructor.sorted(by: { $0.key < $1.key }) {
                print("INSTRUCTOR_COURSE \(id) \(course.name) | \(course.fullName)")
            }
            for (id, course) in courses.student.sorted(by: { $0.key < $1.key }) {
                print("STUDENT_COURSE \(id) \(course.name) | \(course.fullName)")
            }
        } catch {
            if let localized = error as? LocalizedError, let description = localized.errorDescription {
                fputs("WEBKIT_LOGIN_ERROR=\(description)\n", stderr)
            } else {
                fputs("WEBKIT_LOGIN_ERROR=\(String(describing: error))\n", stderr)
            }
            exit(1)
        }
    }
}
