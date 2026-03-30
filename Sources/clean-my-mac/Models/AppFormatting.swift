import Foundation

enum AppFormatting {
    static func byteString(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    static func relativeDate(_ date: Date) -> String {
        date.formatted(.relative(presentation: .named))
    }

    static func absoluteDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
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
