import Foundation

enum GradescopeDateParser {
    static func parse(_ value: String?, fallbackTimeZoneID: String? = nil) -> Date? {
        guard let rawValue = value?.trimmingCharacters(in: .whitespacesAndNewlines), !rawValue.isEmpty else {
            return nil
        }

        let isoFormatters: [ISO8601DateFormatter] = [
            makeISOFormatter(options: [.withInternetDateTime, .withFractionalSeconds]),
            makeISOFormatter(options: [.withInternetDateTime]),
        ]
        for formatter in isoFormatters {
            if let date = formatter.date(from: rawValue) {
                return date
            }
        }

        let formats = [
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
        ]

        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            formatter.timeZone = fallbackTimeZoneID.flatMap(TimeZone.init(identifier:)) ?? .current
            if let date = formatter.date(from: rawValue) {
                return date
            }
        }

        return nil
    }

    static func assignmentFormString(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return formatter.string(from: date)
    }

    static func utcJSONString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return formatter.string(from: date)
    }

    static func makeISOFormatter(options: ISO8601DateFormatter.Options) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = options
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }
}
