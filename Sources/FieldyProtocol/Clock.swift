import Foundation

/// Current Time (`0x2A2B`) payload as the Fieldy expects it, in UTC:
/// `year u16 BIG-endian, month, day, hour, minute, second, weekday (Mon=1..Sun=7)`.
/// Unlike the Bluetooth SIG format there are no fractions or adjust-reason bytes.
public enum ClockPayload {
    public static let length = 8

    private static var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    public static func make(_ date: Date) -> Data {
        let c = utcCalendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: date)
        // Calendar weekday: Sun=1..Sat=7. Device: Mon=1..Sun=7.
        let weekday = ((c.weekday! + 5) % 7) + 1
        var b = [UInt8]()
        b.appendBE(UInt16(c.year!))
        b += [UInt8(c.month!), UInt8(c.day!), UInt8(c.hour!), UInt8(c.minute!), UInt8(c.second!), UInt8(weekday)]
        return Data(b)
    }

    /// Reads a clock value back (e.g. from a read of 0x2A2B). Returns nil when invalid.
    public static func parse(_ data: Data) -> Date? {
        let r = ByteReader(data)
        guard r.count >= 7 else { return nil }
        var c = DateComponents()
        c.year = Int(r.u16be(0))
        c.month = Int(r.u8(2))
        c.day = Int(r.u8(3))
        c.hour = Int(r.u8(4))
        c.minute = Int(r.u8(5))
        c.second = Int(r.u8(6))
        guard let y = c.year, y >= 2000, (1...12).contains(c.month!), (1...31).contains(c.day!) else { return nil }
        return utcCalendar.date(from: c)
    }
}
