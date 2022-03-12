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
        let z = y/x
        print(x, y, x*y, z, x.int, y.int)
        
    }
    
}
