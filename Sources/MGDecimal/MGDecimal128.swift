import Foundation

/// Decimal128 implementation according to IEEE 754.
/// This implementation requires a UInt128 pre-existing data type.
/// A UInt128 implementation is included as part of this library.
public struct MGDecimal128  {
    
    // Binary Integer Decimal implementation
    private typealias BID128 = UInt128
    private let dn128: BID128     // Note: this includes a sign bit, 17-bit combination, and 110-bits of significand
    
    /* parameters for MGDecimal128 */
    static let Bytes   =    16      /* length                          */
    static let Pmax    =    34      /* maximum precision (digits)      */
    static let Emin    = -6143      /* minimum adjusted exponent       */
    static let Emax    =  6144      /* maximum adjusted exponent       */
    static let EmaxD   =     4      /* maximum exponent digits         */
    static let Bias    =  6176      /* bias for the exponent           */
    static let String  =    43      /* maximum string length, +1       */
    static let EconL   =    12      /* exponent continuation length    */
    static let Declets =    11      /* count of declets                */
    
    /* highest biased exponent (Elimit-1) */
    static let Ehigh = Emax + Bias - (Pmax-1)
    
    public static func test() {
//        let x = UInt128(1000)
//        let a = Decimal(2)
//        let y = MGDecimal128.maxSignificand
//        let x = MGDecimal128(Int64(-1234567890))
//        let y = MGDecimal128(sign: .minus, exponent: -9, mantissa: UInt128(1234567889))
//        let z = MGDecimal128.greatestFiniteMagnitude
//        let a = MGDecimal128.leastFiniteMagnitude
//        let t = x < y
//        let s = x.description
//        print(s, y, t, z, a)
//        print(String(MGDecimal128.negativeBit, radix: 16))
//        print(String(MGDecimal128.significandMask, radix: 16))
//        let x = SIMD4<UInt32>(0, 0, 0, 0)  // LSW is first
//        let y = SIMD4<UInt32>(0, 0, 0, 1)
//        let zero = SIMD4<UInt32>(0, 0, 0, 0)
//        var a = vU256(v:(x, y))
//        var b = vU256(v: (zero, zero))
//        vLL256Shift(&a, 100, &b)
//        print(b.v)
    }
    
    private init(_ value: BID128) { dn128 = value } // Note: dn128 is a BID number
    
//    public init(_ value: Int64) {
//        // add the sign bit
//        if value < 0 {
//            self.init(sign: .minus, exponent: 0, mantissa: UInt128(-value))
//        } else {
//            self.init(sign: .plus, exponent: 0, mantissa: UInt128(value))
//        }
//    }
//
//    public init(_ value: UInt64 = 0) {
//        // exponent will always be zero in this case since only 64 bits are used
//        self.init(sign: .plus, exponent: 0, mantissa: UInt128(value))
//    }
    
    /// Internal initializer given a sign, exponent, and mantissa where the resultant
    /// number is ± x × 10ⁿ, where _x = mantissa_, _n = exponent_, and _sign_ gives the ± value.
//    private init(sign: FloatingPointSign, exponent: Int, mantissa: UInt128) {
//        // requirement: overflow on input should return zero
//        let maxExponent = MGDecimal128.maxExponent
//        if mantissa > MGDecimal128.maxSignificand             { self.init(); return } // return zero
//        if exponent < 1-maxExponent || exponent > maxExponent { self.init(); return } // return zero
//
//        /// convert to unsigned exponent from 0x0000 - 0x1FFF where
//        let exp = exponent < 0 ? UInt(MGDecimal128.exponentNegativeOffset + exponent) : UInt(exponent)
//
//        // generate combination field
//        let significandWidth = MGDecimal128.significandWidth
//        var combination = UInt(0)
//        var significand = mantissa
//        let sigNibble = UInt(significand >> significandWidth)
//        significand &= ~(UInt128(0b1111) << significandWidth)         // clear significand upper nibble
//        switch sigNibble {
//            case 0b0000...0b0111: combination = (exp << 3) | sigNibble
//            case 0b1000...0b1001: combination = (0b11 << 15) | (exp << 1) | (sigNibble & 1)
//            default:              break // shouldn't reach here
//        }
//
//        // merge the sign, combination & significand fields
//        let combined = (UInt128(combination) << significandWidth) | significand
//        let num = combined | (sign == .minus ? MGDecimal128.negativeBit : 0)
//        self.init(num)
//    }
//
//    public init(sign: FloatingPointSign, exponent: Int, significand: MGDecimal128) {
//        self.init(sign: sign, exponent: exponent, mantissa: significand._significand)
//    }
//
//    public init(signOf: MGDecimal128, magnitudeOf: MGDecimal128) {
//        let sign = signOf.sign
//        let mag = magnitudeOf.magnitude._significand
//        dn128 = sign == .minus ? mag | MGDecimal128.negativeBit : mag
//    }
    
//    public init<Source>(_ value: Source) where Source : BinaryInteger {
//        let sign = value.signum() < 0 ? FloatingPointSign.minus : .plus
//        self.init(sign: sign, exponent: 0, mantissa: UInt128(value.magnitude))
//    }
    
}

/// Numerical properties
///
extension MGDecimal128 {
    
//    public var sign: FloatingPointSign { dn128 & MGDecimal128.negativeBit != 0 ? .minus : .plus }
//
//    private var combinationField: UInt { UInt((dn128 >> MGDecimal128.significandWidth) & MGDecimal128.combinationMask) }
//    private var upperBits: UInt { (combinationField >> 12) & MGDecimal128.infinityMask }
//
//    private var _significand : BID128 {
//        var significand = dn128 & MGDecimal128.significandMask
//        let combField = combinationField
//        let upperBitsToShift = MGDecimal128.combinationWidth-5 // = 12
//        let upperBits = (combField >> upperBitsToShift) & MGDecimal128.infinityMask
//        if upperBits>>3 == MGDecimal128.mask2Bits {
//            // dealing with two leading '1's
//            // add lower bit of combination field + "1000" to upper bits of significand
//            significand |= UInt128((combField & 1) | 0b1000) << MGDecimal128.significandWidth
//        } else {
//            // dealing with leading '01', '10', or '00'
//            // add lower 3 bits of combination field to upper bits of significand
//            significand |= UInt128(combField & 0b111) << MGDecimal128.significandWidth
//        }
//        return significand
//    }
    
//    public var significand: MGDecimal128 { MGDecimal128(sign: .plus, exponent: 0, mantissa: _significand) }
    
//    public var decimal: Decimal {
//        // Not optimized but should be ok since this is rarely used
//        NSDecimalNumber(string: self.description).decimalValue
//    }
    
//    public var exponent: Int {
//        let combField = combinationField
//        let upperBitsToShift = MGDecimal128.combinationWidth-5 // = 12
//        let upperBits = (combField >> upperBitsToShift) & MGDecimal128.infinityMask
//        let exp: UInt
//        if upperBits>>3 == MGDecimal128.mask2Bits {
//            // dealing with two leading '1's
//            exp = UInt((combField >> 1) & 0x3FFF)         // exp = mid 14 bits of combination field after '11' prefix
//        } else {
//            // dealing with leading '01', '10', or '00'
//            exp = UInt(combField >> 3)                    // exp = upper 14 bits of combination field
//        }
//
//        // Convert exponent to a signed integer
//        return exp > MGDecimal128.maxExponent ? Int(exp) - MGDecimal128.exponentNegativeOffset : Int(exp)
//    }
    
//    public var isZero: Bool         { _significand.nonzeroBitCount == 0 }
//    public var isSignMinus: Bool    { sign == .minus }
//    public var isInfinite: Bool     { upperBits == MGDecimal128.infinityField }
//    public var isNaN: Bool          { upperBits == MGDecimal128.Nan }
//    public var isSignalingNaN: Bool { isNaN && (combinationField & MGDecimal128.signalBit != 0) }
//    public var isFinite: Bool       { isZero || !(isInfinite || isNaN) }
//    public var isNormal: Bool       { true /* TBD */ }
//    public var isSubnormal: Bool    { false /* TBD */ }
//    public var isCanonical: Bool    { true /* TBD */ }
    
//    public var ulp: MGDecimal128    { MGDecimal128.zero /* TBD */ }
//    public var nextUp: MGDecimal128 { MGDecimal128.zero /* TBD */ }
    
}

/// special constants
///
extension MGDecimal128 {
   
//    public static let greatestFiniteMagnitude = MGDecimal128(sign: .plus, exponent: MGDecimal128.maxExponent, mantissa: MGDecimal128.maxSignificand)
//    public static let leastFiniteMagnitude = MGDecimal128(sign: .plus, exponent: 1-MGDecimal128.maxExponent, mantissa: MGDecimal128.maxSignificand)
//    public static var leastNormalMagnitude: MGDecimal128 { leastFiniteMagnitude }
//    public static var leastNonzeroMagnitude: MGDecimal128 { 0 }
    
    public static let radix = 10
//    public static let pi = MGDecimal128()    // TBD
//    public static let nan = MGDecimal128()   // TBD
//    static let quietNaN = MGDecimal128()     // TBD
//
//    public static var signalingNaN: MGDecimal128 { MGDecimal128() }
//    public static var infinity: MGDecimal128 { MGDecimal128() }

}

extension MGDecimal128 /* : SignedNumeric */ {

//    public init?<T>(exactly source: T) where T : BinaryInteger { self.init(Int64(source)) }
    
//    public var magnitude: MGDecimal128 { MGDecimal128(sign: .plus, exponent: exponent, mantissa: _significand) }
    
    public static func * (lhs: MGDecimal128, rhs: MGDecimal128) -> MGDecimal128 {
        assertionFailure("Unimplemented '*' function")
        return lhs
    }
    
    public static func *= (result: inout MGDecimal128, arg: MGDecimal128) {
        assertionFailure("Unimplemented '*=' function")
    }

}

//extension MGDecimal128 : Comparable {
//
//    public static func < (lhs: MGDecimal128, rhs: MGDecimal128) -> Bool { lhs.isLess(than: rhs) }
//
//    public func isEqual(to other: MGDecimal128) -> Bool { false /* TBD */ }
    
//    public func isLess(than other: MGDecimal128) -> Bool {
//        let lhs = self, rhs = other
//        if lhs.sign != rhs.sign { return lhs.isSignMinus }  // negative number is less than a positive
//        let lexp = lhs.exponent
//        let rexp = rhs.exponent
//        if lexp == rexp {
//            // just compare significands
//            if lhs.isSignMinus { return lhs._significand > rhs._significand }
//            else { return lhs._significand < rhs._significand }
//        } else {
//            let lNumber = lhs._significand
//            let rNumber = rhs._significand
//            if lNumber == rNumber { return lexp < rexp }
//            if lNumber < rNumber && lexp < rexp { return true }
//            if lNumber > rNumber && lexp > rexp { return false }
//
//            // convert to doubles and compare
//            let sign = lhs.isSignMinus ? -1.0 : 1.0
//            let ldouble = pow(10, Double(lexp)) * Double(lNumber) * sign
//            let rdouble = pow(10, Double(rexp)) * Double(rNumber) * sign
//            return ldouble < rdouble
//        }
//    }
    
//    public func isLessThanOrEqualTo(_ other: MGDecimal128) -> Bool { self.isLess(than: other) || self.isEqual(to: other) }
//    public func isTotallyOrdered(belowOrEqualTo other: MGDecimal128) -> Bool { self <= other }
    
// }

//extension MGDecimal128 : AdditiveArithmetic {
//    
//    public static func - (lhs: MGDecimal128, rhs: MGDecimal128) -> MGDecimal128 {
//        assertionFailure("Unimplemented '-' function")
//        return lhs
//    }
//    
//    public static func + (lhs: MGDecimal128, rhs: MGDecimal128) -> MGDecimal128 {
//        assertionFailure("Unimplemented '+' function")
//        return lhs
//    }
//    
//}

//extension MGDecimal128 : ExpressibleByIntegerLiteral {
//
//    public init(integerLiteral value: Int64) { self.init(value) }
//
//}

//extension MGDecimal128 /* : ExpressibleByFloatLiteral  */{
    
//    public init(floatLiteral value: Double) {
//        assertionFailure("Unimplemented init(Double) function")
////        let rounded = round(value)
////        let remainder = value - rounded
////        if let x = UInt128(exactly: rounded) {
////            while !remainder.isZero {
////                // TBD
////            }
////        }
//        self.init()
//    }

//}

//extension MGDecimal128 : Strideable {
//    
//    public func distance(to other: MGDecimal128) -> MGDecimal128 {
//        assertionFailure("Unimplemented 'distance' function")
//        return 0
//    }
//    
//    public func advanced(by n: MGDecimal128) -> MGDecimal128 {
//        assertionFailure("Unimplemented 'advanced' function")
//        return 0
//    }
//     
//}

extension MGDecimal128 : Codable { }  // Supported by default methods
extension MGDecimal128 : Hashable { } // Supported by default methods

extension MGDecimal128 /* : CustomStringConvertible */ {
    
    // Produce a textual representation of the number
//    public var description: String {
//        let sign = isSignMinus ? "-" : ""
//
//        // Check for special numbers & extract exponent and significand
//        if isInfinite { return sign + "Infinity" }
//        else if isNaN { return "NaN" } // ignore sign
//        else if isZero { return sign + "0" }
//
//        // Convert the significand to a string
//        var string = _significand.description
//        if exponent != 0 {
//            // add the decimal point
//            string.insert(".", at: string.index(after: string.startIndex))
//            string += "e" + exponent.description
//        }
//        return sign + string
//    }
   
}

extension MGDecimal128 /* : FloatingPoint */ {

    public static func / (lhs: MGDecimal128, rhs: MGDecimal128) -> MGDecimal128 { lhs /* TBD */ }
    public static func /= (lhs: inout MGDecimal128, rhs: MGDecimal128) { /* TBD */ }
    
    public mutating func round(_ rule: FloatingPointRoundingRule) { /* TBD */ }
    public mutating func formRemainder(dividingBy other: MGDecimal128) { /* TBD */ }
    public mutating func formTruncatingRemainder(dividingBy other: MGDecimal128) { /* TBD */ }
    public mutating func formSquareRoot() { /* TBD */ }
    public mutating func addProduct(_ lhs: MGDecimal128, _ rhs: MGDecimal128) { /* TBD */ }
    
}

extension MGDecimal128 /* : BinaryFloatingPoint */ {
    
    public static var exponentBitCount: Int { 0
    }
    
    public static var significandBitCount: Int { 0
    }
    
//    public var exponentBitPattern: UInt { UInt(exponent) }
//
//    public var significandBitPattern: UInt128 { _significand }
//
//    public var binade: MGDecimal128 { self }  /* TBD */
//
//
//    public init(sign: FloatingPointSign, exponentBitPattern: UInt, significandBitPattern: UInt128) {
//        /* TBD */
//        self.init()
//    }
    
    public var significandWidth: Int { 0 } /* TBD */
    
}
