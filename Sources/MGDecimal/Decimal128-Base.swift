import Foundation

/// Decimal128 implementation according to IEEE 754.
/// A UInt128 implementation is included as part of this library.
public struct Decimal128 : ExpressibleByStringLiteral, CustomStringConvertible {

    private static var enableStateOutput = false   // set to true to monitor variable state (i.e., invalid operations, etc.)
    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: - Decimal number storage
    var x:UInt128      // Note: this includes a sign bit, 17-bit combination, and 110-bits of significand
    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: - Class State variables
    public static private(set) var state = Status.clearFlags
    public static private(set) var rounding = Rounding.toNearestOrEven
    
    init(raw: UInt128) { x = raw } // Note: internal use only
    
    public init(stringLiteral value: String) {
        x = Decimal128.bid128_from_string(value, Decimal128.rounding, &Decimal128.state)
    }
    
    public var description: String { Decimal128.bid128_to_string(x) }
    
}

/// Numerical properties
///
extension Decimal128 {
    
    
}

/// special constants
///
extension Decimal128 {
   
    public static let radix = 10

}

extension Decimal128 /* : SignedNumeric */ {

//    public init?<T>(exactly source: T) where T : BinaryInteger { self.init(Int64(source)) }
    
//    public var magnitude: MGDecimal128 { MGDecimal128(sign: .plus, exponent: exponent, mantissa: _significand) }
    
    public static func * (lhs: Decimal128, rhs: Decimal128) -> Decimal128 {
        assertionFailure("Unimplemented '*' function")
        return lhs
    }
    
    public static func *= (result: inout Decimal128, arg: Decimal128) {
        assertionFailure("Unimplemented '*=' function")
    }

}

extension Decimal128 /* : FloatingPoint */ {

    public static func / (lhs: Decimal128, rhs: Decimal128) -> Decimal128 { lhs /* TBD */ }
    public static func /= (lhs: inout Decimal128, rhs: Decimal128) { /* TBD */ }
    
    public mutating func round(_ rule: FloatingPointRoundingRule) { /* TBD */ }
    public mutating func formRemainder(dividingBy other: Decimal128) { /* TBD */ }
    public mutating func formTruncatingRemainder(dividingBy other: Decimal128) { /* TBD */ }
    public mutating func formSquareRoot() { /* TBD */ }
    public mutating func addProduct(_ lhs: Decimal128, _ rhs: Decimal128) { /* TBD */ }
    
}

extension Decimal128 /* : BinaryFloatingPoint */ {
    
    public static var exponentBitCount: Int { 0 }
    
    public static var significandBitCount: Int { 0 }
    
    public var significandWidth: Int { 0 } /* TBD */
    
}