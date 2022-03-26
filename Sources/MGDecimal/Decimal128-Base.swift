import Foundation

/// Decimal128 implementation according to IEEE 754.
/// A UInt128 implementation is included as part of this library. (maybe)
public struct Decimal128 : ExpressibleByStringLiteral, ExpressibleByFloatLiteral, CustomStringConvertible,
                           ExpressibleByIntegerLiteral {

    private static var enableStateOutput = false   // set to true to monitor variable state (i.e., invalid operations, etc.)
    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: - Decimal number storage
    var x:UInt128      // Note: this includes a sign bit, 17-bit combination, and 110-bits of significand
    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: - Class State variables
    public static private(set) var state = Status.clearFlags
    public static private(set) var rounding = Rounding.toNearestOrEven
    
    init(raw: UInt128) { x = raw } // Note: internal use only
    
    /// Binary Integer Decimal encoded 64-bit number
    public init(bid128: UInt128) { x = bid128 }
    
    /// Densely Packed Decimal encoded 64-bit number
    public init(dpd128: UInt128) { x = Decimal128.dpd_to_bid128(dpd128) }
    
    public init(stringLiteral value: String) {
        x = Decimal128.bid128_from_string(value, Decimal128.rounding, &Decimal128.state)
    }
    
    public init(floatLiteral value: Double) {
        x = Decimal128.double_to_bid128(value, Decimal128.rounding, &Decimal128.state)
    }
    
    public init(integerLiteral value: Int) {
        x = Decimal128.bid128_from_int64(Int64(value))
    }
    
    public init(_ value: Decimal64) { x = Decimal64.bid64_to_bid128(value.x, &Decimal128.state) }
    public init(_ value: Decimal32) { x = Decimal32.bid32_to_bid128(value.x, &Decimal128.state) }
    
    public var description: String { Decimal128.bid128_to_string(x) }
    
}

/// Numerical properties
///
extension Decimal128 {
    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: - Numeric State variables
    var sign: FloatingPointSign { x.hi & Decimal128.MASK_SIGN != 0 ? .minus : .plus }
    var magnitude: Decimal128   { Decimal128(raw: UInt128(w: [x.lo, x.hi & ~Decimal128.MASK_SIGN])) }
    var decimal32: Decimal32    { Decimal32(raw: Decimal128.bid128_to_bid32(x, Decimal128.rounding, &Decimal128.state)) }
    var decimal64: Decimal64    { Decimal64(raw: Decimal128.bid128_to_bid64(x, Decimal128.rounding, &Decimal128.state)) }
    var dpd128: UInt128         { Decimal128.bid_to_dpd128(x) }
    var int: Int                { Decimal128.bid128_to_int(x, &Decimal128.state) }
    var double: Double          { Decimal128.bid128_to_double(x, Decimal128.rounding, &Decimal128.state) }
    
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

