import Foundation

enum HTML {
    static func firstMatch(_ pattern: String, in html: String, group: Int = 1) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }
        let range = NSRange(html.startIndex..., in: html)
        guard
            let match = regex.firstMatch(in: html, options: [], range: range),
            let captureRange = Range(match.range(at: group), in: html)
        else {
            return nil
        }
        return String(html[captureRange])
    }

    static func allMatches(_ pattern: String, in html: String, group: Int = 1) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }
        let range = NSRange(html.startIndex..., in: html)
        return regex.matches(in: html, options: [], range: range).compactMap { match in
            guard let captureRange = Range(match.range(at: group), in: html) else {
                return nil
            }
            return String(html[captureRange])
        }
    }

    static func openingTag(of block: String) -> String? {
        guard let closeIndex = block.firstIndex(of: ">") else {
            return nil
        }
        return String(block[...closeIndex])
    }

    static func innerHTML(of block: String) -> String {
        guard
            let openClose = block.firstIndex(of: ">"),
            let closeStart = block.range(of: "</", options: .backwards)?.lowerBound
        else {
            return block
        }
        let start = block.index(after: openClose)
        return String(block[start..<closeStart])
    }

    static func attribute(_ name: String, in tag: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let pattern = "\\b\(escapedName)\\s*=\\s*([\"'])(.*?)\\1"
        return firstMatch(pattern, in: tag, group: 2).map(decodeEntities)
    }

    static func textContent(of html: String) -> String {
        let noScripts = html.replacingOccurrences(
            of: "(?is)<script\\b[^>]*>.*?</script>",
            with: " ",
            options: .regularExpression
        )
        let noStyles = noScripts.replacingOccurrences(
            of: "(?is)<style\\b[^>]*>.*?</style>",
            with: " ",
            options: .regularExpression
        )
        let withoutTags = noStyles.replacingOccurrences(
            of: "(?is)<[^>]+>",
            with: " ",
            options: .regularExpression
        )
        return normalizeWhitespace(decodeEntities(withoutTags))
    }

    static func decodeEntities(_ text: String) -> String {
        var decoded = text
        let entityMap: [(String, String)] = [
            ("&quot;", "\""),
            ("&#34;", "\""),
            ("&#39;", "'"),
            ("&apos;", "'"),
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&nbsp;", " "),
        ]
        for (entity, replacement) in entityMap {
            decoded = decoded.replacingOccurrences(of: entity, with: replacement)
        }

        let numericPattern = "&#(\\d+);"
        guard let regex = try? NSRegularExpression(pattern: numericPattern) else {
            return decoded
        }
        let range = NSRange(decoded.startIndex..., in: decoded)
        let matches = regex.matches(in: decoded, options: [], range: range).reversed()
        var mutable = decoded
        for match in matches {
            guard
                let wholeRange = Range(match.range(at: 0), in: mutable),
                let codeRange = Range(match.range(at: 1), in: mutable),
                let scalar = UInt32(mutable[codeRange]),
                let scalarValue = UnicodeScalar(scalar)
            else {
                continue
            }
            mutable.replaceSubrange(wholeRange, with: String(Character(scalarValue)))
        }
        return mutable
    }

    static func normalizeWhitespace(_ text: String) -> String {
        text.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func extractBlocks(
        named tag: String,
        in html: String,
        where predicate: ((String) -> Bool)? = nil
    ) -> [String] {
        let pattern = "(?is)<\(tag)\\b[^>]*>.*?</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let range = NSRange(html.startIndex..., in: html)
        return regex.matches(in: html, options: [], range: range).compactMap { match in
            guard let captureRange = Range(match.range(at: 0), in: html) else {
                return nil
            }
            let block = String(html[captureRange])
            guard let opening = openingTag(of: block) else {
                return nil
            }
            return predicate?(opening) ?? true ? block : nil
        }
    }

    static func extractBalancedBlocks(
        named tag: String,
        in html: String,
        where predicate: ((String) -> Bool)? = nil
    ) -> [String] {
        let lowercasedHTML = html.lowercased()
        let openNeedle = "<\(tag.lowercased())"
        let closeNeedle = "</\(tag.lowercased())"
        var results: [String] = []
        var searchIndex = html.startIndex

        while let openRange = lowercasedHTML.range(
            of: openNeedle,
            range: searchIndex..<lowercasedHTML.endIndex
        ) {
            guard let openTagEnd = html[openRange.lowerBound...].firstIndex(of: ">") else {
                break
            }
            let openTag = String(html[openRange.lowerBound...openTagEnd])
            guard predicate?(openTag) ?? true else {
                searchIndex = html.index(after: openRange.lowerBound)
                continue
            }

            var depth = 0
            var cursor = openRange.lowerBound
            var blockEnd: String.Index?

            while cursor < html.endIndex {
                guard let nextTagStart = lowercasedHTML[cursor...].firstIndex(of: "<") else {
                    break
                }

                if lowercasedHTML[nextTagStart...].hasPrefix(closeNeedle) {
                    depth -= 1
                    guard let tagEnd = html[nextTagStart...].firstIndex(of: ">") else {
                        break
                    }
                    let afterTag = html.index(after: tagEnd)
                    if depth == 0 {
                        blockEnd = afterTag
                        break
                    }
                    cursor = afterTag
                    continue
                }

                if lowercasedHTML[nextTagStart...].hasPrefix(openNeedle) {
                    depth += 1
                    guard let tagEnd = html[nextTagStart...].firstIndex(of: ">") else {
                        break
                    }
                    let tagText = String(html[nextTagStart...tagEnd])
                    let afterTag = html.index(after: tagEnd)
                    if tagText.hasSuffix("/>") {
                        depth -= 1
                    }
                    cursor = afterTag
                    continue
                }

                cursor = html.index(after: nextTagStart)
            }

            guard let blockEnd else {
                break
            }

            results.append(String(html[openRange.lowerBound..<blockEnd]))
            searchIndex = blockEnd
        }

        return results
    }

    static func extractDirectBalancedBlocks(
        named tag: String,
        in html: String,
        where predicate: ((String) -> Bool)? = nil
    ) -> [String] {
        let content = innerHTML(of: html)
        let lowercasedContent = content.lowercased()
        let openNeedle = "<\(tag.lowercased())"
        var results: [String] = []
        var cursor = content.startIndex

        while cursor < content.endIndex {
            let remainder = lowercasedContent[cursor...]

            guard let nextOpen = remainder.range(of: openNeedle)?.lowerBound else {
                break
            }

            if let nonWhitespace = content[cursor..<nextOpen].first(where: { !$0.isWhitespace }) {
                if nonWhitespace != "<" {
                    cursor = nextOpen
                }
            }

            guard nextOpen == cursor || content[cursor..<nextOpen].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                cursor = nextOpen
                continue
            }

            let blocks = extractBalancedBlocks(named: tag, in: String(content[nextOpen...]))
            guard let block = blocks.first, let opening = openingTag(of: block) else {
                break
            }

            if predicate?(opening) ?? true {
                results.append(block)
            }

            cursor = content.index(nextOpen, offsetBy: block.count, limitedBy: content.endIndex) ?? content.endIndex
        }

        return results
    }
}
