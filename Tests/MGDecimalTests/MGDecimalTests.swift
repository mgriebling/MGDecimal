import XCTest
@testable import MGDecimal

final class MGDecimalTests: XCTestCase {
    
    func testExample() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        // MGDecimal128.test()
        
//        let x = BID32(raw: 0xA23003D0)  // -7.50
//        let y = BID32(stringLiteral: "123456789")
        let y = Decimal32(stringLiteral: "234.5")
        let x = Decimal32(stringLiteral: "345.5")
        let n = UInt32(0xA23003D0)
        var a = Decimal32(dpd32: n)
        print(a, a.dpd32 == n ? "a = n" : "a != n")
        let z = y/x
        print(x.significandDigitCount, x.significandDigits)
        print(y.significandDigitCount, y.significandDigits)
        print(x, y, x*y, z, x.int, y.int, x.decade, y.decade)
        print(x.significand, x.exponent, y.significand, y.exponent)
        var b = Decimal32.leastNormalMagnitude
        print(Decimal32.greatestFiniteMagnitude, b, Decimal32.leastNonzeroMagnitude)
        
        let bias = Decimal32.exponentBias
        // bias == 101
        print(bias, Decimal32.greatestFiniteMagnitude.exponent)
        // Prints "127"
        print(Decimal32.leastNormalMagnitude.exponent)
        // Prints "-126"
        
        a = "-21.5"
        b = "305.15"
        let c = Decimal32(signOf: a, magnitudeOf: b)
        print(c)
        
        a = Decimal32(sign: .plus, exponentBitPattern: 101, significandDigits: [1,2,3,4])
        print(a)
        a = Decimal32.random(in: 1..<1000)
        print(a)
        
        var numbers : [Decimal32] = [2.5, 21.25, 3.0, .nan, -9.5]
        //var numbers2 = [2.5, 21.25, 3.0, .nan, -9.5]
        numbers.sort { !$1.isTotallyOrdered(belowOrEqualTo: $0) }
        print(numbers)
        // Prints "[-9.5, 2.5, 3.0, 21.25, nan]"
    }
    
}
