import Foundation

package enum GradescopeParsers {
    package static func loginAuthenticityToken(from html: String) -> String? {
        let forms = HTML.extractBlocks(named: "form", in: html) { tag in
            HTML.attribute("action", in: tag) == "/login"
        }
        for form in forms {
            if let token = HTML.firstMatch(
                "<input\\b[^>]*name\\s*=\\s*([\"'])authenticity_token\\1[^>]*value\\s*=\\s*([\"'])(.*?)\\2",
                in: form,
                group: 3
            ) {
                return HTML.decodeEntities(token)
            }
            if let token = HTML.firstMatch(
                "<input\\b[^>]*value\\s*=\\s*([\"'])(.*?)\\1[^>]*name\\s*=\\s*([\"'])authenticity_token\\3",
                in: form,
                group: 2
            ) {
                return HTML.decodeEntities(token)
            }
        }
        return nil
    }

    package static func csrfToken(from html: String) -> String? {
        if let direct = HTML.firstMatch(
            "<meta\\b[^>]*name\\s*=\\s*([\"'])csrf-token\\1[^>]*content\\s*=\\s*([\"'])(.*?)\\2",
            in: html,
            group: 3
        ) {
            return HTML.decodeEntities(direct)
        }
        if let reversed = HTML.firstMatch(
            "<meta\\b[^>]*content\\s*=\\s*([\"'])(.*?)\\1[^>]*name\\s*=\\s*([\"'])csrf-token\\3",
            in: html,
            group: 2
        ) {
            return HTML.decodeEntities(reversed)
        }
        return nil
    }

    package static func courses(from html: String) -> CoursesByRole {
        guard let accountBlock = HTML.extractBalancedBlocks(named: "div", in: html, where: {
            HTML.attribute("id", in: $0) == "account-show"
        }).first else {
            return CoursesByRole()
        }

        let isStaff = html.contains("js-createNewCourse")
        var result = CoursesByRole()
        let studentMarker = HTML.firstMatch(
            "<h2\\b[^>]*class\\s*=\\s*([\"'])[^\"']*pageHeading[^\"']*\\1[^>]*>\\s*Student Courses\\s*</h2>",
            in: accountBlock,
            group: 0
        )

        let sections: [(String, String)] = {
            if isStaff, let studentMarker {
                let splitIndex = accountBlock.range(of: studentMarker)?.lowerBound ?? accountBlock.endIndex
                return [
                    ("instructor", String(accountBlock[..<splitIndex])),
                    ("student", String(accountBlock[splitIndex...])),
                ]
            }
            return [(isStaff ? "instructor" : "student", accountBlock)]
        }()

        for (role, sectionHTML) in sections {
            let courseLists = HTML.extractBalancedBlocks(named: "div", in: sectionHTML) { tag in
                HTML.attribute("class", in: tag)?.contains("courseList") == true
            }

            for courseList in courseLists {
                let children = HTML.extractDirectBalancedBlocks(named: "div", in: courseList)
                var currentSemester = ""
                var currentYear = ""

                for child in children {
                    guard let opening = HTML.openingTag(of: child) else {
                        continue
                    }

                    let classes = HTML.attribute("class", in: opening) ?? ""
                    if classes.contains("courseList--term") {
                        let termText = HTML.textContent(of: child)
                        currentSemester = HTML.firstMatch("(Spring|Summer|Fall|Winter)", in: termText) ?? ""
                        currentYear = HTML.firstMatch("(?:Spring|Summer|Fall|Winter)\\s+(\\d{4})", in: termText) ?? ""
                        continue
                    }

                    guard classes.contains("courseList--coursesForTerm") else {
                        continue
                    }

                    let courseAnchors = HTML.extractBlocks(named: "a", in: child) { tag in
                        HTML.attribute("class", in: tag)?.contains("courseBox") == true
                    }

                    for anchor in courseAnchors {
                        guard
                            let anchorOpening = HTML.openingTag(of: anchor),
                            let href = HTML.attribute("href", in: anchorOpening),
                            href.contains("/courses/")
                        else {
                            continue
                        }

                        let courseID = href.split(separator: "/").last.map(String.init)
                        let shortName = HTML.textContent(
                            of: HTML.extractBlocks(named: "h3", in: anchor, where: {
                                HTML.attribute("class", in: $0)?.contains("courseBox--shortname") == true
                            }).first ?? ""
                        )
                        let fullName = HTML.textContent(
                            of: HTML.extractBalancedBlocks(named: "div", in: anchor, where: {
                                HTML.attribute("class", in: $0)?.contains("courseBox--name") == true
                            }).first ?? ""
                        )
                        let numAssignments = HTML.textContent(
                            of: HTML.extractBalancedBlocks(named: "div", in: anchor, where: {
                                HTML.attribute("class", in: $0)?.contains("courseBox--assignments") == true
                            }).first ?? ""
                        )

                        guard let courseID, !courseID.isEmpty, !shortName.isEmpty else {
                            continue
                        }

                        let course = Course(
                            name: shortName,
                            fullName: fullName,
                            semester: currentSemester,
                            year: currentYear,
                            numGradesPublished: nil,
                            numAssignments: numAssignments.isEmpty ? nil : numAssignments
                        )

                        if role == "student" {
                            result.student[courseID] = course
                        } else {
                            result.instructor[courseID] = course
                        }
                    }
                }
            }
        }

        return result
    }

    package static func courseMembers(from html: String, courseID: String) -> [Member] {
        let headerCells = HTML.extractBlocks(named: "th", in: html)
        let hasSections = headerCells.map(HTML.textContent).contains { $0.hasPrefix("Sections") }
        let numSubmissionsColumn = hasSections ? 4 : 3
        let roleMap = ["0": "Student", "1": "Instructor", "2": "TA", "3": "Reader"]

        return HTML.extractBlocks(named: "tr", in: html) { tag in
            HTML.attribute("class", in: tag)?.contains("rosterRow") == true
        }.map { row in
            let cells = HTML.extractBlocks(named: "td", in: row)
            let primaryCell = cells.first ?? ""

            let editButton = HTML.firstMatch(
                "(<button\\b[^>]*class\\s*=\\s*([\"'])[^\"']*rosterCell--editIcon[^\"']*\\2[^>]*>)",
                in: primaryCell,
                group: 1
            )
            let dataCM = editButton.flatMap { HTML.attribute("data-cm", in: $0) }
            let memberPayload = dataCM
                .flatMap { HTML.decodeEntities($0).data(using: .utf8) }
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }

            let rosterNameButton = HTML.firstMatch(
                "(<button\\b[^>]*class\\s*=\\s*([\"'])[^\"']*js-rosterName[^\"']*\\2[^>]*>)",
                in: primaryCell,
                group: 1
            )
            let dataURL = rosterNameButton.flatMap { HTML.attribute("data-url", in: $0) }
            let userID = dataURL.flatMap { urlString -> String? in
                guard let components = URLComponents(string: urlString) else {
                    return nil
                }
                return components.queryItems?.first(where: { $0.name == "user_id" })?.value
            }

            let email = editButton.flatMap { HTML.attribute("data-email", in: $0) }
            let roleID = editButton.flatMap { HTML.attribute("data-role", in: $0) }
            let sections = editButton.flatMap { HTML.attribute("data-sections", in: $0) }
            let numSubmissions = cells.indices.contains(numSubmissionsColumn)
                ? Int(HTML.textContent(of: cells[numSubmissionsColumn])) ?? 0
                : 0

            return Member(
                fullName: memberPayload?["full_name"] as? String,
                firstName: memberPayload?["first_name"] as? String,
                lastName: memberPayload?["last_name"] as? String,
                sid: memberPayload?["sid"] as? String,
                email: email,
                role: roleID.flatMap { roleMap[$0] },
                userID: userID,
                numSubmissions: numSubmissions,
                sections: sections,
                courseID: courseID
            )
        }
    }

    package static func assignments(from html: String) -> [Assignment] {
        let instructor = instructorAssignments(from: html)
        return instructor.isEmpty ? studentAssignments(from: html) : instructor
    }

    package static func instructorAssignments(from html: String) -> [Assignment] {
        let assignmentsTag = HTML.firstMatch(
            "(<div\\b[^>]*data-react-class\\s*=\\s*([\"'])AssignmentsTable\\2[^>]*>)",
            in: html,
            group: 1
        )
        guard
            let assignmentsTag,
            let propsValue = HTML.attribute("data-react-props", in: assignmentsTag),
            let jsonData = propsValue.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
            let tableData = json["table_data"] as? [[String: Any]]
        else {
            return []
        }

        return tableData.compactMap { assignment in
            guard (assignment["type"] as? String) == "assignment" else {
                return nil
            }

            let submissionWindow = assignment["submission_window"] as? [String: Any]
            let maxGrade: Double? = {
                if let numeric = assignment["total_points"] as? Double {
                    return numeric
                }
                if let string = assignment["total_points"] as? String {
                    return Double(string)
                }
                return nil
            }()

            return Assignment(
                assignmentID: (assignment["url"] as? String)?.split(separator: "/").last.map(String.init),
                name: assignment["title"] as? String ?? "",
                releaseDate: GradescopeDateParser.parse(submissionWindow?["release_date"] as? String),
                dueDate: GradescopeDateParser.parse(submissionWindow?["due_date"] as? String),
                lateDueDate: GradescopeDateParser.parse(submissionWindow?["hard_due_date"] as? String),
                submissionsStatus: nil,
                grade: nil,
                maxGrade: maxGrade
            )
        }
    }

    package static func studentAssignments(from html: String) -> [Assignment] {
        let rows = HTML.extractBlocks(named: "tr", in: html) { tag in
            HTML.attribute("role", in: tag) == "row"
        }

        return rows.compactMap { row in
            let rowOpening = HTML.openingTag(of: row) ?? ""
            if HTML.attribute("class", in: rowOpening)?.contains("dropzonePreview--fileNameHeader") == true {
                return nil
            }

            let cells = HTML.extractBlocks(named: "th", in: row) + HTML.extractBlocks(named: "td", in: row)
            guard !cells.isEmpty else {
                return nil
            }

            let nameCell = cells[0]
            let name = HTML.textContent(of: nameCell)
            if name.isEmpty {
                return nil
            }

            let anchorTag = HTML.firstMatch("(<a\\b[^>]*href\\s*=\\s*([\"'])(.*?)\\2[^>]*>)", in: nameCell, group: 1)
            let buttonTag = HTML.firstMatch(
                "(<button\\b[^>]*class\\s*=\\s*([\"'])[^\"']*js-submitAssignment[^\"']*\\2[^>]*>)",
                in: nameCell,
                group: 1
            )

            let assignmentID: String? = {
                if let anchorTag, let href = HTML.attribute("href", in: anchorTag) {
                    let segments = href.split(separator: "/")
                    if let assignmentsIndex = segments.firstIndex(of: "assignments"),
                       segments.indices.contains(assignmentsIndex + 1) {
                        return String(segments[assignmentsIndex + 1])
                    }
                    return segments.last.map(String.init)
                }
                if let buttonTag {
                    return HTML.attribute("data-assignment-id", in: buttonTag)
                }
                return nil
            }()

            if assignmentID == nil && name.lowercased() == "name" {
                return nil
            }

            let statusCell = cells.indices.contains(1) ? cells[1] : ""
            let statusText = HTML.textContent(of: statusCell)
            let gradePair = statusText.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
            let (grade, maxGrade, submissionsStatus): (Double?, Double?, String?) = {
                guard gradePair.count == 2,
                      let gradeValue = Double(gradePair[0]),
                      let maxGradeValue = Double(gradePair[1])
                else {
                    return (nil, nil, statusText.isEmpty ? nil : statusText)
                }
                return (gradeValue, maxGradeValue, "Submitted")
            }()

            let datesCell = cells.indices.contains(2) ? cells[2] : ""
            let releaseDate = HTML.firstMatch(
                "submissionTimeChart--releaseDate[^>]*datetime\\s*=\\s*([\"'])(.*?)\\1",
                in: datesCell,
                group: 2
            ) ?? HTML.firstMatch(
                "datetime\\s*=\\s*([\"'])(.*?)\\1[^>]*submissionTimeChart--releaseDate",
                in: datesCell,
                group: 2
            )

            let dueDates = HTML.allMatches(
                "submissionTimeChart--dueDate[^>]*datetime\\s*=\\s*([\"'])(.*?)\\1",
                in: datesCell,
                group: 2
            ) + HTML.allMatches(
                "datetime\\s*=\\s*([\"'])(.*?)\\1[^>]*submissionTimeChart--dueDate",
                in: datesCell,
                group: 2
            )

            return Assignment(
                assignmentID: assignmentID,
                name: name,
                releaseDate: GradescopeDateParser.parse(releaseDate),
                dueDate: GradescopeDateParser.parse(dueDates.first),
                lateDueDate: GradescopeDateParser.parse(dueDates.dropFirst().first),
                submissionsStatus: submissionsStatus,
                grade: grade,
                maxGrade: maxGrade
            )
        }
    }

    package static func submissionIDs(from html: String) -> [String] {
        HTML.allMatches(
            "<td\\b[^>]*class\\s*=\\s*([\"'])[^\"']*table--primaryLink[^\"']*\\1[^>]*>.*?<a\\b[^>]*href\\s*=\\s*([\"'])(.*?)\\2",
            in: html,
            group: 3
        ).compactMap { href in
            href.split(separator: "/").last.map(String.init)
        }
    }

    package static func submissionID(for studentEmail: String, in html: String) -> String? {
        let rows = HTML.extractBlocks(named: "tr", in: html)
        for row in rows {
            let cells = HTML.extractBlocks(named: "td", in: row)
            guard cells.contains(where: { HTML.textContent(of: $0).contains(studentEmail) }) else {
                continue
            }
            guard let firstCell = cells.first else {
                continue
            }
            let href = HTML.firstMatch("<a\\b[^>]*href\\s*=\\s*([\"'])(.*?)\\1", in: firstCell, group: 2)
            if let href {
                return href.split(separator: "/").last.map(String.init)
            }
            return nil
        }
        return nil
    }

    package static func submissionFiles(from data: Data) throws -> [String] {
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw GradescopeError.parsingFailed("submission files JSON")
        }

        guard let textFiles = json["text_files"] as? [[String: Any]], !textFiles.isEmpty else {
            throw GradescopeError.unsupportedSubmissionType("Image only submissions not yet supported")
        }

        return textFiles.compactMap { item in
            ((item["file"] as? [String: Any])?["url"] as? String)
        }
    }

    package static func graders(from html: String) -> Set<String> {
        let values = HTML.extractBlocks(named: "td", in: html).map(HTML.textContent)
        var graders: Set<String> = []
        for index in stride(from: 2, to: values.count, by: 3) {
            let value = values[index]
            if !value.isEmpty {
                graders.insert(value)
            }
        }
        return graders
    }

    package static func extensions(from html: String) throws -> [String: Extension] {
        let table = HTML.extractBalancedBlocks(named: "table", in: html) { tag in
            HTML.attribute("class", in: tag)?.contains("js-overridesTable") == true
        }.first ?? html
        let rows = HTML.extractBlocks(named: "tr", in: table)
        var result: [String: Extension] = [:]

        for row in rows {
            guard
                let tag = HTML.firstMatch(
                    "(<div\\b[^>]*data-react-class\\s*=\\s*([\"'])EditExtension\\2[^>]*>)",
                    in: row,
                    group: 1
                ),
                let propsValue = HTML.attribute("data-react-props", in: tag),
                let jsonData = propsValue.data(using: .utf8),
                let payload = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                let override = payload["override"] as? [String: Any],
                let settings = override["settings"] as? [String: Any],
                let userID = override["user_id"] as? Int ?? Int((override["user_id"] as? String) ?? "")
            else {
                continue
            }

            let timezone = ((payload["timezone"] as? [String: Any])?["identifier"] as? String)
            let release = ((settings["release_date"] as? [String: Any])?["value"] as? String)
            let due = ((settings["due_date"] as? [String: Any])?["value"] as? String)
            let late = ((settings["hard_due_date"] as? [String: Any])?["value"] as? String)
            let deletePath = payload["deletePath"] as? String ?? ""
            let name = payload["studentName"] as? String ?? ""

            result[String(userID)] = Extension(
                name: name,
                releaseDate: GradescopeDateParser.parse(release, fallbackTimeZoneID: timezone),
                dueDate: GradescopeDateParser.parse(due, fallbackTimeZoneID: timezone),
                lateDueDate: GradescopeDateParser.parse(late, fallbackTimeZoneID: timezone),
                deletePath: deletePath
            )
        }

        return result
    }
}
