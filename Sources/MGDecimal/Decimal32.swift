//
//  File.swift
//  
//
//  Created by Mike Griebling on 2022-03-07.
//

import Foundation

public struct Decimal32 : CustomStringConvertible, ExpressibleByStringLiteral, ExpressibleByIntegerLiteral,
                          ExpressibleByFloatLiteral, CustomDebugStringConvertible {

    //////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: - Data Type
    var x: UInt32   // 32-bit decimal number is stored here
    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: - Class State variables
    public static private(set) var state : Status = .clearFlags
    public static private(set) var rounding : Rounding = .halfEven
    public static let zero = Decimal32(raw: return_bid32_zero(0))
    public static let radix = 10
    public static let pi = Decimal32(floatLiteral: Double.pi)
    public static let nan = Decimal32(raw: return_bid32_nan(0, 0, 0))
    public static let quietNaN = Decimal32(raw: return_bid32_nan(0, 0, 0))
    public static let signalingNaN = zero // TBD
    public static let infinity = Decimal32(raw: return_bid32_inf(0))
    
    public static var greatestFiniteMagnitude: Decimal32 { Decimal32(raw: return_bid32_max(0)) }
    public static var leastNormalMagnitude: Decimal32 { zero /* TBD */ }
    public static var leastNonzeroMagnitude: Decimal32 { zero /* TBD */ }
    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: - Initializers
    public init(raw: UInt32) { x = raw } // only for internal use
    
    public init(integerLiteral value: Int) {
        self = Decimal32.int64_to_BID32(Int64(value), Decimal32.rounding, &Decimal32.state)
        if !Decimal32.state.isEmpty { print("Warning: \(Decimal32.state)"); Decimal32.state = .clearFlags }
    }
    
    public init(_ value: Int = 0) { self.init(integerLiteral: value) }
    public init<Source>(_ value: Source) where Source : BinaryInteger { self.init(Int(value)) }
    
    public init?<T>(exactly source: T) where T : BinaryInteger {
        self.init() // stub
    }
    
    public init(floatLiteral value: Double) {
        x = Decimal32.double_to_bid32(value, Decimal32.rounding, &Decimal32.state)
        if !Decimal32.state.isEmpty { print("Warning: \(Decimal32.state)"); Decimal32.state = .clearFlags }
    }

    public init(stringLiteral value: String) {
        var x = Decimal32(raw: 0)
        Decimal32.bid32_from_string(&x, value, Decimal32.rounding, &Decimal32.state)
        if !Decimal32.state.isEmpty { print("Warning: \(Decimal32.state)"); Decimal32.state = .clearFlags }
        self.x = x.x
    }
    
    public init(sign: FloatingPointSign, exponent: Int, significand: Decimal32) {
        let sgn = sign == .minus ? Decimal32.SIGN_MASK32 : 0
        self = Decimal32.get_BID32(sgn, exponent, significand.x, Decimal32.rounding, &Decimal32.state)
    }
    
    public init(signOf: Decimal32, magnitudeOf: Decimal32) {
        let sign = signOf.isSignMinus
        self = sign ? -magnitudeOf.magnitude : magnitudeOf.magnitude
    }
    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: - Custom String Convertible compliance
    public var description: String {
        var res = ""
        Decimal32.bid32_to_string(&res, self, Decimal32.rounding, Decimal32.state)
        return res
    }
    
    public var debugDescription: String { String(x, radix: 16, uppercase: true) }
    
}

extension Decimal32 : AdditiveArithmetic, Comparable, SignedNumeric, Strideable, FloatingPoint {

    public mutating func round(_ rule: FloatingPointRoundingRule) {
        /* TBD */
    }
    
    public mutating func formRemainder(dividingBy other: Decimal32) {
        /* TBD */
    }
    
    public mutating func formTruncatingRemainder(dividingBy other: Decimal32) {
        /* TBD */
    }
    
    public mutating func formSquareRoot() { x = Decimal32.sqrt(x, Decimal32.rounding, &Decimal32.state) }
    public mutating func addProduct(_ lhs: Decimal32, _ rhs: Decimal32) { self += lhs * rhs /* TBD - use FMA */ }

    public func distance(to other: Decimal32) -> Decimal32 { other - self }
    public func advanced(by n: Decimal32) -> Decimal32 { self + n }
    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: - Basic arithmetic operations
    
    public func isEqual(to other: Decimal32) -> Bool { self == other }
    public func isLess(than other: Decimal32) -> Bool { self < other }
    public func isLessThanOrEqualTo(_ other: Decimal32) -> Bool { self < other || self == other }
    public func isTotallyOrdered(belowOrEqualTo other: Decimal32) -> Bool { self < other }
    public static func == (lhs: Decimal32, rhs: Decimal32) -> Bool { Decimal32.equal(lhs.x, rhs.x, &Decimal32.state) }
    public static func < (lhs: Decimal32, rhs: Decimal32) -> Bool { Decimal32.lessThan(lhs.x, rhs.x, &Decimal32.state) }
    
    public static func / (lhs: Decimal32, rhs: Decimal32) -> Decimal32 {
        let res = Decimal32.div(lhs.x, rhs.x, Decimal32.rounding, &Decimal32.state)
        return Decimal32(raw: res)
    }
    
    public static func * (lhs: Decimal32, rhs: Decimal32) -> Decimal32 {
        let res = Decimal32.mul(lhs.x, rhs.x, Decimal32.rounding, &Decimal32.state)
        return Decimal32(raw: res)
    }
    
    public static func /= (lhs: inout Decimal32, rhs: Decimal32) { lhs = lhs / rhs }
    public static func *= (lhs: inout Decimal32, rhs: Decimal32) { lhs = lhs * rhs }
    public static prefix func - (lhs: Decimal32) -> Decimal32 { Decimal32(raw: lhs.x ^ Decimal32.SIGN_MASK32) }
    public static func - (lhs: Decimal32, rhs: Decimal32) -> Decimal32 { lhs + (-rhs) }
    
    public static func + (lhs: Decimal32, rhs: Decimal32) -> Decimal32 {
        let res = Decimal32.add(lhs.x, rhs.x, Decimal32.rounding, &Decimal32.state)
        return Decimal32(raw: res)
    }
    
}

public extension Decimal32 {
    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: - Numeric State variables
    var sign: FloatingPointSign { x & Decimal32.SIGN_MASK32 != 0 ? .minus : .plus }
    var magnitude: Decimal32 { Decimal32(raw: x & ~Decimal32.SIGN_MASK32) }
    
    private func unpack () -> (sign: UInt32, exponent: Int, significand: UInt32) {
        var s : (sign: UInt32, exponent: Int, significand: UInt32) = (UInt32(0), 0, UInt32(0))
        _ = Decimal32.unpack_BID32 (&s.sign, &s.exponent, &s.significand, x)
        return s
    }
    
    var significand: Decimal32 {
        let s = unpack()
        return Decimal32(raw: return_bid32(0, 0, Int(s.significand)))
    }
    
    var decimal: Decimal {
        // Not optimized but should be ok since this is rarely used -- feel free to fix me
        Decimal(string: self.description) ?? Decimal()
    }
    
    var decimal64: Decimal64 {
        Decimal64(raw: Decimal64.BID32_to_BID64(x, &Decimal32.state))
    }
    
    var exponent: Int {
        let s = unpack()
        return s.exponent
    }
    
    var int: Int {
        Decimal32.bid32_to_int(x, Decimal32.rounding, &Decimal32.state)
    }
    
    var double: Double {
        Decimal32.bid32_to_double(x, Decimal32.rounding, &Decimal32.state)
    }
    
    private var _isZero: Bool {
        if (x & Decimal32.INFINITY_MASK32) == Decimal32.INFINITY_MASK32 { return false }
        if (Decimal32.MASK_STEERING_BITS32 & x) == Decimal32.MASK_STEERING_BITS32 {
            return (x & Decimal32.MASK_BINARY_SIG2_32) | Decimal32.MASK_BINARY_OR2_32 > Decimal32.BID32_SIG_MAX
        } else {
            return (x & Decimal32.MASK_BINARY_SIG1_32) == 0
        }
    }
    
    private var _isCanonical: Bool {
        if self.isNaN {    // NaN
            if (x & 0x01f00000) != 0 {
                return false
            } else if (x & 0x000fffff) > 999999 { // payload
                return false
            } else {
                return true
            }
        } else if (x & Decimal32.MASK_INF32) == Decimal32.MASK_INF32 {
            return (x & 0x03ffffff) == 0
        } else if (x & Decimal32.MASK_STEERING_BITS32) == Decimal32.MASK_STEERING_BITS32 { // 24-bit
            return ((x & Decimal32.MASK_BINARY_SIG2_32) | Decimal32.MASK_BINARY_OR2_32) <= Decimal32.BID32_SIG_MAX
        } else { // 23-bit coeff.
            return true
        }
    }
    
    static private func validDecode(_ x: UInt32) -> (exp:Int, sig:UInt32)? {
        let exp_x:Int
        let sig_x:UInt32
        if (x & INFINITY_MASK32) == INFINITY_MASK32 { return nil }
        if (x & MASK_STEERING_BITS32) == MASK_STEERING_BITS32 {
            sig_x = (x & MASK_BINARY_SIG2_32) | MASK_BINARY_OR2_32
            // check for zero or non-canonical
            if sig_x > Decimal32.BID32_SIG_MAX || sig_x == 0 { return nil } // zero or non-canonical
            exp_x = Int((x & MASK_BINARY_EXPONENT2_32) >> 21)
        } else {
            sig_x = (x & MASK_BINARY_SIG1_32)
            if sig_x == 0 { return nil } // zero
            exp_x = Int((x & MASK_BINARY_EXPONENT1_32) >> 23)
        }
        return (exp_x, sig_x)
    }
    
    private var _isNormal: Bool {
        guard let result = Decimal32.validDecode(x) else { return false }
        
        // if exponent is less than -95, the number may be subnormal
        // if (exp_x - 101 = -95) the number may be subnormal
        if result.exp < 6 {
            let sig_x_prime = UInt64(result.sig) * UInt64(Decimal32.bid_mult_factor[result.exp])
            return !(sig_x_prime < 1000000) // subnormal test
        } else {
            return true // normal
        }
    }
    
    private var _isSubnormal:Bool {
        guard let result = Decimal32.validDecode(x) else { return false }
        
        // if exponent is less than -95, the number may be subnormal
        // if (exp_x - 101 = -95) the number may be subnormal
        if result.exp < 6 {
            let sig_x_prime = UInt64(result.sig) * UInt64(Decimal32.bid_mult_factor[result.exp])
            return sig_x_prime < 1000000  // subnormal test
        } else {
            return false // normal
        }
    }
    
    var isZero: Bool         { _isZero }
    var isSignMinus: Bool    { sign == .minus }
    var isInfinite: Bool     { ((x & Decimal32.INFINITY_MASK32) == Decimal32.INFINITY_MASK32) && !isNaN }
    var isNaN: Bool          { (x & Decimal32.NAN_MASK32) == Decimal32.NAN_MASK32 }
    var isSignalingNaN: Bool { (x & Decimal32.SNAN_MASK32) == Decimal32.SNAN_MASK32 }
    var isFinite: Bool       { (x & Decimal32.INFINITY_MASK32) != Decimal32.INFINITY_MASK32 }
    var isNormal: Bool       { _isNormal }
    var isSubnormal: Bool    { _isSubnormal }
    var isCanonical: Bool    { _isCanonical }
    
    var ulp: Decimal32    { Decimal32.zero /* TBD */ }
    var nextUp: Decimal32 { Decimal32.zero /* TBD */ }
    
}

