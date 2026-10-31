import CoreBluetooth
import FieldyDevice
import Foundation
import Testing

/// Hardware-free checks. Creating a `FieldyDevice` would start CoreBluetooth,
/// so these tests stay at the error-classification level.
@Suite("Device errors")
struct FieldyDeviceErrorTests {
    @Test func pairingFailuresAreRecognized() {
        #expect(FieldyDeviceError.att(code: 0x0F, operation: "read").isPairingFailure)
        #expect(FieldyDeviceError.att(code: 0x05, operation: "read").isPairingFailure)
        #expect(FieldyDeviceError.att(code: 0x0C, operation: "read").isPairingFailure)
        #expect(FieldyDeviceError.coreBluetooth(code: CBError.Code.peerRemovedPairingInformation.rawValue, message: "").isPairingFailure)
        #expect(!FieldyDeviceError.att(code: 0x02, operation: "read").isPairingFailure)
        #expect(!FieldyDeviceError.timeout("read").isPairingFailure)
        #expect(!FieldyDeviceError.notConnected.isPairingFailure)
    }

    @Test func descriptions() {
        #expect(FieldyDeviceError.att(code: 0x0F, operation: "read 66E1").description == "ATT error 0x0F during read 66E1")
        #expect(FieldyDeviceError.pairedElsewhere.description == "This Fieldy is paired with another device")
        #expect(FieldyDeviceError.readWhileNotifying("66E1").description == "cannot read 66E1 while its notifications are on")
        #expect(!FieldyDeviceError.readWhileNotifying("66E1").isPairingFailure)
    }
}
