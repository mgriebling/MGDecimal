import XCTest
@testable import MGDecimal

final class MGDecimalTests: XCTestCase {
    
    func testDecimal32() throws {
        let y1 = Decimal32(stringLiteral: "123456789"); XCTAssert(y1.description == "1.234568e+8")
        print("123456789 -> \(y1)")
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
        
        a = Decimal32(sign: .plus, exponentBitPattern: 101, significandDigits: [1,2,3,4])
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
        a1.formRemainder(dividingBy: b1)
        print("\(a1).formRemainder(dividingBy: \(b1) = ", a1)
        XCTAssert(a1 == Decimal32("-0.375"))
        a1 = Decimal32("8.625")
        let q = (a1/b1).rounded(.towardZero); print(q)
        a1 = a1 - q * b1
//        a1.formTruncatingRemainder(dividingBy: b1)
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
        let y1 = Decimal64(stringLiteral: "123456789"); XCTAssert(y1.description == "123456789")
        print("123456789 -> \(y1)")
    }
    
}
