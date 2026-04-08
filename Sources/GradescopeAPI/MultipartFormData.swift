import Foundation

package struct MultipartFormData {
    package struct Part {
        package let name: String
        package let filename: String?
        package let mimeType: String?
        package let data: Data

        package init(name: String, filename: String?, mimeType: String?, data: Data) {
            self.name = name
            self.filename = filename
            self.mimeType = mimeType
            self.data = data
        }
    }

    package let boundary: String
    package let parts: [Part]

    package init(parts: [Part], boundary: String = "Boundary-\(UUID().uuidString)") {
        self.boundary = boundary
        self.parts = parts
    }

    package var contentType: String {
        "multipart/form-data; boundary=\(boundary)"
    }

    package var body: Data {
        var data = Data()
        let lineBreak = "\r\n"

        for part in parts {
            data.append(Data("--\(boundary)\(lineBreak)".utf8))
            if let filename = part.filename {
                data.append(
                    Data(
                        "Content-Disposition: form-data; name=\"\(part.name)\"; filename=\"\(filename)\"\(lineBreak)"
                            .utf8
                    )
                )
                data.append(
                    Data(
                        "Content-Type: \(part.mimeType ?? "application/octet-stream")\(lineBreak)\(lineBreak)"
                            .utf8
                    )
                )
            } else {
                data.append(
                    Data(
                        "Content-Disposition: form-data; name=\"\(part.name)\"\(lineBreak)\(lineBreak)"
                            .utf8
                    )
                )
            }
            data.append(part.data)
            data.append(Data(lineBreak.utf8))
        }

        data.append(Data("--\(boundary)--\(lineBreak)".utf8))
        return data
    }
}
