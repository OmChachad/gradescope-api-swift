# GradescopeAPI Swift

Native Swift package based on the original Python `gradescopeapi` project in this repository.

## Credits

I based this Swift package on the original Python Gradescope API project at [nyuoss/gradescope-api](https://github.com/nyuoss/gradescope-api). That repository was the original source for the feature set, scraping flow, and overall package shape that this Swift port follows.

I used Codex to do much of the Swift translation and implementation work, but I also worked through the back-and-forth debugging myself and pushed toward the fix that ended up mattering most in practice: running authentication and authenticated fetching through WebKit instead of relying on `URLSession` alone.

## Install

From Xcode or SwiftPM, point the dependency at this local `swift` folder and import:

```swift
import GradescopeAPI
```

## Quick Start

On Apple platforms, `login(...)` now uses the WebKit-backed flow by default.

```swift
import Foundation
import GradescopeAPI

let connection = GSConnection()
try await connection.login("email@domain.com", "password")

if let account = connection.account {
    let courses = try await account.getCourses()
    let assignments = try await account.getAssignments("753413")
    print(courses.student)
    print(assignments)
}
```

You can also call the WebKit entry point explicitly:

```swift
try await connection.loginWithWebKit("email@domain.com", "password")
```

## Included Features

- Login and authenticated session management via `GSConnection`
- WebKit-backed authenticated fetching on Apple platforms
- Course lookup via `Account.getCourses()`
- Course roster lookup via `Account.getCourseUsers(_:)`
- Assignment lookup via `Account.getAssignments(_:)`
- Submission lookup via `Account.getAssignmentSubmissions(courseID:assignmentID:)`
- Single-student submission lookup via `Account.getAssignmentSubmission(studentEmail:courseID:assignmentID:)`
- Grader lookup via `Account.getAssignmentGraders(courseID:questionID:)`
- Assignment extension fetch/update
- Assignment date/title/autograder updates
- Assignment file upload support

## Notes

- This package mirrors the Python package's HTML-scraping approach, so it still depends on Gradescope's live markup and page behavior remaining compatible.
- The working Apple-platform implementation uses WebKit for login and authenticated page requests because Gradescope's live behavior did not consistently cooperate with a plain `URLSession` flow.
- `updateAssignmentDate` accepts a `timeZone` argument because Gradescope's edit forms expect institution-local wall-clock times.
- A local smoke-check target is included and can be run with:

```bash
swift run GradescopeAPISmokeCheck
```

- A live WebKit verification target is also included for local debugging:

```bash
GRADESCOPE_EMAIL="email@domain.com" \
GRADESCOPE_PASSWORD="password" \
swift run GradescopeAPIWebKitCheck
```
