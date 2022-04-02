import XCTest
@testable import MGDecimal

let verbose = true  // set to false to skip test-by-test passes

final class MGDecimalTests: XCTestCase {
    
    struct TestCase {
        let id:String
        let roundMode:Rounding
        let istr, istr2:String
        let res:UInt64
        let reshi:UInt64
        let reslo:UInt64
        let status:Status
        
        static func toStatus(_ int:Int) -> Status {
            var status:Status=[]
            var int = int
            while int != 0 {
                if int >= 0x20 { status.insert(.inexact);          int-=0x20 }
                if int >= 0x10 { status.insert(.underflow);        int-=0x10 }
                if int >= 0x08 { status.insert(.overflow);         int-=0x08 }
                if int >= 0x04 { status.insert(.divisionByZero);   int-=0x04 }
                if int >= 0x02 { status.insert(.subnormal);        int-=0x02 }
                if int >= 0x01 { status.insert(.invalidOperation); int-=0x01 }
            }
            return status
        }
        
        static func toRounding(_ int:Int) -> Rounding {
            var round:Rounding
            switch int {
                case 0: round = .toNearestOrEven
                case 1: round = .down
                case 2: round = .up
                case 3: round = .towardZero
                case 4: round = .toNearestOrAwayFromZero
                default: round = .awayFromZero
            }
            return round
        }
        
        init(_ id: String, _ roundMode:Int, _ istr:String, _ res:UInt64, _ status:Int) {
            self.id = id; self.res = res
            self.istr = istr
            self.status = TestCase.toStatus(status)
            self.roundMode = TestCase.toRounding(roundMode)
            self.istr2 = ""
            self.reshi = 0; self.reslo = 0
        }
        
        init(_ id: String, _ roundMode:Int, _ istr:String, _ res128:String, _ status:Int) {
            self.id = id
            let r128 = UInt128(stringLiteral: res128)
            self.reshi = r128.hi
            self.reslo = r128.lo
            self.res = 0
            self.istr = istr
            self.status = TestCase.toStatus(status)
            self.roundMode = TestCase.toRounding(roundMode)
            self.istr2 = ""
        }
        
        init(_ id: String, _ roundMode:Int, _ istr1:String, _ istr2:String, _ res:UInt64, _ status:Int) {
            self.id = id
            self.res = res
            self.istr = istr1
            self.istr2 = istr2
            self.status = TestCase.toStatus(status)
            self.roundMode = TestCase.toRounding(roundMode)
            self.reshi = 0; self.reslo = 0
        }
    }
    
    func testDecimal32() throws {
        let testCases = [
            TestCase("bid32_from_string", 2, "-9.9999995", 0xebf8967f, 0x20), // 1
            TestCase("bid32_from_string", 1, "-9.9999995", 0xb00f4240, 0x20),
            TestCase("bid32_from_string", 0, "9.9999995", 0x300f4240, 0x20),
            TestCase("bid32_from_string", 2, "9.9999995", 0x300f4240, 0x20),
            TestCase("bid32_from_string", 4, "9.9999995", 0x300f4240, 0x20),  // 5
            TestCase("bid32_from_string", 3, "9.9999995", 0x6bf8967f, 0x20),
            TestCase("bid32_from_string", 1, "9.9999995", 0x6bf8967f, 0x20),
            TestCase("bid32_from_string", 0, ".0", 0x32000000, 0x00),
            TestCase("bid32_from_string", 0, "000.0", 0x32000000, 0x00),
            TestCase("bid32_from_string", 0, "0.0000000000000000000000000000000000001001", 0x1e8003e9, 0x00), // 10
            TestCase("bid32_from_string", 1, "0.0000000000000000000000000000000000001001", 0x1e8003e9, 0x00),
            TestCase("bid32_from_string", 0, "0.", 0x32800000, 0x00),
            TestCase("bid32_from_string", 0, "1.", 0x32800001, 0x00),
            TestCase("bid32_from_string", 0, "a", 0x7c000000, 0x00),
            TestCase("bid32_from_string", 0, "..", 0x7c000000, 0x00),   // 15
            TestCase("bid32_from_string", 0, "1..", 0x7c000000, 0x00),
            TestCase("bid32_from_string", 0, "0.0.", 0x7c000000, 0x00),
            TestCase("bid32_from_string", 0, "1.0000005", 0x2f8f4240, 0x20),
            TestCase("bid32_from_string", 2, "1.0000005", 0x2f8f4241, 0x20),
            TestCase("bid32_from_string", 4, "1.0000005", 0x2f8f4241, 0x20),  // 20
            TestCase("bid32_from_string", 3, "1.0000005", 0x2f8f4240, 0x20),
            TestCase("bid32_from_string", 1, "1.0000005", 0x2f8f4240, 0x20),
            TestCase("bid32_from_string", 0, "1.00000051", 0x2f8f4241, 0x20),
            TestCase("bid32_from_string", 2, "1.00000051", 0x2f8f4241, 0x20),
            TestCase("bid32_from_string", 4, "1.00000051", 0x2f8f4241, 0x20), // 25
            TestCase("bid32_from_string", 3, "1.00000051", 0x2f8f4240, 0x20),
            TestCase("bid32_from_string", 1, "1.00000051", 0x2f8f4240, 0x20),
            TestCase("bid32_from_string", 0, "1.0000004999999999999999", 0x2f8f4240, 0x20),
            TestCase("bid32_from_string", 2, "1.0000004999999999999999", 0x2f8f4241, 0x20),
            TestCase("bid32_from_string", 1, "1.0000004999999999999999", 0x2f8f4240, 0x20), // 30
            TestCase("bid32_from_string", 4, "1.0000004999999999999999", 0x2f8f4240, 0x20),
            TestCase("bid32_from_string", 3, "1.0000004999999999999999", 0x2f8f4240, 0x20),
            TestCase("bid32_from_string", 0, "1.1E2", 0x3300000b, 0x00),
            TestCase("bid32_from_string", 0, "1.1P2", 0x7c000000, 0x00),
            TestCase("bid32_from_string", 0, "1.1EE", 0x7c000000, 0x00),   // 35
            TestCase("bid32_from_string", 0, "1.1P-2", 0x7c000000, 0x00),
            TestCase("bid32_from_string", 0, "1.1E-2E", 0x7c000000, 0x00),
            TestCase("bid32_from_string", 0, "1.0000015", 0x2f8f4242, 0x20),
            TestCase("bid32_from_string", 2, "1.0000015", 0x2f8f4242, 0x20),
            TestCase("bid32_from_string", 4, "1.0000015", 0x2f8f4242, 0x20), // 40
            TestCase("bid32_from_string", 3, "1.0000015", 0x2f8f4241, 0x20),
            TestCase("bid32_from_string", 1, "1.0000015", 0x2f8f4241, 0x20),
            
            TestCase("bid32_abs", 0, "0x00000001", 0x00000001, 0x00),  // 1
            TestCase("bid32_abs", 0, "0x00080001", 0x00080001, 0x00),
            TestCase("bid32_abs", 0, "-1.0", 0x3200000a, 0x00),
            TestCase("bid32_abs", 0, "1.0", 0x3200000a, 0x00),
            TestCase("bid32_abs", 0, "-1.0e-96", 0x0200000a, 0x00),   // 5
            TestCase("bid32_abs", 0, "1.0e-96", 0x0200000a, 0x00),
            TestCase("bid32_abs", 0, "0x6098967f", 0x6098967f, 0x00),
            TestCase("bid32_abs", 0, "0x60989680", 0x60989680, 0x00),
            TestCase("bid32_abs", 0, "0x7c000000", 0x7c000000, 0x00),
            TestCase("bid32_abs", 0, "0x7c8f423f", 0x7c8f423f, 0x00), // 10
            TestCase("bid32_abs", 0, "0x7c8f4240", 0x7c8f4240, 0x00),
            TestCase("bid32_abs", 0, "0x7e100000", 0x7e100000, 0x00),
            TestCase("bid32_abs", 0, "0x7e100100", 0x7e100100, 0x00),
            TestCase("bid32_abs", 0, "0x7e8f423f", 0x7e8f423f, 0x00),
            TestCase("bid32_abs", 0, "0x7e8f4240", 0x7e8f4240, 0x00), // 15
            TestCase("bid32_abs", 0, "0x80000001", 0x00000001, 0x00),
            TestCase("bid32_abs", 0, "-9.999999e-95", 0x6018967f, 0x00),
            TestCase("bid32_abs", 0, "9.999999e-95", 0x6018967f, 0x00),
            TestCase("bid32_abs", 0, "-9.999999e96", 0x77f8967f, 0x00),
            TestCase("bid32_abs", 0, "9.999999e96", 0x77f8967f, 0x00), // 20
            TestCase("bid32_abs", 0, "0xfc100000", 0x7c100000, 0x00),
            TestCase("bid32_abs", 0, "0xfc100100", 0x7c100100, 0x00),
            TestCase("bid32_abs", 0, "0xfe000000", 0x7e000000, 0x00),
            
            TestCase("bid32_add", 0, "0x00000001", "1.0", 0x2f8f4240, 0x20),        // 1
            TestCase("bid32_add", 0, "0x00080001", "1.0", 0x2f8f4240, 0x20),
            TestCase("bid32_add", 0, "1.0", "0x00000001", 0x2f8f4240, 0x20),
            TestCase("bid32_add", 0, "1.0", "0x00080001", 0x2f8f4240, 0x20),
            TestCase("bid32_add", 0, "-1.0", "1.0", 0x32000000, 0x00),              // 5
            TestCase("bid32_add", 0, "1.0", "-1.0", 0x32000000, 0x00),
            TestCase("bid32_add", 0, "1.0", "1.0",  0x32000014, 0x00),
            TestCase("bid32_add", 0, "1.0", "-1.0e-96", 0x2f8f4240, 0x20),
            TestCase("bid32_add", 0, "1.0", "1.0e-96", 0x2f8f4240, 0x20),
            TestCase("bid32_add", 0, "1.0", "0x6098967f", 0x2f8f4240, 0x20),        // 10
            TestCase("bid32_add", 0, "1.0", "0x60989680", 0x2f8f4240, 0x00),
            TestCase("bid32_add", 0, "1.0", "0x7c000000", 0x7c000000, 0x00),
            TestCase("bid32_add", 0, "1.0", "0x7c8f423f", 0x7c0f423f, 0x00),
            TestCase("bid32_add", 0, "1.0", "0x7c8f4240", 0x7c000000, 0x00),
            TestCase("bid32_add", 0, "1.0", "0x7e100000", 0x7c000000, 0x01),        // 15
            TestCase("bid32_add", 0, "1.0", "0x7e100100", 0x7c000100, 0x01),
            TestCase("bid32_add", 0, "1.0", "0x7e8f423f", 0x7c0f423f, 0x01),
            TestCase("bid32_add", 0, "1.0", "0x7e8f4240", 0x7c000000, 0x01),
            TestCase("bid32_add", 0, "1.0", "0x80000001", 0x2f8f4240, 0x20),
            TestCase("bid32_add", 0, "1.0", "-9.999999e-95", 0x2f8f4240, 0x20),     // 20
            TestCase("bid32_add", 0, "1.0","9.999999e-95", 0x2f8f4240, 0x20),
            TestCase("bid32_add", 0, "1.0","9.999999e96", 0x77f8967f, 0x20),
            TestCase("bid32_add", 0, "1.0", "-9.999999e96", 0xf7f8967f, 0x20),
            TestCase("bid32_add", 0, "-1.0e-96", "1.0", 0x2f8f4240, 0x20),
            TestCase("bid32_add", 0, "1.0e-96", "1.0", 0x2f8f4240, 0x20),           // 25
            TestCase("bid32_add", 0, "1.0", "0xfc100000", 0xfc000000, 0x00),
            TestCase("bid32_add", 0, "1.0", "0xfc100100", 0xfc000100, 0x00),
            TestCase("bid32_add", 0, "1.0", "0xfe000000", 0xfc000000, 0x01),
            TestCase("bid32_add", 0, "0x6098967f", "1.0", 0x2f8f4240, 0x20),
            TestCase("bid32_add", 0, "0x60989680", "1.0", 0x2f8f4240, 0x00),        // 30
            TestCase("bid32_add", 0, "0x7c000000", "1.0", 0x7c000000, 0x00),
            TestCase("bid32_add", 0, "0x7c8f423f", "1.0", 0x7c0f423f, 0x00),
            TestCase("bid32_add", 0, "0x7c8f423f", "0x7e100000", 0x7c0f423f, 0x01),
            TestCase("bid32_add", 0, "0x7c8f423f", "Infinity", 0x7c0f423f, 0x00),
            TestCase("bid32_add", 0, "0x7c8f4240", "1.0", 0x7c000000, 0x00),        // 35
            TestCase("bid32_add", 0, "0x7e100000", "1.0", 0x7c000000, 0x01),
            TestCase("bid32_add", 0, "0x7e100100", "1.0", 0x7c000100, 0x01),
            TestCase("bid32_add", 0, "0x7e8f423f", "1.0", 0x7c0f423f, 0x01),
            TestCase("bid32_add", 0, "0x7e8f4240", "1.0", 0x7c000000, 0x01),
            TestCase("bid32_add", 0, "0x80000001", "1.0", 0x2f8f4240, 0x20),        // 40
            TestCase("bid32_add", 0, "-9.999999e-95", "1.0", 0x2f8f4240, 0x20),
            TestCase("bid32_add", 0, "9.999999e-95", "1.0", 0x2f8f4240, 0x20),
            TestCase("bid32_add", 0, "9.999999e96", "1.0", 0x77f8967f, 0x20),
            TestCase("bid32_add", 0, "-9.999999e96", "1.0", 0xf7f8967f, 0x20),
            TestCase("bid32_add", 0, "0xfc100000", "1.0", 0xfc000000, 0x00),        // 45
            TestCase("bid32_add", 0, "0xfc100100", "1.0", 0xfc000100, 0x00),
            TestCase("bid32_add", 0, "0xfe000000", "1.0", 0xfc000000, 0x01),
            TestCase("bid32_add", 0, "Infinity", "NaN", 0x7c000000, 0x00),
            
            TestCase("bid32_div", 0, "0x00000001", "1.0", 0x00000001, 0x00),          // 1
            TestCase("bid32_div", 0, "0x00080001", "1.0", 0x00080001, 0x00),
            TestCase("bid32_div", 0, "0x04240011", "0xf8000000", 0x80000000, 0x00),
            TestCase("bid32_div", 0, "0E-101", "1E+89", 0x00000000, 0x00),
            TestCase("bid32_div", 0, "0E+89", "0E+89", 0x7c000000, 0x01),             // 5
            TestCase("bid32_div", 0, "0E+89", "1E-96", 0x5f800000, 0x00),
            TestCase("bid32_div", 0, "0E+89", "9.999999E+96", 0x32000000, 0x00),
            TestCase("bid32_div", 0, "0x0f4a7e34", "0xdf2fffff", 0x80000000, 0x30),
            TestCase("bid32_div", 0, "1.0", "0x00000001", 0x78000000, 0x28),
            TestCase("bid32_div", 0, "1.0", "0x00080001", 0x5f1d1a91, 0x20),          // 10
            TestCase("bid32_div", 0, "1.0", "1.0", 0x32800001, 0x00),
            TestCase("bid32_div", 0, "-1.0", "1.0", 0xb2800001, 0x00),
            TestCase("bid32_div", 0, "1.0", "-1.0", 0xb2800001, 0x00),
            TestCase("bid32_div", 0, "1.0", "1.0e-96", 0x5f8f4240, 0x00),
            TestCase("bid32_div", 0, "1.0", "-1.0e-96", 0xdf8f4240, 0x00),            // 15
            TestCase("bid32_div", 0, "1.0", "0x6098967f", 0x5c8f4240, 0x20),
            TestCase("bid32_div", 0, "1.0", "0x60989680", 0x78000000, 04),
            TestCase("bid32_div", 0, "1.0", "0x7c000000", 0x7c000000, 0x00),
            TestCase("bid32_div", 0, "1.0", "0x7c8f423f", 0x7c0f423f, 0x00),
            TestCase("bid32_div", 0, "1.0", "0x7c8f4240", 0x7c000000, 0x00),          // 20
            TestCase("bid32_div", 0, "1.0", "0x7e100000", 0x7c000000, 0x01),
            TestCase("bid32_div", 0, "1.0", "0x7e100100", 0x7c000100, 0x01),
            TestCase("bid32_div", 0, "1.0", "0x7e8f423f", 0x7c0f423f, 0x01),
            TestCase("bid32_div", 0, "1.0", "0x7e8f4240", 0x7c000000, 0x01),
            TestCase("bid32_div", 0, "1.0", "0x80000001", 0xf8000000, 0x28),          // 25
            TestCase("bid32_div", 0, "1.0", "9.999999e-95", 0x5e8f4240, 0x20),
            TestCase("bid32_div", 0, "1.0", "-9.999999e-95", 0xde8f4240, 0x20),
            TestCase("bid32_div", 0, "1.0", "9.999999e96", 0x00002710, 0x30),
            TestCase("bid32_div", 0, "1.0", "-9.999999e96", 0x80002710, 0x30),
            TestCase("bid32_div", 0, "1.0e-96", "1.0", 0x02800001, 0x00),             // 30
            TestCase("bid32_div", 0, "-1.0e-96", "1.0", 0x82800001, 0x00),
            TestCase("bid32_div", 0, "1.0", "0xfc100000", 0xfc000000, 0x00),
            TestCase("bid32_div", 0, "1.0", "0xfc100100", 0xfc000100, 0x00),
            TestCase("bid32_div", 0, "1.0", "0xfe000000", 0xfc000000, 0x01),
            TestCase("bid32_div", 0, "0x15000000", "0x4d8583fd", 0x00000000, 0x00),   // 35
            TestCase("bid32_div", 0, "1E+89", "0.5", 0x5f000002, 0x00),
            TestCase("bid32_div", 0, "1E+89",  "1.000000E+96", 0x2f000001, 0x00),     // fail
            TestCase("bid32_div", 0, "0x23000000", "0x6896ff7f", 0x33800000, 0x00),
            TestCase("bid32_div", 0, "0x6098967f", "1.0", 0x6098967f, 0x00),
            TestCase("bid32_div", 0, "0x60989680", "1.0", 0x02800000, 0x00),          // 40
            TestCase("bid32_div", 0, "0x78000000", "0xf3d4b76a", 0xf8000000, 0x00),
            TestCase("bid32_div", 0, "0x7c000000", "1.0", 0x7c000000, 0x00),
            TestCase("bid32_div", 0, "0x7c8f423f", "1.0", 0x7c0f423f, 0x00),
            TestCase("bid32_div", 0, "0x7c8f423f", "0x7e100000", 0x7c0f423f, 0x01),
            TestCase("bid32_div", 0, "0x7c8f423f", "Infinity", 0x7c0f423f, 0x00),     // 45
            TestCase("bid32_div", 0, "0x7c8f4240", "1.0", 0x7c000000, 0x00),
            TestCase("bid32_div", 0, "0x7e100000", "1.0", 0x7c000000, 0x01),
            TestCase("bid32_div", 0, "0x7e100100", "1.0", 0x7c000100, 0x01),
            TestCase("bid32_div", 0, "0x7e8f423f", "1.0", 0x7c0f423f, 0x01),
            TestCase("bid32_div", 0, "0x7e8f4240", "1.0", 0x7c000000, 0x01),          // 50
            TestCase("bid32_div", 0, "0x80000001", "1.0", 0x80000001, 0x00),
            TestCase("bid32_div", 0, "9.999999e-95", "1.0", 0x6018967f, 0x00),
            TestCase("bid32_div", 0, "-9.999999e-95", "1.0", 0xe018967f, 0x00),
            TestCase("bid32_div", 0, "9.999999e96", "1.0", 0x77f8967f, 0x00),
            TestCase("bid32_div", 0, "-9.999999e96", "1.0", 0xf7f8967f, 0x00),        // 55
            TestCase("bid32_div", 0, "0xc3088000", "0x00020000", 0xf8000000, 0x28),
            TestCase("bid32_div", 0, "0xce000000", "0x049e2480", 0xdf800000, 0x00),
            TestCase("bid32_div", 0, "0xd5800000", "0xc2000000", 0x7c000000, 0x01),
            TestCase("bid32_div", 0, "0xf8000000", "0x78000000", 0x7c000000, 0x01),
            TestCase("bid32_div", 0, "0xfc100000", "1.0", 0xfc000000, 0x00),          // 60
            TestCase("bid32_div", 0, "0xfc100100", "1.0", 0xfc000100, 0x00),
            TestCase("bid32_div", 0, "0xfe000000", "1.0", 0xfc000000, 0x01),
            TestCase("bid32_div", 0, "Infinity", "Infinity", 0x7c000000, 0x01),
            TestCase("bid32_div", 0, "Infinity", "NaN", 0x7c000000, 0x00),
            TestCase("bid32_div", 1, "0x803c6719", "0xa77f173f", 0x08488551, 0x20),   // 65
            TestCase("bid32_div", 2, "0x803c6719", "0xa77f173f", 0x08488552, 0x20),
            TestCase("bid32_div", 2, "0xc27912d4", "0x6c2e0ad6", 0xf0220ff5, 0x20),
            
            TestCase("bid32_isCanonical", 0, "0x00000001", 1, 0x00),
            TestCase("bid32_isCanonical", 0, "0x00080001", 1, 0x00),
            TestCase("bid32_isCanonical", 0, "-1.0", 1, 0x00),
            TestCase("bid32_isCanonical", 0, "1.0", 1, 0x00),
            TestCase("bid32_isCanonical", 0, "-1.0e-96", 1, 0x00),
            TestCase("bid32_isCanonical", 0, "1.0e-96", 1, 0x00),
            TestCase("bid32_isCanonical", 0, "0x6098967f", 1, 0x00),
            TestCase("bid32_isCanonical", 0, "0x60989680", 0, 0x00),
            TestCase("bid32_isCanonical", 0, "0x7c000000", 1, 0x00),
            TestCase("bid32_isCanonical", 0, "0x7c8f423f", 0, 0x00),
            TestCase("bid32_isCanonical", 0, "0x7c8f4240", 0, 0x00),
            TestCase("bid32_isCanonical", 0, "0x7e100000", 0, 0x00),
            TestCase("bid32_isCanonical", 0, "0x7e100100", 0, 0x00),
            TestCase("bid32_isCanonical", 0, "0x7e8f423f", 0, 0x00),
            TestCase("bid32_isCanonical", 0, "0x7e8f4240", 0, 0x00),
            TestCase("bid32_isCanonical", 0, "0x80000001", 1, 0x00),
            TestCase("bid32_isCanonical", 0, "-9.999999e-95", 1, 0x00),
            TestCase("bid32_isCanonical", 0, "9.999999e-95", 1, 0x00),
            TestCase("bid32_isCanonical", 0, "-9.999999e96", 1, 0x00),
            TestCase("bid32_isCanonical", 0, "9.999999e96", 1, 0x00),
            TestCase("bid32_isCanonical", 0, "0xf8000000", 1, 0x00),
            TestCase("bid32_isCanonical", 0, "0xf8001000", 0, 0x00),
            TestCase("bid32_isCanonical", 0, "0xf8400000", 0, 0x00),
            TestCase("bid32_isCanonical", 0, "0xfc100000", 0, 0x00),
            TestCase("bid32_isCanonical", 0, "0xfc100100", 0, 0x00),
            TestCase("bid32_isCanonical", 0, "0xfe000000", 1, 0x00),
                     
            TestCase("bid32_isFinite", 0, "0x00000001", 1, 0x00),
            TestCase("bid32_isFinite", 0, "0x00080001", 1, 0x00),
            TestCase("bid32_isFinite", 0, "-1.0", 1, 0x00),
            TestCase("bid32_isFinite", 0, "1.0", 1, 0x00),
            TestCase("bid32_isFinite", 0, "-1.0e-96", 1, 0x00),
            TestCase("bid32_isFinite", 0, "1.0e-96", 1, 0x00),
            TestCase("bid32_isFinite", 0, "0x6098967f", 1, 0x00),
            TestCase("bid32_isFinite", 0, "0x60989680", 1, 0x00),
            TestCase("bid32_isFinite", 0, "0x7c000000", 0, 0x00),
            TestCase("bid32_isFinite", 0, "0x7c8f423f", 0, 0x00),
            TestCase("bid32_isFinite", 0, "0x7c8f4240", 0, 0x00),
            TestCase("bid32_isFinite", 0, "0x7e100000", 0, 0x00),
            TestCase("bid32_isFinite", 0, "0x7e100100", 0, 0x00),
            TestCase("bid32_isFinite", 0, "0x7e8f423f", 0, 0x00),
            TestCase("bid32_isFinite", 0, "0x7e8f4240", 0, 0x00),
            TestCase("bid32_isFinite", 0, "0x80000001", 1, 0x00),
            TestCase("bid32_isFinite", 0, "-9.999999e-95", 1, 0x00),
            TestCase("bid32_isFinite", 0, "9.999999e-95", 1, 0x00),
            TestCase("bid32_isFinite", 0, "-9.999999e96", 1, 0x00),
            TestCase("bid32_isFinite", 0, "9.999999e96", 1, 0x00),
            TestCase("bid32_isFinite", 0, "0xfc100000", 0, 0x00),
            TestCase("bid32_isFinite", 0, "0xfc100100", 0, 0x00),
            TestCase("bid32_isFinite", 0, "0xfe000000", 0, 0x00),
                     
            TestCase("bid32_isInf", 0, "0x00000001", 0, 0x00),
            TestCase("bid32_isInf", 0, "0x00080001", 0, 0x00),
            TestCase("bid32_isInf", 0, "-1.0", 0, 0x00),
            TestCase("bid32_isInf", 0, "1.0", 0, 0x00),
            TestCase("bid32_isInf", 0, "-1.0e-96", 0, 0x00),
            TestCase("bid32_isInf", 0, "1.0e-96", 0, 0x00),
            TestCase("bid32_isInf", 0, "0x6098967f", 0, 0x00),
            TestCase("bid32_isInf", 0, "0x60989680", 0, 0x00),
            TestCase("bid32_isInf", 0, "0x7c000000", 0, 0x00),
            TestCase("bid32_isInf", 0, "0x7c8f423f", 0, 0x00),
            TestCase("bid32_isInf", 0, "0x7c8f4240", 0, 0x00),
            TestCase("bid32_isInf", 0, "0x7e100000", 0, 0x00),
            TestCase("bid32_isInf", 0, "0x7e100100", 0, 0x00),
            TestCase("bid32_isInf", 0, "0x7e8f423f", 0, 0x00),
            TestCase("bid32_isInf", 0, "0x7e8f4240", 0, 0x00),
            TestCase("bid32_isInf", 0, "0x80000001", 0, 0x00),
            TestCase("bid32_isInf", 0, "-9.999999e-95", 0, 0x00),
            TestCase("bid32_isInf", 0, "9.999999e-95", 0, 0x00),
            TestCase("bid32_isInf", 0, "-9.999999e96", 0, 0x00),
            TestCase("bid32_isInf", 0, "9.999999e96", 0, 0x00),
            TestCase("bid32_isInf", 0, "0xfc100000", 0, 0x00),
            TestCase("bid32_isInf", 0, "0xfc100100", 0, 0x00),
            TestCase("bid32_isInf", 0, "0xfe000000", 0, 0x00),
                     
            TestCase("bid32_isNaN", 0, "0x00000001", 0, 0x00),
            TestCase("bid32_isNaN", 0, "0x00080001", 0, 0x00),
            TestCase("bid32_isNaN", 0, "-1.0", 0, 0x00),
            TestCase("bid32_isNaN", 0, "1.0", 0, 0x00),
            TestCase("bid32_isNaN", 0, "-1.0e-96", 0, 0x00),
            TestCase("bid32_isNaN", 0, "1.0e-96", 0, 0x00),
            TestCase("bid32_isNaN", 0, "0x6098967f", 0, 0x00),
            TestCase("bid32_isNaN", 0, "0x60989680", 0, 0x00),
            TestCase("bid32_isNaN", 0, "0x7c000000", 1, 0x00),
            TestCase("bid32_isNaN", 0, "0x7c8f423f", 1, 0x00),
            TestCase("bid32_isNaN", 0, "0x7c8f4240", 1, 0x00),
            TestCase("bid32_isNaN", 0, "0x7e100000", 1, 0x00),
            TestCase("bid32_isNaN", 0, "0x7e100100", 1, 0x00),
            TestCase("bid32_isNaN", 0, "0x7e8f423f", 1, 0x00),
            TestCase("bid32_isNaN", 0, "0x7e8f4240", 1, 0x00),
            TestCase("bid32_isNaN", 0, "0x80000001", 0, 0x00),
            TestCase("bid32_isNaN", 0, "-9.999999e-95", 0, 0x00),
            TestCase("bid32_isNaN", 0, "9.999999e-95", 0, 0x00),
            TestCase("bid32_isNaN", 0, "-9.999999e96", 0, 0x00),
            TestCase("bid32_isNaN", 0, "9.999999e96", 0, 0x00),
            TestCase("bid32_isNaN", 0, "0xfc100000", 1, 0x00),
            TestCase("bid32_isNaN", 0, "0xfc100100", 1, 0x00),
            TestCase("bid32_isNaN", 0, "0xfe000000", 1, 0x00),
                     
            TestCase("bid32_isNormal", 0, "0x00000001", 0, 0x00),
            TestCase("bid32_isNormal", 0, "0x00080001", 0, 0x00),
            TestCase("bid32_isNormal", 0, "0x029259a6", 1, 0x00),
            TestCase("bid32_isNormal", 0, "0x02f69ec8", 1, 0x00),
            TestCase("bid32_isNormal", 0, "0x0a800000", 0, 0x00),
            TestCase("bid32_isNormal", 0, "-1.0", 1, 0x00),
            TestCase("bid32_isNormal", 0, "1.0", 1, 0x00),
            TestCase("bid32_isNormal", 0, "-1.0e-96", 0, 0x00),
            TestCase("bid32_isNormal", 0, "1.0e-96", 0, 0x00),
            TestCase("bid32_isNormal", 0, "0x6098967f", 1, 0x00),
            TestCase("bid32_isNormal", 0, "0x60989680", 0, 0x00),
            TestCase("bid32_isNormal", 0, "0x7c000000", 0, 0x00),
            TestCase("bid32_isNormal", 0, "0x7c8f423f", 0, 0x00),
            TestCase("bid32_isNormal", 0, "0x7c8f4240", 0, 0x00),
            TestCase("bid32_isNormal", 0, "0x7e100000", 0, 0x00),
            TestCase("bid32_isNormal", 0, "0x7e100100", 0, 0x00),
            TestCase("bid32_isNormal", 0, "0x7e8f423f", 0, 0x00),
            TestCase("bid32_isNormal", 0, "0x7e8f4240", 0, 0x00),
            TestCase("bid32_isNormal", 0, "0x80000001", 0, 0x00),
            TestCase("bid32_isNormal", 0, "0x82f69ec3", 1, 0x00),
            TestCase("bid32_isNormal", 0, "0x82f69ec8", 1, 0x00),
            TestCase("bid32_isNormal", 0, "-9.999999e-95", 1, 0x00),
            TestCase("bid32_isNormal", 0, "9.999999e-95", 1, 0x00),
            TestCase("bid32_isNormal", 0, "-9.999999e96", 1, 0x00),
            TestCase("bid32_isNormal", 0, "9.999999e96", 1, 0x00),
            TestCase("bid32_isNormal", 0, "0xfc100000", 0, 0x00),
            TestCase("bid32_isNormal", 0, "0xfc100100", 0, 0x00),
            TestCase("bid32_isNormal", 0, "0xfe000000", 0, 0x00),
            
            TestCase("bid32_isSignaling", 0, "0x00000001", 0, 0x00),
            TestCase("bid32_isSignaling", 0, "0x00080001", 0, 0x00),
            TestCase("bid32_isSignaling", 0, "-1.0", 0, 0x00),
            TestCase("bid32_isSignaling", 0, "1.0", 0, 0x00),
            TestCase("bid32_isSignaling", 0, "-1.0e-96", 0, 0x00),
            TestCase("bid32_isSignaling", 0, "1.0e-96", 0, 0x00),
            TestCase("bid32_isSignaling", 0, "0x6098967f", 0, 0x00),
            TestCase("bid32_isSignaling", 0, "0x60989680", 0, 0x00),
            TestCase("bid32_isSignaling", 0, "0x7c000000", 0, 0x00),
            TestCase("bid32_isSignaling", 0, "0x7c8f423f", 0, 0x00),
            TestCase("bid32_isSignaling", 0, "0x7c8f4240", 0, 0x00),
            TestCase("bid32_isSignaling", 0, "0x7e100000", 1, 0x00),
            TestCase("bid32_isSignaling", 0, "0x7e100100", 1, 0x00),
            TestCase("bid32_isSignaling", 0, "0x7e8f423f", 1, 0x00),
            TestCase("bid32_isSignaling", 0, "0x7e8f4240", 1, 0x00),
            TestCase("bid32_isSignaling", 0, "0x80000001", 0, 0x00),
            TestCase("bid32_isSignaling", 0, "-9.999999e-95", 0, 0x00),
            TestCase("bid32_isSignaling", 0, "9.999999e-95", 0, 0x00),
            TestCase("bid32_isSignaling", 0, "-9.999999e96", 0, 0x00),
            TestCase("bid32_isSignaling", 0, "9.999999e96", 0, 0x00),
            TestCase("bid32_isSignaling", 0, "0xfc100000", 0, 0x00),
            TestCase("bid32_isSignaling", 0, "0xfc100100", 0, 0x00),
            TestCase("bid32_isSignaling", 0, "0xfe000000", 1, 0x00),
                     
            TestCase("bid32_isSigned", 0, "0x00000001", 0, 0x00),
            TestCase("bid32_isSigned", 0, "0x00080001", 0, 0x00),
            TestCase("bid32_isSigned", 0, "1.0", 0, 0x00),
            TestCase("bid32_isSigned", 0, "-1.0", 1, 0x00),
            TestCase("bid32_isSigned", 0, "1.0e-96", 0, 0x00),
            TestCase("bid32_isSigned", 0, "-1.0e-96", 1, 0x00),
            TestCase("bid32_isSigned", 0, "0x6098967f", 0, 0x00),
            TestCase("bid32_isSigned", 0, "0x60989680", 0, 0x00),
            TestCase("bid32_isSigned", 0, "0x7c000000", 0, 0x00),
            TestCase("bid32_isSigned", 0, "0x7c8f423f", 0, 0x00),
            TestCase("bid32_isSigned", 0, "0x7c8f4240", 0, 0x00),
            TestCase("bid32_isSigned", 0, "0x7e100000", 0, 0x00),
            TestCase("bid32_isSigned", 0, "0x7e100100", 0, 0x00),
            TestCase("bid32_isSigned", 0, "0x7e8f423f", 0, 0x00),
            TestCase("bid32_isSigned", 0, "0x7e8f4240", 0, 0x00),
            TestCase("bid32_isSigned", 0, "0x80000001", 1, 0x00),
            TestCase("bid32_isSigned", 0, "9.999999e-95", 0, 0x00),
            TestCase("bid32_isSigned", 0, "-9.999999e-95", 1, 0x00),
            TestCase("bid32_isSigned", 0, "9.999999e96", 0, 0x00),
            TestCase("bid32_isSigned", 0, "-9.999999e96", 1, 0x00),
            TestCase("bid32_isSigned", 0, "0xfc100000", 1, 0x00),
            TestCase("bid32_isSigned", 0, "0xfc100100", 1, 0x00),
            TestCase("bid32_isSigned", 0, "0xfe000000", 1, 0x00),
                     
            TestCase("bid32_isSubnormal", 0, "0x00000001", 1, 0x00),
            TestCase("bid32_isSubnormal", 0, "0x00080001", 1, 0x00),
            TestCase("bid32_isSubnormal", 0, "0x0292599f", 0, 0x00),
            TestCase("bid32_isSubnormal", 0, "0x029259a4", 0, 0x00),
            TestCase("bid32_isSubnormal", 0, "0x029259a6", 0, 0x00),
            TestCase("bid32_isSubnormal", 0, "0x02f69ec8", 0, 0x00),
            TestCase("bid32_isSubnormal", 0, "-1.0", 0, 0x00),
            TestCase("bid32_isSubnormal", 0, "1.0", 0, 0x00),
            TestCase("bid32_isSubnormal", 0, "-1.0e-96", 1, 0x00),
            TestCase("bid32_isSubnormal", 0, "1.0e-96", 1, 0x00),
            TestCase("bid32_isSubnormal", 0, "0x6098967f", 0, 0x00),
            TestCase("bid32_isSubnormal", 0, "0x60989680", 0, 0x00),
            TestCase("bid32_isSubnormal", 0, "0x7c000000", 0, 0x00),
            TestCase("bid32_isSubnormal", 0, "0x7c8f423f", 0, 0x00),
            TestCase("bid32_isSubnormal", 0, "0x7c8f4240", 0, 0x00),
            TestCase("bid32_isSubnormal", 0, "0x7e100000", 0, 0x00),
            TestCase("bid32_isSubnormal", 0, "0x7e100100", 0, 0x00),
            TestCase("bid32_isSubnormal", 0, "0x7e8f423f", 0, 0x00),
            TestCase("bid32_isSubnormal", 0, "0x7e8f4240", 0, 0x00),
            TestCase("bid32_isSubnormal", 0, "0x80000001", 1, 0x00),
            TestCase("bid32_isSubnormal", 0, "-9.999999e-95", 0, 0x00),
            TestCase("bid32_isSubnormal", 0, "9.999999e-95", 0, 0x00),
            TestCase("bid32_isSubnormal", 0, "-9.999999e96", 0, 0x00),
            TestCase("bid32_isSubnormal", 0, "9.999999e96", 0, 0x00),
            TestCase("bid32_isSubnormal", 0, "0xbf800000", 0, 0x00),
            TestCase("bid32_isSubnormal", 0, "0xfc100000", 0, 0x00),
            TestCase("bid32_isSubnormal", 0, "0xfc100100", 0, 0x00),
            TestCase("bid32_isSubnormal", 0, "0xfe000000", 0, 0x00),
                     
            TestCase("bid32_isZero", 0, "0x00000001", 0, 0x00),
            TestCase("bid32_isZero", 0, "0x00080001", 0, 0x00),
            TestCase("bid32_isZero", 0, "-1.0", 0, 0x00),
            TestCase("bid32_isZero", 0, "1.0", 0, 0x00),
            TestCase("bid32_isZero", 0, "-1.0e-96", 0, 0x00),
            TestCase("bid32_isZero", 0, "1.0e-96", 0, 0x00),
            TestCase("bid32_isZero", 0, "0x6098967f", 0, 0x00),
            TestCase("bid32_isZero", 0, "0x60989680", 1, 0x00),
            TestCase("bid32_isZero", 0, "0x7c000000", 0, 0x00),
            TestCase("bid32_isZero", 0, "0x7c8f423f", 0, 0x00),
            TestCase("bid32_isZero", 0, "0x7c8f4240", 0, 0x00),
            TestCase("bid32_isZero", 0, "0x7e100000", 0, 0x00),
            TestCase("bid32_isZero", 0, "0x7e100100", 0, 0x00),
            TestCase("bid32_isZero", 0, "0x7e8f423f", 0, 0x00),
            TestCase("bid32_isZero", 0, "0x7e8f4240", 0, 0x00),
            TestCase("bid32_isZero", 0, "0x80000001", 0, 0x00),
            TestCase("bid32_isZero", 0, "-9.999999e-95", 0, 0x00),
            TestCase("bid32_isZero", 0, "9.999999e-95", 0, 0x00),
            TestCase("bid32_isZero", 0, "-9.999999e96", 0, 0x00),
            TestCase("bid32_isZero", 0, "9.999999e96", 0, 0x00),
            TestCase("bid32_isZero", 0, "0xfc100000", 0, 0x00),
            TestCase("bid32_isZero", 0, "0xfc100100", 0, 0x00),
            TestCase("bid32_isZero", 0, "0xfe000000", 0, 0x00),
            
            TestCase("bid32_mul", 0, "0x00000001", "1.0", 0x00000001, 0x00),
            TestCase("bid32_mul", 0, "0x00080001", "1.0", 0x00080001, 0x00),
            TestCase("bid32_mul", 0, "1.0", "0x00000001", 0x00000001, 0x00),
            TestCase("bid32_mul", 0, "1.0", "0x00080001", 0x00080001, 0x00),
            TestCase("bid32_mul", 0, "1.0", "1.0", 0x31800064, 0x00),
            TestCase("bid32_mul", 0, "-1.0", "1.0", 0xb1800064, 0x00),
            TestCase("bid32_mul", 0, "1.0", "-1.0", 0xb1800064, 0x00),
            TestCase("bid32_mul", 0, "1.0", "1.0e-96", 0x01800064, 0x00),
            TestCase("bid32_mul", 0, "1.0", "-1.0e-96", 0x81800064, 0x00),
            TestCase("bid32_mul", 0, "1.0", "0x6098967f", 0x6098967f, 0x00),
            TestCase("bid32_mul", 0, "1.0", "0x60989680", 0x01800000, 0x00),
            TestCase("bid32_mul", 0, "1.0", "0x7c000000", 0x7c000000, 0x00),
            TestCase("bid32_mul", 0, "1.0", "0x7c8f423f", 0x7c0f423f, 0x00),
            TestCase("bid32_mul", 0, "1.0", "0x7c8f4240", 0x7c000000, 0x00),
            TestCase("bid32_mul", 0, "1.0", "0x7e100000", 0x7c000000, 0x01),
            TestCase("bid32_mul", 0, "1.0", "0x7e100100", 0x7c000100, 0x01),
            TestCase("bid32_mul", 0, "1.0", "0x7e8f423f", 0x7c0f423f, 0x01),
            TestCase("bid32_mul", 0, "1.0", "0x7e8f4240", 0x7c000000, 0x01),
            TestCase("bid32_mul", 0, "1.0", "0x80000001", 0x80000001, 0x00),
            TestCase("bid32_mul", 0, "1.0", "9.999999e-95", 0x6018967f, 0x00),
            TestCase("bid32_mul", 0, "1.0", "-9.999999e-95", 0xe018967f, 0x00),
            TestCase("bid32_mul", 0, "1.0", "9.999999e96", 0x77f8967f, 0x00),
            TestCase("bid32_mul", 0, "1.0", "-9.999999e96", 0xf7f8967f, 0x00),
            TestCase("bid32_mul", 0, "1.0e-96", "1.0", 0x01800064, 0x00),
            TestCase("bid32_mul", 0, "-1.0e-96", "1.0", 0x81800064, 0x00),
            TestCase("bid32_mul", 0, "1.0", "0xfc100000", 0xfc000000, 0x00),
            TestCase("bid32_mul", 0, "1.0", "0xfc100100", 0xfc000100, 0x00),
            TestCase("bid32_mul", 0, "1.0", "0xfe000000", 0xfc000000, 0x01),
            TestCase("bid32_mul", 0, "0x6098967f", "1.0", 0x6098967f, 0x00),
            TestCase("bid32_mul", 0, "0x60989680", "1.0", 0x01800000, 0x00),
            TestCase("bid32_mul", 0, "0x7c000000", "1.0", 0x7c000000, 0x00),
            TestCase("bid32_mul", 0, "0x7c8f423f", "1.0", 0x7c0f423f, 0x00),
            TestCase("bid32_mul", 0, "0x7c8f423f", "0x7e100000", 0x7c0f423f, 0x01),
            TestCase("bid32_mul", 0, "0x7c8f423f", "Infinity", 0x7c0f423f, 0x00),
            TestCase("bid32_mul", 0, "0x7c8f4240", "1.0", 0x7c000000, 0x00),
            TestCase("bid32_mul", 0, "0x7e100000", "1.0", 0x7c000000, 0x01),
            TestCase("bid32_mul", 0, "0x7e100100", "1.0", 0x7c000100, 0x01),
            TestCase("bid32_mul", 0, "0x7e8f423f", "1.0", 0x7c0f423f, 0x01),
            TestCase("bid32_mul", 0, "0x7e8f4240", "1.0", 0x7c000000, 0x01),
            TestCase("bid32_mul", 0, "0x80000001", "1.0", 0x80000001, 0x00),
            TestCase("bid32_mul", 0, "9.999999e-95", "1.0", 0x6018967f, 0x00),
            TestCase("bid32_mul", 0, "-9.999999e-95", "1.0", 0xe018967f, 0x00),
            TestCase("bid32_mul", 0, "9.999999e96", "1.0", 0x77f8967f, 0x00),
            TestCase("bid32_mul", 0, "-9.999999e96", "1.0", 0xf7f8967f, 0x00),
            TestCase("bid32_mul", 0, "0xfc100000", "1.0", 0xfc000000, 0x00),
            TestCase("bid32_mul", 0, "0xfc100100", "1.0", 0xfc000100, 0x00),
            TestCase("bid32_mul", 0, "0xfe000000", "1.0", 0xfc000000, 0x01),
            TestCase("bid32_mul", 0, "Infinity", "NaN", 0x7c000000, 0x00),
            
            TestCase("bid32_negate", 0, "0x00000001", 0x80000001, 0x00),    // 1
            TestCase("bid32_negate", 0, "0x00080001", 0x80080001, 0x00),
            TestCase("bid32_negate", 0, "-1.0", 0x3200000a, 0x00),
            TestCase("bid32_negate", 0, "1.0", 0xb200000a, 0x00),
            TestCase("bid32_negate", 0, "-1.0e-96", 0x0200000a, 0x00),
            TestCase("bid32_negate", 0, "1.0e-96", 0x8200000a, 0x00),
            TestCase("bid32_negate", 0, "0x6098967f", 0xe098967f, 0x00),
            TestCase("bid32_negate", 0, "0x60989680", 0xe0989680, 0x00),
            TestCase("bid32_negate", 0, "0x7c000000", 0xfc000000, 0x00),
            TestCase("bid32_negate", 0, "0x7c8f423f", 0xfc8f423f, 0x00),    // 10
            TestCase("bid32_negate", 0, "0x7c8f4240", 0xfc8f4240, 0x00),
            TestCase("bid32_negate", 0, "0x7e100000", 0xfe100000, 0x00),
            TestCase("bid32_negate", 0, "0x7e100100", 0xfe100100, 0x00),
            TestCase("bid32_negate", 0, "0x7e8f423f", 0xfe8f423f, 0x00),
            TestCase("bid32_negate", 0, "0x7e8f4240", 0xfe8f4240, 0x00),
            TestCase("bid32_negate", 0, "0x80000001", 0x00000001, 0x00),
            TestCase("bid32_negate", 0, "-9.999999e-95", 0x6018967f, 0x00),
            TestCase("bid32_negate", 0, "9.999999e-95", 0xe018967f, 0x00),
            TestCase("bid32_negate", 0, "-9.999999e96", 0x77f8967f, 0x00),
            TestCase("bid32_negate", 0, "9.999999e96", 0xf7f8967f, 0x00),   // 20
            TestCase("bid32_negate", 0, "0xfc100000", 0x7c100000, 0x00),
            TestCase("bid32_negate", 0, "0xfc100100", 0x7c100100, 0x00),
            TestCase("bid32_negate", 0, "0xfe000000", 0x7e000000, 0x00),
            
            TestCase("bid32_to_bid128", 0, "0x3d000000", "0x306a0000000000000000000000000000", 0x00),
            TestCase("bid32_to_bid128", 0, "0x7c000100", "0x7c0000033b2e3c9fd0803ce800000000", 0x00),
            TestCase("bid32_to_bid128", 0, "0x92229c08", "0xafbe0000000000000000000000229c08", 0x00),
            TestCase("bid32_to_bid128", 0, "0xe5c005c3", "0xafd200000000000000000000008005c3", 0x00),
            TestCase("bid32_to_bid128", 0, "0xfe000000", "0xfc000000000000000000000000000000", 0x01),
            TestCase("bid32_to_bid128", 0, "-Infinity", "0xf8000000000000000000000000000000", 0x00),
            
            TestCase("bid32_to_bid64", 0, "0x00000000", 0x2520000000000000, 0x00),
            TestCase("bid32_to_bid64", 0, "0x00000001", 0x2520000000000001, 0x00),
            TestCase("bid32_to_bid64", 0, "0x00000066", 0x2520000000000066, 0x00),
            TestCase("bid32_to_bid64", 0, "0x00001231", 0x2520000000001231, 0x00),
            TestCase("bid32_to_bid64", 0, "0x000027db", 0x25200000000027db, 0x00),
            TestCase("bid32_to_bid64", 0, "0x000f1b60", 0x25200000000f1b60, 0x00),
            TestCase("bid32_to_bid64", 0, "0x0012d687", 0x252000000012d687, 0x00),
            TestCase("bid32_to_bid64", 0, "0x02800000", 0x25c0000000000000, 0x00),
            TestCase("bid32_to_bid64", 0, "0x02800001", 0x25c0000000000001, 0x00),
            TestCase("bid32_to_bid64", 0, "0x2f8f4240", 0x31000000000f4240, 0x00),
            TestCase("bid32_to_bid64", 0, "0x2f9e8480", 0x31000000001e8480, 0x00),
            TestCase("bid32_to_bid64", 0, "0x300186a0", 0x31200000000186a0, 0x00),
            TestCase("bid32_to_bid64", 0, "0x30030d40", 0x3120000000030d40, 0x00),
            TestCase("bid32_to_bid64", 0, "0x30802710", 0x3140000000002710, 0x00),
            TestCase("bid32_to_bid64", 0, "0x30804e20", 0x3140000000004e20, 0x00),
            TestCase("bid32_to_bid64", 0, "0x310003e8", 0x31600000000003e8, 0x00),
            TestCase("bid32_to_bid64", 0, "0x310007d0", 0x31600000000007d0, 0x00),
            TestCase("bid32_to_bid64", 0, "0x31800064", 0x3180000000000064, 0x00),
            TestCase("bid32_to_bid64", 0, "0x318000c8", 0x31800000000000c8, 0x00),
            TestCase("bid32_to_bid64", 0, "0x3200000a", 0x31a000000000000a, 0x00),
            TestCase("bid32_to_bid64", 0, "0x32000014", 0x31a0000000000014, 0x00),
            TestCase("bid32_to_bid64", 0, "0x32800001", 0x31c0000000000001, 0x00),
            TestCase("bid32_to_bid64", 0, "0x32800002", 0x31c0000000000002, 0x00),
            TestCase("bid32_to_bid64", 0, "0x32800003", 0x31c0000000000003, 0x00),
            TestCase("bid32_to_bid64", 0, "0x32800004", 0x31c0000000000004, 0x00),
            TestCase("bid32_to_bid64", 0, "0x32800008", 0x31c0000000000008, 0x00),
            TestCase("bid32_to_bid64", 0, "0x32800010", 0x31c0000000000010, 0x00),
            TestCase("bid32_to_bid64", 0, "0x32800020", 0x31c0000000000020, 0x00),
            TestCase("bid32_to_bid64", 0, "0x32800040", 0x31c0000000000040, 0x00),
            TestCase("bid32_to_bid64", 0, "0x32800080", 0x31c0000000000080, 0x00),
            TestCase("bid32_to_bid64", 0, "0x32800100", 0x31c0000000000100, 0x00),
            TestCase("bid32_to_bid64", 0, "0x32800200", 0x31c0000000000200, 0x00),
            TestCase("bid32_to_bid64", 0, "0x32800400", 0x31c0000000000400, 0x00),
            TestCase("bid32_to_bid64", 0, "0x32800800", 0x31c0000000000800, 0x00),
            TestCase("bid32_to_bid64", 0, "0x32801000", 0x31c0000000001000, 0x00),
            TestCase("bid32_to_bid64", 0, "0x32802000", 0x31c0000000002000, 0x00),
            TestCase("bid32_to_bid64", 0, "0x32804000", 0x31c0000000004000, 0x00),
            TestCase("bid32_to_bid64", 0, "0x32808000", 0x31c0000000008000, 0x00),
            TestCase("bid32_to_bid64", 0, "0x32810000", 0x31c0000000010000, 0x00),
            TestCase("bid32_to_bid64", 0, "0x32820000", 0x31c0000000020000, 0x00),
            TestCase("bid32_to_bid64", 0, "0x32840000", 0x31c0000000040000, 0x00),
            TestCase("bid32_to_bid64", 0, "0x32880000", 0x31c0000000080000, 0x00),
            TestCase("bid32_to_bid64", 0, "0x32900000", 0x31c0000000100000, 0x00),
            TestCase("bid32_to_bid64", 0, "0x32a00000", 0x31c0000000200000, 0x00),
            TestCase("bid32_to_bid64", 0, "0x32c00000", 0x31c0000000400000, 0x00),
            TestCase("bid32_to_bid64", 0, "0x3319999a", 0x31e000000019999a, 0x00),
            TestCase("bid32_to_bid64", 0, "0x33333333", 0x31e0000000333333, 0x00),
            TestCase("bid32_to_bid64", 0, "0x33666666", 0x31e0000000666666, 0x00),
            TestCase("bid32_to_bid64", 0, "0x33947ae1", 0x3200000000147ae1, 0x00),
            TestCase("bid32_to_bid64", 0, "0x33a8f5c3", 0x320000000028f5c3, 0x00),
            TestCase("bid32_to_bid64", 0, "0x5f000000", 0x3ce0000000000000, 0x00),
            TestCase("bid32_to_bid64", 0, "0x5f000001", 0x3ce0000000000001, 0x00),
            TestCase("bid32_to_bid64", 0, "0x5f12d687", 0x3ce000000012d687, 0x00),
            TestCase("bid32_to_bid64", 0, "0x5f800000", 0x3d00000000000000, 0x00),
            TestCase("bid32_to_bid64", 0, "0x5f800001", 0x3d00000000000001, 0x00),
            TestCase("bid32_to_bid64", 0, "0x5f8f4241", 0x3d000000000f4241, 0x00),
            TestCase("bid32_to_bid64", 0, "0x5f92d687", 0x3d0000000012d687, 0x00),
            TestCase("bid32_to_bid64", 0, "0x6018967f", 0x252000000098967f, 0x00),
            TestCase("bid32_to_bid64", 0, "0x607fffff", 0x2580000000000000, 0x00),
            TestCase("bid32_to_bid64", 0, "0x658c3437", 0x2aa00000008c3437, 0x00),
            TestCase("bid32_to_bid64", 0, "0x6ca00000", 0x31c0000000800000, 0x00),
            TestCase("bid32_to_bid64", 0, "0x77eae409", 0x3d000000008ae409, 0x00),
            TestCase("bid32_to_bid64", 0, "0x77f8967e", 0x3d0000000098967e, 0x00),
            TestCase("bid32_to_bid64", 0, "0x77f8967f", 0x3d0000000098967f, 0x00),
            TestCase("bid32_to_bid64", 0, "0x78000000", 0x7800000000000000, 0x00),
            TestCase("bid32_to_bid64", 0, "0x78000001", 0x7800000000000000, 0x00),
            TestCase("bid32_to_bid64", 0, "0x78001000", 0x7800000000000000, 0x00),
            TestCase("bid32_to_bid64", 0, "0x780fffff", 0x7800000000000000, 0x00),
            TestCase("bid32_to_bid64", 0, "0x78f00000", 0x7800000000000000, 0x00),
            TestCase("bid32_to_bid64", 0, "0x78f00001", 0x7800000000000000, 0x00),
            TestCase("bid32_to_bid64", 0, "0x78ffffff", 0x7800000000000000, 0x00),
            TestCase("bid32_to_bid64", 0, "0x7c000000", 0x7c00000000000000, 0x00),
            TestCase("bid32_to_bid64", 0, "0x7c000001", 0x7c0000003b9aca00, 0x00),
            TestCase("bid32_to_bid64", 0, "0x7c000100", 0x7c00003b9aca0000, 0x00),
            TestCase("bid32_to_bid64", 0, "0x7c001000", 0x7c0003b9aca00000, 0x00),
            TestCase("bid32_to_bid64", 0, "0x7c0fffff", 0x7c00000000000000, 0x00),
            TestCase("bid32_to_bid64", 0, "0x7cf00000", 0x7c00000000000000, 0x00),
            TestCase("bid32_to_bid64", 0, "0x7cf00001", 0x7c0000003b9aca00, 0x00),
            TestCase("bid32_to_bid64", 0, "0x7cffffff", 0x7c00000000000000, 0x00),
            TestCase("bid32_to_bid64", 0, "0x7e000000", 0x7c00000000000000, 0x01),
            TestCase("bid32_to_bid64", 0, "0x7e000001", 0x7c0000003b9aca00, 0x01),
            TestCase("bid32_to_bid64", 0, "0x7e000100", 0x7c00003b9aca0000, 0x01),
            TestCase("bid32_to_bid64", 0, "0x7e0fffff", 0x7c00000000000000, 0x01),
            TestCase("bid32_to_bid64", 0, "0x7ef00000", 0x7c00000000000000, 0x01),
            TestCase("bid32_to_bid64", 0, "0x7ef00001", 0x7c0000003b9aca00, 0x01),
            TestCase("bid32_to_bid64", 0, "0x7effffff", 0x7c00000000000000, 0x01),
            TestCase("bid32_to_bid64", 0, "0x80000000", 0xa520000000000000, 0x00),
            TestCase("bid32_to_bid64", 0, "0x80000001", 0xa520000000000001, 0x00),
            TestCase("bid32_to_bid64", 0, "0x800007d0", 0xa5200000000007d0, 0x00),
            TestCase("bid32_to_bid64", 0, "0x800027db", 0xa5200000000027db, 0x00),
            TestCase("bid32_to_bid64", 0, "0x808000c8", 0xa5400000000000c8, 0x00),
            TestCase("bid32_to_bid64", 0, "0x81000014", 0xa560000000000014, 0x00),
            TestCase("bid32_to_bid64", 0, "0x81800002", 0xa580000000000002, 0x00),
            TestCase("bid32_to_bid64", 0, "0xdf8f4241", 0xbd000000000f4241, 0x00),
            TestCase("bid32_to_bid64", 0, "0xdf92d687", 0xbd0000000012d687, 0x00),
            TestCase("bid32_to_bid64", 0, "0xf420b31f", 0xb94000000080b31f, 0x00),
            TestCase("bid32_to_bid64", 0, "0xf71fffff", 0xbc20000000000000, 0x00),
            TestCase("bid32_to_bid64", 0, "0xf7f8967e", 0xbd0000000098967e, 0x00),
            TestCase("bid32_to_bid64", 0, "0xf7f8967f", 0xbd0000000098967f, 0x00),
            TestCase("bid32_to_bid64", 0, "0xf8000000", 0xf800000000000000, 0x00),
            TestCase("bid32_to_bid64", 0, "0xf8000001", 0xf800000000000000, 0x00),
            TestCase("bid32_to_bid64", 0, "0xf8001000", 0xf800000000000000, 0x00),
            TestCase("bid32_to_bid64", 0, "0xf80fffff", 0xf800000000000000, 0x00),
            TestCase("bid32_to_bid64", 0, "0xf8f00000", 0xf800000000000000, 0x00),
            TestCase("bid32_to_bid64", 0, "0xf8f00001", 0xf800000000000000, 0x00),
            TestCase("bid32_to_bid64", 0, "0xf8ffffff", 0xf800000000000000, 0x00),
            TestCase("bid32_to_bid64", 0, "0xfc000000", 0xfc00000000000000, 0x00),
            TestCase("bid32_to_bid64", 0, "0xfc000001", 0xfc0000003b9aca00, 0x00),
            TestCase("bid32_to_bid64", 0, "0xfc001000", 0xfc0003b9aca00000, 0x00),
            TestCase("bid32_to_bid64", 0, "0xfc0fffff", 0xfc00000000000000, 0x00),
            TestCase("bid32_to_bid64", 0, "0xfcf00000", 0xfc00000000000000, 0x00),
            TestCase("bid32_to_bid64", 0, "0xfcf00001", 0xfc0000003b9aca00, 0x00),
            TestCase("bid32_to_bid64", 0, "0xfcffffff", 0xfc00000000000000, 0x00),
            TestCase("bid32_to_bid64", 0, "0xfe000000", 0xfc00000000000000, 0x01),
            TestCase("bid32_to_bid64", 0, "0xfe000001", 0xfc0000003b9aca00, 0x01),
            TestCase("bid32_to_bid64", 0, "0xfe000100", 0xfc00003b9aca0000, 0x01),
            TestCase("bid32_to_bid64", 0, "0xfe0fffff", 0xfc00000000000000, 0x01),
            TestCase("bid32_to_bid64", 0, "0xfef00000", 0xfc00000000000000, 0x01),
            TestCase("bid32_to_bid64", 0, "0xfef00001", 0xfc0000003b9aca00, 0x01),
            TestCase("bid32_to_bid64", 0, "0xfeffffff", 0xfc00000000000000, 0x01),
            
            TestCase("bid32_to_binary64", 0, "0x00000001", 0x2af665bf1d3e6a8d, 0x20),   // 1
            TestCase("bid32_to_binary64", 0, "0x00000001", 0x2AF665BF1D3E6A8D, 0x20),
            // Here when x=noncanonical finite
            TestCase("bid32_to_binary64", 0, "0x00989680", 0x2C75830F53F56FD4, 0x20),
            TestCase("bid32_to_binary64", 0, "0x010bcb3b", 0x2c99cbd06456ee4e, 0x20),
            TestCase("bid32_to_binary64", 0, "0x03000001", 0x2c355c2076bf9a55, 0x20),
            TestCase("bid32_to_binary64", 0, "0x03800001", 0x2c6ab328946f80ea, 0x20),
            TestCase("bid32_to_binary64", 0, "0x04f08deb", 0x2e425799582d3bbe, 0x20),
            TestCase("bid32_to_binary64", 0, "0x0881888c", 0x2f87d4b57562e710, 0x20),
            TestCase("bid32_to_binary64", 0, "0x0c8a06d8", 0x315d0681489839d5, 0x20),
            TestCase("bid32_to_binary64", 0, "0x1082384c", 0x32e326cd14f71c23, 0x20),   // 10
            TestCase("bid32_to_binary64", 0, "0x1489fdf7", 0x34b00e7db3b3f242, 0x20),
            TestCase("bid32_to_binary64", 0, "0x1871b2b3", 0x365b39ab78718832, 0x20),
            // Here argument is near min denormalized float
            TestCase("bid32_to_binary64", 0, "0x189ABA47", 0x366FFFFFE75B0A51, 0x20),
            TestCase("bid32_to_binary64", 0, "0x189ABA49", 0x36700001262D4AB6, 0x20),
            TestCase("bid32_to_binary64", 0, "0x18EAE91C", 0x368FFFFFE75B0A51, 0x20),
            TestCase("bid32_to_binary64", 0, "0x18EAE923", 0x36900000FFDD5204, 0x20),
            TestCase("bid32_to_binary64", 0, "0x1910095E", 0x369800003A243920, 0x20),
            TestCase("bid32_to_binary64", 0, "0x191561D2", 0x369FFFFF4E1B278A, 0x20),
            TestCase("bid32_to_binary64", 0, "0x192012BC", 0x36A800003A243920, 0x20),
            TestCase("bid32_to_binary64", 0, "0x1A0036BD", 0x36A00001262D4AB6, 0x20),   // 20
            TestCase("bid32_to_binary64", 0, "0x1A6D79F8", 0x372FFFFFF5B90794, 0x20),
            TestCase("bid32_to_binary64", 0, "0x1A6D79FF", 0x3730000100C331D9, 0x20),
            TestCase("bid32_to_binary64", 0, "0x1c37083b", 0x37f3a2d93e5ad254, 0x20),
            TestCase("bid32_to_binary64", 0, "0x2082ffad", 0x398fe3544145e9d8, 0x20),
            TestCase("bid32_to_binary64", 0, "0x24033b59", 0x3b047bf052eac347, 0x20),
            TestCase("bid32_to_binary64", 0, "0x2bb057d9", 0x3e61025d42033846, 0x20),
            TestCase("bid32_to_binary64", 0, "0x2ecd7c6d", 0x3faa000000000000, 0x00),
            TestCase("bid32_to_binary64", 0, "0x2ff9ff92", 0x401ffb2b3461309c, 0x20),
            TestCase("bid32_to_binary64", 0, "0x3200000f", 0x3ff8000000000000, 0x00),
            TestCase("bid32_to_binary64", 0, "0x32800000", 0x0000000000000000, 0x00),   // 30
            // Here different combinations of number of leading zero),es in significand
            TestCase("bid32_to_binary64", 0, "0x32800001", 0x3FF0000000000000, 0x00),
            TestCase("bid32_to_binary64", 0, "0x32800001", 0x3ff0000000000000, 0x00),
            TestCase("bid32_to_binary64", 0, "0x32800040", 0x4050000000000000, 0x00),
            TestCase("bid32_to_binary64", 0, "0x328003e7", 0x408f380000000000, 0x00),
            TestCase("bid32_to_binary64", 0, "0x328003e8", 0x408f400000000000, 0x00),
            TestCase("bid32_to_binary64", 0, "0x3281ffff", 0x40FFFFF000000000, 0x00),
            TestCase("bid32_to_binary64", 0, "0x3283ffff", 0x410FFFF800000000, 0x00),
            TestCase("bid32_to_binary64", 0, "0x3287ffff", 0x411FFFFC00000000, 0x00),
            TestCase("bid32_to_binary64", 0, "0x328fffff", 0x412FFFFE00000000, 0x00),
            TestCase("bid32_to_binary64", 0, "0x3297ffff", 0x4137FFFF00000000, 0x00),   // 40
            TestCase("bid32_to_binary64", 0, "0x3319999A", 0x4170000040000000, 0x00),
            TestCase("bid32_to_binary64", 0, "0x33a8f5c2", 0x41afffff90000000, 0x00),
            TestCase("bid32_to_binary64", 0, "0x3800AFEC", 0x433000001635E000, 0x00),
            TestCase("bid32_to_binary64", 0, "0x391C25C2", 0x43EFFFFF89707FA8, 0x00),
            TestCase("bid32_to_binary64", 0, "0x3b2e1de6", 0x44cffffcd7edc456, 0x20),
            TestCase("bid32_to_binary64", 0, "0x3edc99f0", 0x46532645e1ba93f0, 0x20),
            TestCase("bid32_to_binary64", 0, "0x404F3A69", 0x46F00000075046A6, 0x20),
            TestCase("bid32_to_binary64", 0, "0x408FD87B", 0x46FFFFFF3FD4FE24, 0x20),
            // Here argument is near max normalized double/float
            TestCase("bid32_to_binary64", 0, "0x42B3DEFD", 0x47EFF7CEF1751C53, 0x20),
            TestCase("bid32_to_binary64", 0, "0x42CDE26C", 0x47F8000027246519, 0x20),   // 50
            TestCase("bid32_to_binary64", 0, "0x43175D87", 0x4812000044CCB73D, 0x20),
            TestCase("bid32_to_binary64", 0, "0x47140a10", 0x49b70105df3d47cb, 0x20),
            TestCase("bid32_to_binary64", 0, "0x4afda8f2", 0x4b557eb8ad52a5c9, 0x20),
            TestCase("bid32_to_binary64", 0, "0x4e980326", 0x4cd87b809b494507, 0x20),
            TestCase("bid32_to_binary64", 0, "0x5aa9d03d", 0x51e1a1d9135cca53, 0x20),   // 55
            TestCase("bid32_to_binary64", 0, "0x69edd92d", 0x3cd0bf1a651525e8, 0x20),
            TestCase("bid32_to_binary64", 0, "0x6CA00000", 0x4160000000000000, 0x00),
            TestCase("bid32_to_binary64", 0, "0x6CB89680", 0x0000000000000000, 0x00),
            TestCase("bid32_to_binary64", 0, "0x6dc97056", 0x433ffffdd85fdc00, 0x00),
            TestCase("bid32_to_binary64", 0, "0x6DC9705F", 0x433FFFFFF0D0F600, 0x00),
            TestCase("bid32_to_binary64", 0, "0x6E2CBCCC", 0x43DFFFFFFDDAD230, 0x00),
            TestCase("bid32_to_binary64", 0, "0x70c9732f", 0x483a78ce1807f5f8, 0x20),
            TestCase("bid32_to_binary64", 0, "0x74b6e7ac", 0x4eaca897d8932bce, 0x20),
            TestCase("bid32_to_binary64", 0, "0x758a9968", 0x501f60b4a930ae18, 0x20),
            TestCase("bid32_to_binary64", 0, "0x77f8967f", 0x5412ba093e5c6114, 0x20),
            TestCase("bid32_to_binary64", 0, "0x77F8967F", 0x5412BA093E5C6114, 0x20),
            TestCase("bid32_to_binary64", 0, "0x77f89680", 0x0000000000000000, 0x00),
            TestCase("bid32_to_binary64", 0, "0x78000000", 0x7ff0000000000000, 0x00),
            // Here when x=qNaN with canonical/non-canonical payload
            TestCase("bid32_to_binary64", 0, "0x7c000000", 0x7FF8000000000000, 0x00),
            TestCase("bid32_to_binary64", 0, "0x7c0F423F", 0x7FFFA11F80000000, 0x00),
            TestCase("bid32_to_binary64", 0, "0x7c0F4240", 0x7FF8000000000000, 0x00),
            // Here when x=sNaN with canonical/non-canonical payload
            TestCase("bid32_to_binary64", 0, "0x7e000000", 0x7FF8000000000000, 0x01),
            TestCase("bid32_to_binary64", 0, "0x7e0F423F", 0x7FFFA11F80000000, 0x01),
            TestCase("bid32_to_binary64", 0, "0x7e0F4240", 0x7FF8000000000000, 0x01),
            TestCase("bid32_to_binary64", 0, "0x80000001", 0xaaf665bf1d3e6a8d, 0x20),
            TestCase("bid32_to_binary64", 0, "0x810bcb3b", 0xac99cbd06456ee4e, 0x20),
            TestCase("bid32_to_binary64", 0, "0x83000001", 0xac355c2076bf9a55, 0x20),
            TestCase("bid32_to_binary64", 0, "0x83800001", 0xac6ab328946f80ea, 0x20),
            TestCase("bid32_to_binary64", 0, "0x84f08deb", 0xae425799582d3bbe, 0x20),
            TestCase("bid32_to_binary64", 0, "0x8881888c", 0xaf87d4b57562e710, 0x20),
            TestCase("bid32_to_binary64", 0, "0x8c8a06d8", 0xb15d0681489839d5, 0x20),
            TestCase("bid32_to_binary64", 0, "0x9082384c", 0xb2e326cd14f71c23, 0x20),
            TestCase("bid32_to_binary64", 0, "0x9489fdf7", 0xb4b00e7db3b3f242, 0x20),
            TestCase("bid32_to_binary64", 0, "0x9871b2b3", 0xb65b39ab78718832, 0x20),
            TestCase("bid32_to_binary64", 0, "0x9c37083b", 0xb7f3a2d93e5ad254, 0x20),
            TestCase("bid32_to_binary64", 0, "0xa082ffad", 0xb98fe3544145e9d8, 0x20),
            TestCase("bid32_to_binary64", 0, "0xa4033b59", 0xbb047bf052eac347, 0x20),
            TestCase("bid32_to_binary64", 0, "0xabb057d9", 0xbe61025d42033846, 0x20),
            TestCase("bid32_to_binary64", 0, "0xaecd7c6d", 0xbfaa000000000000, 0x00),
            TestCase("bid32_to_binary64", 0, "0xaff9ff92", 0xc01ffb2b3461309c, 0x20),
            TestCase("bid32_to_binary64", 0, "0xb200000f", 0xbff8000000000000, 0x00),
            TestCase("bid32_to_binary64", 0, "0xb2800001", 0xbff0000000000000, 0x00),
            TestCase("bid32_to_binary64", 0, "0xb2800040", 0xc050000000000000, 0x00),
            TestCase("bid32_to_binary64", 0, "0xb28003e7", 0xc08f380000000000, 0x00),
            TestCase("bid32_to_binary64", 0, "0xb28003e8", 0xc08f400000000000, 0x00),
            TestCase("bid32_to_binary64", 0, "0xb3a8f5c2", 0xc1afffff90000000, 0x00),
            TestCase("bid32_to_binary64", 0, "0xbb2e1de6", 0xc4cffffcd7edc456, 0x20),
            TestCase("bid32_to_binary64", 0, "0xbedc99f0", 0xc6532645e1ba93f0, 0x20),
            TestCase("bid32_to_binary64", 0, "0xc7140a10", 0xc9b70105df3d47cb, 0x20),
            TestCase("bid32_to_binary64", 0, "0xcafda8f2", 0xcb557eb8ad52a5c9, 0x20),
            TestCase("bid32_to_binary64", 0, "0xce980326", 0xccd87b809b494507, 0x20),
            TestCase("bid32_to_binary64", 0, "0xdaa9d03d", 0xd1e1a1d9135cca53, 0x20),
            TestCase("bid32_to_binary64", 0, "0xe9edd92d", 0xbcd0bf1a651525e8, 0x20),
            TestCase("bid32_to_binary64", 0, "0xedc97056", 0xc33ffffdd85fdc00, 0x00),
            TestCase("bid32_to_binary64", 0, "0xf0c9732f", 0xc83a78ce1807f5f8, 0x20),
            TestCase("bid32_to_binary64", 0, "0xf4b6e7ac", 0xceaca897d8932bce, 0x20),
            TestCase("bid32_to_binary64", 0, "0xf58a9968", 0xd01f60b4a930ae18, 0x20),
            TestCase("bid32_to_binary64", 0, "0xf7f8967f", 0xd412ba093e5c6114, 0x20),
            TestCase("bid32_to_binary64", 0, "0xf8000000", 0xfff0000000000000, 0x00),
            TestCase("bid32_to_binary64", 1, "0x00000001", 0x2af665bf1d3e6a8c, 0x20),
            TestCase("bid32_to_binary64", 1, "0x010bcb3b", 0x2c99cbd06456ee4e, 0x20),
            TestCase("bid32_to_binary64", 1, "0x03000001", 0x2c355c2076bf9a55, 0x20),
            TestCase("bid32_to_binary64", 1, "0x03800001", 0x2c6ab328946f80ea, 0x20),
            TestCase("bid32_to_binary64", 1, "0x04f08deb", 0x2e425799582d3bbd, 0x20),
            TestCase("bid32_to_binary64", 1, "0x0881888c", 0x2f87d4b57562e710, 0x20),
            TestCase("bid32_to_binary64", 1, "0x0c8a06d8", 0x315d0681489839d5, 0x20),
            TestCase("bid32_to_binary64", 1, "0x1082384c", 0x32e326cd14f71c23, 0x20),
            TestCase("bid32_to_binary64", 1, "0x1489fdf7", 0x34b00e7db3b3f241, 0x20),
            TestCase("bid32_to_binary64", 1, "0x1871b2b3", 0x365b39ab78718831, 0x20),
            TestCase("bid32_to_binary64", 1, "0x1c37083b", 0x37f3a2d93e5ad253, 0x20),
            TestCase("bid32_to_binary64", 1, "0x2082ffad", 0x398fe3544145e9d8, 0x20),
            TestCase("bid32_to_binary64", 1, "0x24033b59", 0x3b047bf052eac347, 0x20),
            TestCase("bid32_to_binary64", 1, "0x2bb057d9", 0x3e61025d42033846, 0x20),
            TestCase("bid32_to_binary64", 1, "0x2ecd7c6d", 0x3faa000000000000, 0x00),
            TestCase("bid32_to_binary64", 1, "0x2ff9ff92", 0x401ffb2b3461309c, 0x20),
            TestCase("bid32_to_binary64", 1, "0x3200000f", 0x3ff8000000000000, 0x00),
            TestCase("bid32_to_binary64", 1, "0x32800000", 0x0000000000000000, 0x00),
            TestCase("bid32_to_binary64", 1, "0x32800001", 0x3ff0000000000000, 0x00),
            TestCase("bid32_to_binary64", 1, "0x32800040", 0x4050000000000000, 0x00),
            TestCase("bid32_to_binary64", 1, "0x328003e7", 0x408f380000000000, 0x00),
            TestCase("bid32_to_binary64", 1, "0x328003e8", 0x408f400000000000, 0x00),
            TestCase("bid32_to_binary64", 1, "0x33a8f5c2", 0x41afffff90000000, 0x00),
            TestCase("bid32_to_binary64", 1, "0x3b2e1de6", 0x44cffffcd7edc455, 0x20),
            TestCase("bid32_to_binary64", 1, "0x3edc99f0", 0x46532645e1ba93ef, 0x20),
            TestCase("bid32_to_binary64", 1, "0x47140a10", 0x49b70105df3d47cb, 0x20),
            TestCase("bid32_to_binary64", 1, "0x4afda8f2", 0x4b557eb8ad52a5c8, 0x20),
            TestCase("bid32_to_binary64", 1, "0x4e980326", 0x4cd87b809b494507, 0x20),
            TestCase("bid32_to_binary64", 1, "0x5aa9d03d", 0x51e1a1d9135cca53, 0x20),
            TestCase("bid32_to_binary64", 1, "0x69edd92d", 0x3cd0bf1a651525e7, 0x20),
            TestCase("bid32_to_binary64", 1, "0x6dc97056", 0x433ffffdd85fdc00, 0x00),
            TestCase("bid32_to_binary64", 1, "0x70c9732f", 0x483a78ce1807f5f8, 0x20),
            TestCase("bid32_to_binary64", 1, "0x74b6e7ac", 0x4eaca897d8932bce, 0x20),
            TestCase("bid32_to_binary64", 1, "0x758a9968", 0x501f60b4a930ae17, 0x20),
            TestCase("bid32_to_binary64", 1, "0x77f8967f", 0x5412ba093e5c6114, 0x20),
            TestCase("bid32_to_binary64", 1, "0x78000000", 0x7ff0000000000000, 0x00),
            TestCase("bid32_to_binary64", 1, "0x80000001", 0xaaf665bf1d3e6a8d, 0x20),
            TestCase("bid32_to_binary64", 1, "0x810bcb3b", 0xac99cbd06456ee4f, 0x20),
            TestCase("bid32_to_binary64", 1, "0x83000001", 0xac355c2076bf9a56, 0x20),
            TestCase("bid32_to_binary64", 1, "0x83800001", 0xac6ab328946f80eb, 0x20),
            TestCase("bid32_to_binary64", 1, "0x84f08deb", 0xae425799582d3bbe, 0x20),
            TestCase("bid32_to_binary64", 1, "0x8881888c", 0xaf87d4b57562e711, 0x20),
            TestCase("bid32_to_binary64", 1, "0x8c8a06d8", 0xb15d0681489839d6, 0x20),
            TestCase("bid32_to_binary64", 1, "0x9082384c", 0xb2e326cd14f71c24, 0x20),
            TestCase("bid32_to_binary64", 1, "0x9489fdf7", 0xb4b00e7db3b3f242, 0x20),
            TestCase("bid32_to_binary64", 1, "0x9871b2b3", 0xb65b39ab78718832, 0x20),
            TestCase("bid32_to_binary64", 1, "0x9c37083b", 0xb7f3a2d93e5ad254, 0x20),
            TestCase("bid32_to_binary64", 1, "0xa082ffad", 0xb98fe3544145e9d9, 0x20),
            TestCase("bid32_to_binary64", 1, "0xa4033b59", 0xbb047bf052eac348, 0x20),
            TestCase("bid32_to_binary64", 1, "0xabb057d9", 0xbe61025d42033847, 0x20),
            TestCase("bid32_to_binary64", 1, "0xaecd7c6d", 0xbfaa000000000000, 0x00),
            TestCase("bid32_to_binary64", 1, "0xaff9ff92", 0xc01ffb2b3461309d, 0x20),
            TestCase("bid32_to_binary64", 1, "0xb200000f", 0xbff8000000000000, 0x00),
            TestCase("bid32_to_binary64", 1, "0xb2800001", 0xbff0000000000000, 0x00),
            TestCase("bid32_to_binary64", 1, "0xb2800040", 0xc050000000000000, 0x00),
            TestCase("bid32_to_binary64", 1, "0xb28003e7", 0xc08f380000000000, 0x00),
            TestCase("bid32_to_binary64", 1, "0xb28003e8", 0xc08f400000000000, 0x00),
            TestCase("bid32_to_binary64", 1, "0xb3a8f5c2", 0xc1afffff90000000, 0x00),
            TestCase("bid32_to_binary64", 1, "0xbb2e1de6", 0xc4cffffcd7edc456, 0x20),
            TestCase("bid32_to_binary64", 1, "0xbedc99f0", 0xc6532645e1ba93f0, 0x20),
            TestCase("bid32_to_binary64", 1, "0xc7140a10", 0xc9b70105df3d47cc, 0x20),
            TestCase("bid32_to_binary64", 1, "0xcafda8f2", 0xcb557eb8ad52a5c9, 0x20),
            TestCase("bid32_to_binary64", 1, "0xce980326", 0xccd87b809b494508, 0x20),
            TestCase("bid32_to_binary64", 1, "0xdaa9d03d", 0xd1e1a1d9135cca54, 0x20),
            TestCase("bid32_to_binary64", 1, "0xe9edd92d", 0xbcd0bf1a651525e8, 0x20),
            TestCase("bid32_to_binary64", 1, "0xedc97056", 0xc33ffffdd85fdc00, 0x00),
            TestCase("bid32_to_binary64", 1, "0xf0c9732f", 0xc83a78ce1807f5f9, 0x20),
            TestCase("bid32_to_binary64", 1, "0xf4b6e7ac", 0xceaca897d8932bcf, 0x20),
            TestCase("bid32_to_binary64", 1, "0xf58a9968", 0xd01f60b4a930ae18, 0x20),
            TestCase("bid32_to_binary64", 1, "0xf7f8967f", 0xd412ba093e5c6115, 0x20),
            TestCase("bid32_to_binary64", 1, "0xf8000000", 0xfff0000000000000, 0x00),
            TestCase("bid32_to_binary64", 2, "0x00000001", 0x2af665bf1d3e6a8d, 0x20),
            TestCase("bid32_to_binary64", 2, "0x010bcb3b", 0x2c99cbd06456ee4f, 0x20),
            TestCase("bid32_to_binary64", 2, "0x03000001", 0x2c355c2076bf9a56, 0x20),
            TestCase("bid32_to_binary64", 2, "0x03800001", 0x2c6ab328946f80eb, 0x20),
            TestCase("bid32_to_binary64", 2, "0x04f08deb", 0x2e425799582d3bbe, 0x20),
            TestCase("bid32_to_binary64", 2, "0x0881888c", 0x2f87d4b57562e711, 0x20),
            TestCase("bid32_to_binary64", 2, "0x0c8a06d8", 0x315d0681489839d6, 0x20),
            TestCase("bid32_to_binary64", 2, "0x1082384c", 0x32e326cd14f71c24, 0x20),
            TestCase("bid32_to_binary64", 2, "0x1489fdf7", 0x34b00e7db3b3f242, 0x20),
            TestCase("bid32_to_binary64", 2, "0x1871b2b3", 0x365b39ab78718832, 0x20),
            TestCase("bid32_to_binary64", 2, "0x1c37083b", 0x37f3a2d93e5ad254, 0x20),
            TestCase("bid32_to_binary64", 2, "0x2082ffad", 0x398fe3544145e9d9, 0x20),
            TestCase("bid32_to_binary64", 2, "0x24033b59", 0x3b047bf052eac348, 0x20),
            TestCase("bid32_to_binary64", 2, "0x2bb057d9", 0x3e61025d42033847, 0x20),
            TestCase("bid32_to_binary64", 2, "0x2ecd7c6d", 0x3faa000000000000, 0x00),
            TestCase("bid32_to_binary64", 2, "0x2ff9ff92", 0x401ffb2b3461309d, 0x20),
            TestCase("bid32_to_binary64", 2, "0x3200000f", 0x3ff8000000000000, 0x00),
            TestCase("bid32_to_binary64", 2, "0x32800000", 0x0000000000000000, 0x00),
            TestCase("bid32_to_binary64", 2, "0x32800001", 0x3ff0000000000000, 0x00),
            TestCase("bid32_to_binary64", 2, "0x32800040", 0x4050000000000000, 0x00),
            TestCase("bid32_to_binary64", 2, "0x328003e7", 0x408f380000000000, 0x00),
            TestCase("bid32_to_binary64", 2, "0x328003e8", 0x408f400000000000, 0x00),
            TestCase("bid32_to_binary64", 2, "0x33a8f5c2", 0x41afffff90000000, 0x00),
            TestCase("bid32_to_binary64", 2, "0x3b2e1de6", 0x44cffffcd7edc456, 0x20),
            TestCase("bid32_to_binary64", 2, "0x3edc99f0", 0x46532645e1ba93f0, 0x20),
            TestCase("bid32_to_binary64", 2, "0x47140a10", 0x49b70105df3d47cc, 0x20),
            TestCase("bid32_to_binary64", 2, "0x4afda8f2", 0x4b557eb8ad52a5c9, 0x20),
            TestCase("bid32_to_binary64", 2, "0x4e980326", 0x4cd87b809b494508, 0x20),
            TestCase("bid32_to_binary64", 2, "0x5aa9d03d", 0x51e1a1d9135cca54, 0x20),
            TestCase("bid32_to_binary64", 2, "0x69edd92d", 0x3cd0bf1a651525e8, 0x20),
            TestCase("bid32_to_binary64", 2, "0x6dc97056", 0x433ffffdd85fdc00, 0x00),
            TestCase("bid32_to_binary64", 2, "0x70c9732f", 0x483a78ce1807f5f9, 0x20),
            TestCase("bid32_to_binary64", 2, "0x74b6e7ac", 0x4eaca897d8932bcf, 0x20),
            TestCase("bid32_to_binary64", 2, "0x758a9968", 0x501f60b4a930ae18, 0x20),
            TestCase("bid32_to_binary64", 2, "0x77f8967f", 0x5412ba093e5c6115, 0x20),
            TestCase("bid32_to_binary64", 2, "0x78000000", 0x7ff0000000000000, 0x00),
            TestCase("bid32_to_binary64", 2, "0x80000001", 0xaaf665bf1d3e6a8c, 0x20),
            TestCase("bid32_to_binary64", 2, "0x810bcb3b", 0xac99cbd06456ee4e, 0x20),
            TestCase("bid32_to_binary64", 2, "0x83000001", 0xac355c2076bf9a55, 0x20),
            TestCase("bid32_to_binary64", 2, "0x83800001", 0xac6ab328946f80ea, 0x20),
            TestCase("bid32_to_binary64", 2, "0x84f08deb", 0xae425799582d3bbd, 0x20),
            TestCase("bid32_to_binary64", 2, "0x8881888c", 0xaf87d4b57562e710, 0x20),
            TestCase("bid32_to_binary64", 2, "0x8c8a06d8", 0xb15d0681489839d5, 0x20),
            TestCase("bid32_to_binary64", 2, "0x9082384c", 0xb2e326cd14f71c23, 0x20),
            TestCase("bid32_to_binary64", 2, "0x9489fdf7", 0xb4b00e7db3b3f241, 0x20),
            TestCase("bid32_to_binary64", 2, "0x9871b2b3", 0xb65b39ab78718831, 0x20),
            TestCase("bid32_to_binary64", 2, "0x9c37083b", 0xb7f3a2d93e5ad253, 0x20),
            TestCase("bid32_to_binary64", 2, "0xa082ffad", 0xb98fe3544145e9d8, 0x20),
            TestCase("bid32_to_binary64", 2, "0xa4033b59", 0xbb047bf052eac347, 0x20),
            TestCase("bid32_to_binary64", 2, "0xabb057d9", 0xbe61025d42033846, 0x20),
            TestCase("bid32_to_binary64", 2, "0xaecd7c6d", 0xbfaa000000000000, 0x00),
            TestCase("bid32_to_binary64", 2, "0xaff9ff92", 0xc01ffb2b3461309c, 0x20),
            TestCase("bid32_to_binary64", 2, "0xb200000f", 0xbff8000000000000, 0x00),
            TestCase("bid32_to_binary64", 2, "0xb2800001", 0xbff0000000000000, 0x00),
            TestCase("bid32_to_binary64", 2, "0xb2800040", 0xc050000000000000, 0x00),
            TestCase("bid32_to_binary64", 2, "0xb28003e7", 0xc08f380000000000, 0x00),
            TestCase("bid32_to_binary64", 2, "0xb28003e8", 0xc08f400000000000, 0x00),
            TestCase("bid32_to_binary64", 2, "0xb3a8f5c2", 0xc1afffff90000000, 0x00),
            TestCase("bid32_to_binary64", 2, "0xbb2e1de6", 0xc4cffffcd7edc455, 0x20),
            TestCase("bid32_to_binary64", 2, "0xbedc99f0", 0xc6532645e1ba93ef, 0x20),
            TestCase("bid32_to_binary64", 2, "0xc7140a10", 0xc9b70105df3d47cb, 0x20),
            TestCase("bid32_to_binary64", 2, "0xcafda8f2", 0xcb557eb8ad52a5c8, 0x20),
            TestCase("bid32_to_binary64", 2, "0xce980326", 0xccd87b809b494507, 0x20),
            TestCase("bid32_to_binary64", 2, "0xdaa9d03d", 0xd1e1a1d9135cca53, 0x20),
            TestCase("bid32_to_binary64", 2, "0xe9edd92d", 0xbcd0bf1a651525e7, 0x20),
            TestCase("bid32_to_binary64", 2, "0xedc97056", 0xc33ffffdd85fdc00, 0x00),
            TestCase("bid32_to_binary64", 2, "0xf0c9732f", 0xc83a78ce1807f5f8, 0x20),
            TestCase("bid32_to_binary64", 2, "0xf4b6e7ac", 0xceaca897d8932bce, 0x20),
            TestCase("bid32_to_binary64", 2, "0xf58a9968", 0xd01f60b4a930ae17, 0x20),
            TestCase("bid32_to_binary64", 2, "0xf7f8967f", 0xd412ba093e5c6114, 0x20),
            TestCase("bid32_to_binary64", 2, "0xf8000000", 0xfff0000000000000, 0x00),
            TestCase("bid32_to_binary64", 3, "0x00000001", 0x2af665bf1d3e6a8c, 0x20),
            TestCase("bid32_to_binary64", 3, "0x010bcb3b", 0x2c99cbd06456ee4e, 0x20),
            TestCase("bid32_to_binary64", 3, "0x03000001", 0x2c355c2076bf9a55, 0x20),
            TestCase("bid32_to_binary64", 3, "0x03800001", 0x2c6ab328946f80ea, 0x20),
            TestCase("bid32_to_binary64", 3, "0x04f08deb", 0x2e425799582d3bbd, 0x20),
            TestCase("bid32_to_binary64", 3, "0x0881888c", 0x2f87d4b57562e710, 0x20),
            TestCase("bid32_to_binary64", 3, "0x0c8a06d8", 0x315d0681489839d5, 0x20),
            TestCase("bid32_to_binary64", 3, "0x1082384c", 0x32e326cd14f71c23, 0x20),
            TestCase("bid32_to_binary64", 3, "0x1489fdf7", 0x34b00e7db3b3f241, 0x20),
            TestCase("bid32_to_binary64", 3, "0x1871b2b3", 0x365b39ab78718831, 0x20),
            TestCase("bid32_to_binary64", 3, "0x1c37083b", 0x37f3a2d93e5ad253, 0x20),
            TestCase("bid32_to_binary64", 3, "0x2082ffad", 0x398fe3544145e9d8, 0x20),
            TestCase("bid32_to_binary64", 3, "0x24033b59", 0x3b047bf052eac347, 0x20),
            TestCase("bid32_to_binary64", 3, "0x2bb057d9", 0x3e61025d42033846, 0x20),
            TestCase("bid32_to_binary64", 3, "0x2ecd7c6d", 0x3faa000000000000, 0x00),
            TestCase("bid32_to_binary64", 3, "0x2ff9ff92", 0x401ffb2b3461309c, 0x20),
            TestCase("bid32_to_binary64", 3, "0x3200000f", 0x3ff8000000000000, 0x00),
            TestCase("bid32_to_binary64", 3, "0x32800000", 0x0000000000000000, 0x00),
            TestCase("bid32_to_binary64", 3, "0x32800001", 0x3ff0000000000000, 0x00),
            TestCase("bid32_to_binary64", 3, "0x32800040", 0x4050000000000000, 0x00),
            TestCase("bid32_to_binary64", 3, "0x328003e7", 0x408f380000000000, 0x00),
            TestCase("bid32_to_binary64", 3, "0x328003e8", 0x408f400000000000, 0x00),
            TestCase("bid32_to_binary64", 3, "0x33a8f5c2", 0x41afffff90000000, 0x00),
            TestCase("bid32_to_binary64", 3, "0x3b2e1de6", 0x44cffffcd7edc455, 0x20),
            TestCase("bid32_to_binary64", 3, "0x3edc99f0", 0x46532645e1ba93ef, 0x20),
            TestCase("bid32_to_binary64", 3, "0x47140a10", 0x49b70105df3d47cb, 0x20),
            TestCase("bid32_to_binary64", 3, "0x4afda8f2", 0x4b557eb8ad52a5c8, 0x20),
            TestCase("bid32_to_binary64", 3, "0x4e980326", 0x4cd87b809b494507, 0x20),
            TestCase("bid32_to_binary64", 3, "0x5aa9d03d", 0x51e1a1d9135cca53, 0x20),
            TestCase("bid32_to_binary64", 3, "0x69edd92d", 0x3cd0bf1a651525e7, 0x20),
            TestCase("bid32_to_binary64", 3, "0x6dc97056", 0x433ffffdd85fdc00, 0x00),
            TestCase("bid32_to_binary64", 3, "0x70c9732f", 0x483a78ce1807f5f8, 0x20),
            TestCase("bid32_to_binary64", 3, "0x74b6e7ac", 0x4eaca897d8932bce, 0x20),
            TestCase("bid32_to_binary64", 3, "0x758a9968", 0x501f60b4a930ae17, 0x20),
            TestCase("bid32_to_binary64", 3, "0x77f8967f", 0x5412ba093e5c6114, 0x20),
            TestCase("bid32_to_binary64", 3, "0x78000000", 0x7ff0000000000000, 0x00),
            TestCase("bid32_to_binary64", 3, "0x80000001", 0xaaf665bf1d3e6a8c, 0x20),
            TestCase("bid32_to_binary64", 3, "0x810bcb3b", 0xac99cbd06456ee4e, 0x20),
            TestCase("bid32_to_binary64", 3, "0x83000001", 0xac355c2076bf9a55, 0x20),
            TestCase("bid32_to_binary64", 3, "0x83800001", 0xac6ab328946f80ea, 0x20),
            TestCase("bid32_to_binary64", 3, "0x84f08deb", 0xae425799582d3bbd, 0x20),
            TestCase("bid32_to_binary64", 3, "0x8881888c", 0xaf87d4b57562e710, 0x20),
            TestCase("bid32_to_binary64", 3, "0x8c8a06d8", 0xb15d0681489839d5, 0x20),
            TestCase("bid32_to_binary64", 3, "0x9082384c", 0xb2e326cd14f71c23, 0x20),
            TestCase("bid32_to_binary64", 3, "0x9489fdf7", 0xb4b00e7db3b3f241, 0x20),
            TestCase("bid32_to_binary64", 3, "0x9871b2b3", 0xb65b39ab78718831, 0x20),
            TestCase("bid32_to_binary64", 3, "0x9c37083b", 0xb7f3a2d93e5ad253, 0x20),
            TestCase("bid32_to_binary64", 3, "0xa082ffad", 0xb98fe3544145e9d8, 0x20),
            TestCase("bid32_to_binary64", 3, "0xa4033b59", 0xbb047bf052eac347, 0x20),
            TestCase("bid32_to_binary64", 3, "0xabb057d9", 0xbe61025d42033846, 0x20),
            TestCase("bid32_to_binary64", 3, "0xaecd7c6d", 0xbfaa000000000000, 0x00),
            TestCase("bid32_to_binary64", 3, "0xaff9ff92", 0xc01ffb2b3461309c, 0x20),
            TestCase("bid32_to_binary64", 3, "0xb200000f", 0xbff8000000000000, 0x00),
            TestCase("bid32_to_binary64", 3, "0xb2800001", 0xbff0000000000000, 0x00),
            TestCase("bid32_to_binary64", 3, "0xb2800040", 0xc050000000000000, 0x00),
            TestCase("bid32_to_binary64", 3, "0xb28003e7", 0xc08f380000000000, 0x00),
            TestCase("bid32_to_binary64", 3, "0xb28003e8", 0xc08f400000000000, 0x00),
            TestCase("bid32_to_binary64", 3, "0xb3a8f5c2", 0xc1afffff90000000, 0x00),
            TestCase("bid32_to_binary64", 3, "0xbb2e1de6", 0xc4cffffcd7edc455, 0x20),
            TestCase("bid32_to_binary64", 3, "0xbedc99f0", 0xc6532645e1ba93ef, 0x20),
            TestCase("bid32_to_binary64", 3, "0xc7140a10", 0xc9b70105df3d47cb, 0x20),
            TestCase("bid32_to_binary64", 3, "0xcafda8f2", 0xcb557eb8ad52a5c8, 0x20),
            TestCase("bid32_to_binary64", 3, "0xce980326", 0xccd87b809b494507, 0x20),
            TestCase("bid32_to_binary64", 3, "0xdaa9d03d", 0xd1e1a1d9135cca53, 0x20),
            TestCase("bid32_to_binary64", 3, "0xe9edd92d", 0xbcd0bf1a651525e7, 0x20),
            TestCase("bid32_to_binary64", 3, "0xedc97056", 0xc33ffffdd85fdc00, 0x00),
            TestCase("bid32_to_binary64", 3, "0xf0c9732f", 0xc83a78ce1807f5f8, 0x20),
            TestCase("bid32_to_binary64", 3, "0xf4b6e7ac", 0xceaca897d8932bce, 0x20),
            TestCase("bid32_to_binary64", 3, "0xf58a9968", 0xd01f60b4a930ae17, 0x20),
            TestCase("bid32_to_binary64", 3, "0xf7f8967f", 0xd412ba093e5c6114, 0x20),
            TestCase("bid32_to_binary64", 3, "0xf8000000", 0xfff0000000000000, 0x00),
            TestCase("bid32_to_binary64", 4, "0x00000001", 0x2af665bf1d3e6a8d, 0x20),
            TestCase("bid32_to_binary64", 4, "0x010bcb3b", 0x2c99cbd06456ee4e, 0x20),
            TestCase("bid32_to_binary64", 4, "0x03000001", 0x2c355c2076bf9a55, 0x20),
            TestCase("bid32_to_binary64", 4, "0x03800001", 0x2c6ab328946f80ea, 0x20),
            TestCase("bid32_to_binary64", 4, "0x04f08deb", 0x2e425799582d3bbe, 0x20),
            TestCase("bid32_to_binary64", 4, "0x0881888c", 0x2f87d4b57562e710, 0x20),
            TestCase("bid32_to_binary64", 4, "0x0c8a06d8", 0x315d0681489839d5, 0x20),
            TestCase("bid32_to_binary64", 4, "0x1082384c", 0x32e326cd14f71c23, 0x20),
            TestCase("bid32_to_binary64", 4, "0x1489fdf7", 0x34b00e7db3b3f242, 0x20),
            TestCase("bid32_to_binary64", 4, "0x1871b2b3", 0x365b39ab78718832, 0x20),
            TestCase("bid32_to_binary64", 4, "0x1c37083b", 0x37f3a2d93e5ad254, 0x20),
            TestCase("bid32_to_binary64", 4, "0x2082ffad", 0x398fe3544145e9d8, 0x20),
            TestCase("bid32_to_binary64", 4, "0x24033b59", 0x3b047bf052eac347, 0x20),
            TestCase("bid32_to_binary64", 4, "0x2bb057d9", 0x3e61025d42033846, 0x20),
            TestCase("bid32_to_binary64", 4, "0x2ecd7c6d", 0x3faa000000000000, 0x00),
            TestCase("bid32_to_binary64", 4, "0x2ff9ff92", 0x401ffb2b3461309c, 0x20),
            TestCase("bid32_to_binary64", 4, "0x3200000f", 0x3ff8000000000000, 0x00),
            TestCase("bid32_to_binary64", 4, "0x32800000", 0x0000000000000000, 0x00),
            TestCase("bid32_to_binary64", 4, "0x32800001", 0x3ff0000000000000, 0x00),
            TestCase("bid32_to_binary64", 4, "0x32800040", 0x4050000000000000, 0x00),
            TestCase("bid32_to_binary64", 4, "0x328003e7", 0x408f380000000000, 0x00),
            TestCase("bid32_to_binary64", 4, "0x328003e8", 0x408f400000000000, 0x00),
            TestCase("bid32_to_binary64", 4, "0x33a8f5c2", 0x41afffff90000000, 0x00),
            TestCase("bid32_to_binary64", 4, "0x3b2e1de6", 0x44cffffcd7edc456, 0x20),
            TestCase("bid32_to_binary64", 4, "0x3edc99f0", 0x46532645e1ba93f0, 0x20),
            TestCase("bid32_to_binary64", 4, "0x47140a10", 0x49b70105df3d47cb, 0x20),
            TestCase("bid32_to_binary64", 4, "0x4afda8f2", 0x4b557eb8ad52a5c9, 0x20),
            TestCase("bid32_to_binary64", 4, "0x4e980326", 0x4cd87b809b494507, 0x20),
            TestCase("bid32_to_binary64", 4, "0x5aa9d03d", 0x51e1a1d9135cca53, 0x20),
            TestCase("bid32_to_binary64", 4, "0x69edd92d", 0x3cd0bf1a651525e8, 0x20),
            TestCase("bid32_to_binary64", 4, "0x6dc97056", 0x433ffffdd85fdc00, 0x00),
            TestCase("bid32_to_binary64", 4, "0x70c9732f", 0x483a78ce1807f5f8, 0x20),
            TestCase("bid32_to_binary64", 4, "0x74b6e7ac", 0x4eaca897d8932bce, 0x20),
            TestCase("bid32_to_binary64", 4, "0x758a9968", 0x501f60b4a930ae18, 0x20),
            TestCase("bid32_to_binary64", 4, "0x77f8967f", 0x5412ba093e5c6114, 0x20),
            TestCase("bid32_to_binary64", 4, "0x78000000", 0x7ff0000000000000, 0x00),
            TestCase("bid32_to_binary64", 4, "0x80000001", 0xaaf665bf1d3e6a8d, 0x20),
            TestCase("bid32_to_binary64", 4, "0x810bcb3b", 0xac99cbd06456ee4e, 0x20),
            TestCase("bid32_to_binary64", 4, "0x83000001", 0xac355c2076bf9a55, 0x20),
            TestCase("bid32_to_binary64", 4, "0x83800001", 0xac6ab328946f80ea, 0x20),
            TestCase("bid32_to_binary64", 4, "0x84f08deb", 0xae425799582d3bbe, 0x20),
            TestCase("bid32_to_binary64", 4, "0x8881888c", 0xaf87d4b57562e710, 0x20),
            TestCase("bid32_to_binary64", 4, "0x8c8a06d8", 0xb15d0681489839d5, 0x20),
            TestCase("bid32_to_binary64", 4, "0x9082384c", 0xb2e326cd14f71c23, 0x20),
            TestCase("bid32_to_binary64", 4, "0x9489fdf7", 0xb4b00e7db3b3f242, 0x20),
            TestCase("bid32_to_binary64", 4, "0x9871b2b3", 0xb65b39ab78718832, 0x20),
            TestCase("bid32_to_binary64", 4, "0x9c37083b", 0xb7f3a2d93e5ad254, 0x20),
            TestCase("bid32_to_binary64", 4, "0xa082ffad", 0xb98fe3544145e9d8, 0x20),
            TestCase("bid32_to_binary64", 4, "0xa4033b59", 0xbb047bf052eac347, 0x20),
            TestCase("bid32_to_binary64", 4, "0xabb057d9", 0xbe61025d42033846, 0x20),
            TestCase("bid32_to_binary64", 4, "0xaecd7c6d", 0xbfaa000000000000, 0x00),
            TestCase("bid32_to_binary64", 4, "0xaff9ff92", 0xc01ffb2b3461309c, 0x20),
            TestCase("bid32_to_binary64", 4, "0xb200000f", 0xbff8000000000000, 0x00),
            TestCase("bid32_to_binary64", 4, "0xb2800001", 0xbff0000000000000, 0x00),
            TestCase("bid32_to_binary64", 4, "0xb2800040", 0xc050000000000000, 0x00),
            TestCase("bid32_to_binary64", 4, "0xb28003e7", 0xc08f380000000000, 0x00),
            TestCase("bid32_to_binary64", 4, "0xb28003e8", 0xc08f400000000000, 0x00),
            TestCase("bid32_to_binary64", 4, "0xb3a8f5c2", 0xc1afffff90000000, 0x00),
            TestCase("bid32_to_binary64", 4, "0xbb2e1de6", 0xc4cffffcd7edc456, 0x20),
            TestCase("bid32_to_binary64", 4, "0xbedc99f0", 0xc6532645e1ba93f0, 0x20),
            TestCase("bid32_to_binary64", 4, "0xc7140a10", 0xc9b70105df3d47cb, 0x20),
            TestCase("bid32_to_binary64", 4, "0xcafda8f2", 0xcb557eb8ad52a5c9, 0x20),
            TestCase("bid32_to_binary64", 4, "0xce980326", 0xccd87b809b494507, 0x20),
            TestCase("bid32_to_binary64", 4, "0xdaa9d03d", 0xd1e1a1d9135cca53, 0x20),
            TestCase("bid32_to_binary64", 4, "0xe9edd92d", 0xbcd0bf1a651525e8, 0x20),
            TestCase("bid32_to_binary64", 4, "0xedc97056", 0xc33ffffdd85fdc00, 0x00),
            TestCase("bid32_to_binary64", 4, "0xf0c9732f", 0xc83a78ce1807f5f8, 0x20),
            TestCase("bid32_to_binary64", 4, "0xf4b6e7ac", 0xceaca897d8932bce, 0x20),
            TestCase("bid32_to_binary64", 4, "0xf58a9968", 0xd01f60b4a930ae18, 0x20),
            TestCase("bid32_to_binary64", 4, "0xf7f8967f", 0xd412ba093e5c6114, 0x20),
            TestCase("bid32_to_binary64", 4, "0xf8000000", 0xfff0000000000000, 0x00),
            
            TestCase("bid32_to_int64_int", 0, "0xb348af10", UInt64(bitPattern: -47634080), 0x00),
            TestCase("bid32_to_int64_int", 0, "0xb8fd0b20", UInt64(bitPattern: -8194848000000000000), 0x00),
            TestCase("bid32_to_int64_int", 0, "0xb118546b", UInt64(bitPattern: -1594), 0x00),
            TestCase("bid32_to_int64_int", 0, "0xb2e373ef", UInt64(bitPattern: -6517743), 0x00),
            TestCase("bid32_to_int64_int", 0, "0x6e37ff6b", UInt64(bitPattern: -9223372036854775808), 0x01),
            TestCase("bid32_to_int64_int", 0, "0xee34dc83", UInt64(bitPattern: -9223372036854775808), 0x01),
                     
            TestCase("bid32_to_uint64_int", 0, "0x2F4C4B40", 0, 0x00), // 0.5                           // 1
            TestCase("bid32_to_uint64_int", 0, "0x2F8F4240", 1, 0x00), // 1
            TestCase("bid32_to_uint64_int", 0, "0x2F96E360", 1, 0x00), // 1.5
            TestCase("bid32_to_uint64_int", 0, "0x30ADC6C0", 300, 0x00), // 300
            TestCase("bid32_to_uint64_int", 0, "0x30ADDA48", 300, 0x00), // 300.5
            TestCase("bid32_to_uint64_int", 0, "0x310003E7", 0, 0x00), // 0.999
            TestCase("bid32_to_uint64_int", 0, "0x32000005", 0, 0x00), // 0.5
            TestCase("bid32_to_uint64_int", 0, "0x3200000F", 1, 0x00), // 1.5
            TestCase("bid32_to_uint64_int", 0, "0x32000BBD", 300, 0x00), // 300.5
            TestCase("bid32_to_uint64_int", 0, "0x32800001", 1, 0x00), // 1                             // 10
            TestCase("bid32_to_uint64_int", 0, "0x33800003", 300, 0x00), // 300
            TestCase("bid32_to_uint64_int", 0, "0x343D0900", 4000000000, 0x00), // 4e9
            TestCase("bid32_to_uint64_int", 0, "0x344C4B40", 5000000000, 0x00), // 5e9
            TestCase("bid32_to_uint64_int", 0, "0x349E8480", 20000000000, 0x00), // 2e10
            TestCase("bid32_to_uint64_int", 0, "0x3635AFE5", 35184370000000, 0x00), // 2^45
            TestCase("bid32_to_uint64_int", 0, "0x37000004", 4000000000, 0x00), // 4e9
            TestCase("bid32_to_uint64_int", 0, "0x37000005", 5000000000, 0x00), // 5e9
            TestCase("bid32_to_uint64_int", 0, "0x371E8480", 2000000000000000, 0x00), // 2e15
            TestCase("bid32_to_uint64_int", 0, "0x37800002", 20000000000, 0x00), // 2e10
            TestCase("bid32_to_uint64_int", 0, "0x390F4240", 10000000000000000000, 0x00), // 1e19       // 20
            TestCase("bid32_to_uint64_int", 0, "0x3916E360", 15000000000000000000, 0x00), // 1.5e19
            TestCase("bid32_to_uint64_int", 0, "0x391C25C2", 18446740000000000000, 0x00), // 2^64
            TestCase("bid32_to_uint64_int", 0, "0x391E8480", 9223372036854775808, 0x01), // 2e19
            TestCase("bid32_to_uint64_int", 0, "0x392625A0", 9223372036854775808, 0x01), // 2.5e19
            TestCase("bid32_to_uint64_int", 0, "0x398F4240", 9223372036854775808, 0x01), // 1e20
            TestCase("bid32_to_uint64_int", 0, "0x3A000002", 2000000000000000, 0x00), // 2e15
            TestCase("bid32_to_uint64_int", 0, "0x3B80000F", 15000000000000000000, 0x00), // 1.5e19
            TestCase("bid32_to_uint64_int", 0, "0x3B800019", 9223372036854775808, 0x01), // 2.5e19
            TestCase("bid32_to_uint64_int", 0, "0x3C000001", 10000000000000000000, 0x00), // 1e19
            TestCase("bid32_to_uint64_int", 0, "0x3C000002", 9223372036854775808, 0x01), // 2e19        // 30
            TestCase("bid32_to_uint64_int", 0, "0x3C800001", 9223372036854775808, 0x01), // 1e20
            TestCase("bid32_to_uint64_int", 0, "0x6BD86F70", 0, 0x00), // 0.999
            TestCase("bid32_to_uint64_int", 0, "0x6CB89680", 0, 0x00),
            TestCase("bid32_to_uint64_int", 0, "0x6E2CBCCC", 9223372000000000000, 0x00), // 2^63
            TestCase("bid32_to_uint64_int", 0, "0x78000000", 9223372036854775808, 0x01),
            TestCase("bid32_to_uint64_int", 0, "0x7c000000", 9223372036854775808, 0x01),
            TestCase("bid32_to_uint64_int", 0, "0x7e000000", 9223372036854775808, 0x01),
            TestCase("bid32_to_uint64_int", 0, "9.223372E+18", 9223372000000000000, 0x00)               // 38
       ]
        
        var testID = 1
        var prevID = ""
        
        func checkValues(_ test: TestCase, _ x: UInt64, _ s: Status, _ msg: String) {
            let pass1 = test.res == x
            let pass2 = test.status == s
            XCTAssert(pass1, "Expected: " + msg)
            XCTAssert(pass2, "[\(test.status)] != [\(s)]")
            let pf = pass1 && pass2 ? "passed" : "failed"
            if verbose { print("Decimal32 test \(test.id)-\(testID) \(pf)") }
        }
        
        func checkValues(_ test: TestCase, _ x: UInt128, _ s: Status, _ msg: String) {
            let pass1 = test.reshi == x.hi && test.reslo == x.lo
            let pass2 = test.status == s
            XCTAssert(pass1, "Expected: " + msg)
            XCTAssert(pass2, "[\(test.status)] != [\(s)]")
            let pf = pass1 && pass2 ? "passed" : "failed"
            if verbose { print("Decimal32 test \(test.id)-\(testID) \(pf)") }
        }
        
        for test in testCases {
            Decimal32.rounding = test.roundMode; Decimal32.state = []
            if prevID != test.id { testID = 1; prevID = test.id; print() } // reset for each type of test
            
            switch test.id {
                case "bid32_from_string":
                    let t1 = Decimal32(stringLiteral: test.istr)
                    let dtest = Decimal32(raw:UInt32(test.res))
                    let error = String(format: "0x%08X[\(dtest)] != 0x%08X[\(t1)]", test.res, t1.x)
                    checkValues(test, UInt64(t1.x), Decimal32.state, error)
                case "bid32_to_binary64":
                    let t1 = Decimal32(stringLiteral: test.istr).double
                    let d1 = Double(bitPattern: test.res)
                    let error = "\(d1) != \(t1)"
                    checkValues(test, t1.bitPattern, Decimal32.state, error)
                case "bid32_to_int64_int":
                    let t1 = Decimal32(stringLiteral: test.istr)
                    let error = "\(test.res) != \(t1.int)"
                    checkValues(test, UInt64(bitPattern: Int64(t1.int)), Decimal32.state, error)
                case "bid32_to_uint64_int":
                    let t1 = Decimal32(stringLiteral: test.istr)
                    let error = "\(test.res) != \(t1.uint)"
                    checkValues(test, UInt64(t1.uint), Decimal32.state, error)
                case "bid32_negate":
                    var t1 = Decimal32(stringLiteral: test.istr); t1.negate()
                    let dtest = Decimal32(raw:UInt32(test.res))
                    let error = String(format: "0x%08X[\(dtest)] != 0x%08X[\(t1)]", test.res, t1.x)
                    checkValues(test, UInt64(t1.x), Decimal32.state, error)
                case "bid32_to_bid128":
                    let t1 = Decimal32(stringLiteral: test.istr)
                    let b128 = t1.decimal128
                    let d128 = Decimal128(raw: UInt128(upper: test.reshi, lower: test.reslo))
                    let error = String(format: "0x%08X%08X[\(d128)] != 0x%08X%08X[\(b128)]", test.reshi, test.reslo, b128.x.hi, b128.x.lo)
                    checkValues(test, b128.x, Decimal32.state, error)
                case "bid32_to_bid64":
                    let t1 = Decimal32(stringLiteral: test.istr)
                    let b64 = t1.decimal64.x
                    let error = "\(test.res) != \(b64)"
                    checkValues(test, b64, Decimal32.state, error)
                case "bid32_abs":
                    let t1 = Decimal32(stringLiteral: test.istr).magnitude
                    let state = Decimal32.state
                    let dtest = Decimal32(raw:UInt32(test.res))
                    let error = String(format: "0x%08X[\(dtest)] != 0x%08X[\(t1)]", test.res, t1.x)
                    checkValues(test, UInt64(t1.x), state, error)
                case "bid32_isCanonical", "bid32_isFinite", "bid32_isInf", "bid32_isNaN", "bid32_isNormal",
                    "bid32_isSignaling", "bid32_isSigned", "bid32_isSubnormal", "bid32_isZero":
                    let t1 = Decimal32(stringLiteral: test.istr)
                    var flag = 0
                    if test.id.hasSuffix("isCanonical") {
                        flag = t1.isCanonical ? 1 : 0
                    } else if test.id.hasSuffix("isFinite") {
                        flag = t1.isFinite ? 1 : 0
                    } else if test.id.hasSuffix("isInf") {
                        flag = t1.isInfinite ? 1 : 0
                    } else if test.id.hasSuffix("isNaN") {
                        flag = t1.isNaN ? 1 : 0
                    } else if test.id.hasSuffix("isNormal") {
                        flag = t1.isNormal ? 1 : 0
                    } else if test.id.hasSuffix("isSignaling") {
                        flag = t1.isSignalingNaN ? 1 : 0
                    } else if test.id.hasSuffix("isSigned") {
                        flag = t1.isSignMinus ? 1 : 0
                    } else if test.id.hasSuffix("isSubnormal") {
                        flag = t1.isSubnormal ? 1 : 0
                    } else if test.id.hasSuffix("isZero") {
                        flag = t1.isZero ? 1 : 0
                    }
                    checkValues(test, UInt64(flag), Decimal32.state, "\(test.res) != \(flag)")
                case "bid32_add", "bid32_div", "bid32_mul":
                    let t1 = Decimal32(stringLiteral: test.istr)
                    let t2 = Decimal32(stringLiteral: test.istr2)
                    let res: Decimal32
                    if test.id.hasSuffix("add") {
                        res = t1 + t2
                    } else if test.id.hasSuffix("mul") {
                        res = t1 * t2
                    } else {
                        if testID == 37 {
                            print(t1, t2)
                        }
                        res = t1 / t2
                    }
                    let dtest = Decimal32(raw:UInt32(test.res))
                    let error = String(format: "Expected: 0x%08X[\(dtest)] != 0x%08X[\(res)]", test.res, res.x)
                    checkValues(test, UInt64(res.x), Decimal32.state, error)
                default:
                    XCTAssert(false, "Unknown test identifier: \(test.id)")
            }
            testID += 1
        }
        
        // back to default rounding mode
        Decimal32.rounding = .toNearestOrEven
        let s = "123456789"
        let y1 = Decimal32(stringLiteral: s); XCTAssert(y1.description == "1.234568e+8")
        print("\(s) -> \(y1)")
        
        let y = Decimal32(stringLiteral: "234.5"); XCTAssert(y.description == "234.5")
        let x = Decimal32(stringLiteral: "345.5"); XCTAssert(x.description == "345.5")
        
        let n = UInt32(0xA23003D0)
        var a = Decimal32(dpd32: n); XCTAssert(a.description == "-7.50")
        print(a, a.dpd32 == n ? "a = n" : "a != n"); XCTAssert(a.dpd32 == n)
        
        print("\(x) -> digits = \(x.significandDigitCount), bcd = \(x.significandDigits)")
        XCTAssert(x.significandDigitCount == 4 && x.significandDigits == [3, 4, 5, 5])
        print("\(y) -> digits = \(y.significandDigitCount), bcd = \(y.significandDigits)")
        XCTAssert(y.significandDigitCount == 4 && y.significandDigits == [2, 3, 4, 5])
        
        print(x, y, x*y, y/x, x.int, y.int, x.decade, y.decade)
        print(x.significand, x.exponent, y.significand, y.exponent)
        var b = Decimal32.leastNormalMagnitude
        print(Decimal32.greatestFiniteMagnitude, b, Decimal32.leastNonzeroMagnitude)
        
        let bias = Decimal32.exponentBias // bias == 101
        print(bias, Decimal32.greatestFiniteMagnitude.exponent); XCTAssert(bias == 101)
        XCTAssert(Decimal32.greatestFiniteMagnitude.exponent == 96)
        print(Decimal32.leastNormalMagnitude.exponent);
        XCTAssert(Decimal32.leastNormalMagnitude.exponent == -95)
        
        a = "-21.5"; b = "305.15"
        let c = Decimal32(signOf: a, magnitudeOf: b)
        print(c); XCTAssert((-b) == c)
        
        a = Decimal32(sign: .plus, exponentBitPattern: UInt32(bias), significandDigits: [1,2,3,4])
        print(a); XCTAssert(a.description == "1234")
        
        a = Decimal32.random(in: 1..<1000)
        print(a); XCTAssert(a >= Decimal32(1) && a < Decimal32(1000))
        
        var numbers : [Decimal32] = [2.5, 21.25, 3.0, .nan, -9.5]
        let ordered : [Decimal32] = [-9.5, 2.5, 3.0, 21.25, .nan]
        //var numbers2 = [2.5, 21.25, 3.0, .nan, -9.5]
        numbers.sort { !$1.isTotallyOrdered(belowOrEqualTo: $0) }
        print(numbers)
        XCTAssert(ordered.description == numbers.description)
        // Prints "[-9.5, 2.5, 3.0, 21.25, nan]"
        
        print("Decimal32.zero =", Decimal32.zero); XCTAssert(Decimal32.zero.description == "0")
        print("Decimal32.pi =", Decimal32.pi); XCTAssert(Decimal32.pi.description == "3.141593")
        print("Decimal32.nan =", Decimal32.nan); XCTAssert(Decimal32.nan.description == "NaN")
        print("Decimal32.quietNaN =", Decimal32.quietNaN); XCTAssert(Decimal32.quietNaN.description == "NaN")
        print("Decimal32.signalingNaN =", Decimal32.signalingNaN); XCTAssert(Decimal32.signalingNaN.description == "SNaN")
        print("Decimal32.infinity =", Decimal32.infinity); XCTAssert(Decimal32.infinity.description == "Inf")
        
        var a1 = Decimal32("8.625"); let b1 = Decimal32("0.75")
        let rem = a1.remainder(dividingBy: b1)
        print("\(a1).formRemainder(dividingBy: \(b1) = ", rem)
        XCTAssert(rem == Decimal32("-0.375"))
        a1 = Decimal32("8.625")
        let q = (a1/b1).rounded(.towardZero); print(q)
        a1 = a1 - q * b1
        print("\(a1)")
        
        // Equivalent to the C 'round' function:
        let w = Decimal32(6.5)
        print(w.rounded(.toNearestOrAwayFromZero))
        XCTAssert(w.rounded(.toNearestOrAwayFromZero) == Decimal32(7)) // w == 7.0
        
        // Equivalent to the C 'trunc' function:
        print(w.rounded(.towardZero))
        XCTAssert(w.rounded(.towardZero) == Decimal32(6)) // x == 6.0
        
        // Equivalent to the C 'ceil' function:
        print(w.rounded(.up))
        XCTAssert(w.rounded(.up) == Decimal32(7)) // w == 7.0
        
        // Equivalent to the C 'floor' function:
        print(w.rounded(.down))
        XCTAssert(w.rounded(.down) == Decimal32(6)) // x == 6.0
    }
    
    func testDecimal64() throws {
        let s = "123456789012345678"
        let y1 = Decimal64(stringLiteral: s); XCTAssert(y1.description == "1.234567890123457e+17")
        print("\(s) -> \(y1)")
        
        print("Decimal64.zero =", Decimal64.zero); XCTAssert(Decimal64.zero.description == "0")
        print("Decimal64.pi =", Decimal64.pi); XCTAssert(Decimal64.pi.description == "3.141592653589793")
        print("Decimal64.nan =", Decimal64.nan); XCTAssert(Decimal64.nan.description == "NaN")
        print("Decimal64.quietNaN =", Decimal64.quietNaN); XCTAssert(Decimal64.quietNaN.description == "NaN")
        print("Decimal64.signalingNaN =", Decimal64.signalingNaN); XCTAssert(Decimal64.signalingNaN.description == "SNaN")
        print("Decimal64.infinity =", Decimal64.infinity); XCTAssert(Decimal64.infinity.description == "Inf")
        
        let n = UInt64(0xA2300000000003D0)
        let a = Decimal64(dpd64: n); XCTAssert(a.description == "-7.50")
        print(a, a.dpd64 == n ? "a = n" : "a != n"); XCTAssert(a.dpd64 == n)
    }
    
    func testDecimal128() throws {
        let s = "12345678901234567890.12345678901234567890"
        let y1 = Decimal128(stringLiteral: s); XCTAssert(y1.description == "12345678901234567890.12345678901235")
        print("\(s) -> \(y1)")
        
        print("Decimal128.zero =", Decimal128.zero); XCTAssert(Decimal128.zero.description == "0")
        print("Decimal128.pi =", Decimal128.pi); XCTAssert(Decimal128.pi.description == "3.141592653589793238462651973214093")
        print("Decimal128.nan =", Decimal128.nan); XCTAssert(Decimal128.nan.description == "NaN")
        print("Decimal128.quietNaN =", Decimal128.quietNaN); XCTAssert(Decimal128.quietNaN.description == "NaN")
        print("Decimal128.signalingNaN =", Decimal128.signalingNaN); XCTAssert(Decimal128.signalingNaN.description == "SNaN")
        print("Decimal128.infinity =", Decimal128.infinity); XCTAssert(Decimal128.infinity.description == "Inf")
        
        let n = UInt128(upper: 0xA207_8000_0000_0000, lower: 0x0000_0000_0000_03D0)
        let a = Decimal128(dpd128: n); XCTAssert(a.description == "-7.50")
        print(a, a.dpd128, a.dpd128 == n ? "a = n" : "a != n"); XCTAssert(a.dpd128 == n)
    }
    
    func testUInt128() throws {
        let y : UInt128 = "0xA207_8000_0000_0000_0000_0000_0000_03D0"
        let x : UInt128 = "1_000_000_000_000_000_000_000_000_000_000_000"
        let div : UInt128 = 215373
        let rem : UInt128 = "877_543_595_382_617_630_722_487_884_973_008"
        XCTAssert(x.description == "1000000000000000000000000000000000")
        XCTAssert(y.description == "215373877543595382617630722487884973008")
        XCTAssert(UInt128.max.description == "340282366920938463463374607431768211455")
        XCTAssert(UInt128.min.description == "0")
        print("x = \(x)", "y = \(y)")
        print("UInt128.max = \(UInt128.max)", "UInt128.min = \(UInt128.min)")
        XCTAssert((y/x).description == div.description)
        XCTAssert((y%x).description == rem.description)
        print("y/x = \(y/x), y%x = \(y%x)")
    }
    
}
