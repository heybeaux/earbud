/// Fieldy 3 GATT identifiers (firmware 3.3.5). See fieldy-local docs/protocol.md.
/// Plain strings so this module has no CoreBluetooth dependency.
public enum FieldyGATT {
    /// Advertised local name prefix, e.g. "Fieldy1A".
    public static let namePrefix = "Fieldy"

    public static let serviceA = "4FAFC201-1FB5-459E-8FCC-C5C9C331914B"
    public static let serviceB = "4FAFC202-1FB5-459E-8FCC-C5C9C331914B"

    private static func custom(_ suffix: String) -> String { "82A48422-3CA9-4156-AE67-4170F58666\(suffix)" }

    /// Live audio (read, notify). 240-byte notifications of six 40-byte Opus frames.
    public static let liveAudio = custom("E0")
    /// Offline storage (read, write, notify). Needs a bonded, encrypted link.
    public static let storage = custom("E1")
    /// Mute: 01 muted, 00 unmuted.
    public static let mute = custom("E2")
    /// Always-on LED: 01 on, 00 off.
    public static let led = custom("E3")
    /// Button events (notify).
    public static let button = custom("E4")
    /// Unknown, service B.
    public static let unknownE5 = custom("E5")
    /// Recording manifest. Needs bonding.
    public static let manifest = custom("E6")
    /// Recording control: write 01 start, 00 stop. Notifies an 11-byte status.
    public static let recordingControl = custom("E7")
    /// Recording mode: 00 manual, 01 automatic.
    public static let recordingMode = custom("E8")
    /// Device ("profile") status: write 01, device notifies an 18-byte record.
    public static let deviceStatus = custom("E9")
    /// Sleep. EarBud never writes this.
    public static let sleep = custom("EA")
    /// Reset/recovery report (10 bytes). Write 01 to acknowledge.
    public static let resetReport = custom("EE")
    /// Haptics: 01 04 buzzes the device.
    public static let haptics = custom("EF")

    // Standard services and characteristics (16-bit, expanded by CoreBluetooth).
    public static let batteryService = "180F"
    public static let batteryLevel = "2A19"
    public static let batteryVoltage = "2B18"
    public static let currentTimeService = "1805"
    public static let currentTime = "2A2B"
    public static let deviceInformationService = "180A"
    public static let modelNumber = "2A24"
    public static let serialNumber = "2A25"
    public static let firmwareRevision = "2A26"
    public static let hardwareRevision = "2A27"
    public static let softwareRevision = "2A28"
    public static let manufacturerName = "2A29"
    public static let environmentalSensingService = "181A"
    public static let temperature = "2A6E"

    /// The firmware EarBud's protocol was mapped on.
    public static let testedFirmware = "3.3.5"
}
