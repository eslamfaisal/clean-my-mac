import Foundation

enum AppFormatting {
    private static let absoluteDateStyle = Date.FormatStyle(date: .abbreviated, time: .shortened)
    private static let relativeDateStyle = Date.RelativeFormatStyle(presentation: .named)

    static func byteString(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    static func relativeDate(_ date: Date) -> String {
        date.formatted(relativeDateStyle)
    }

    static func absoluteDate(_ date: Date) -> String {
        date.formatted(absoluteDateStyle)
    }
}

extension Int64 {
    var byteString: String {
        AppFormatting.byteString(self)
    }
}

extension Date {
    var relativeDescription: String {
        AppFormatting.relativeDate(self)
    }
}
