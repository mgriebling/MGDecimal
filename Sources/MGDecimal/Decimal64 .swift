//
//  Decimal64.swift
//  
//
//  Created by Mike Griebling on 2022-03-12.
//

import Foundation

public struct Decimal64 : CustomStringConvertible, ExpressibleByStringLiteral, ExpressibleByIntegerLiteral,
                          ExpressibleByFloatLiteral, Codable, Hashable {

    private static var enableStateOutput = false   // set to true to monitor variable state (i.e., invalid operations, etc.)
    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: - Decimal number storage
    var x: UInt64
    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: - Class State variables
    public static var state = Status.clearFlags
    public static var rounding = Rounding.toNearestOrEven
    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: - Class State constants
    public static let zero = Decimal64(raw: return_bid64_zero(0))
    public static let radix = 10
    public static let pi = Decimal64(stringLiteral: "3.1415926535897932384626433832795028841971693993751")
    public static let nan = Decimal64(raw: return_bid64_nan(0, 0, 0))
    public static let quietNaN = Decimal64(raw: return_bid64_nan(0, 0, 0))
    public static let signalingNaN = Decimal64(raw: SNAN_MASK64)
    public static let infinity = Decimal64(raw: return_bid64_inf(0))
    
    public static var greatestFiniteMagnitude: Decimal64 { Decimal64(raw: return_bid64_max(0)) }
    public static var leastNormalMagnitude: Decimal64    { Decimal64(raw: return_bid64(0, 0, 1_000_000_000_000_000)) }
    public static var leastNonzeroMagnitude: Decimal64   { Decimal64(raw: return_bid64(0, 0, 1)) }
    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: - Initializers
    init(raw: UInt64) { x = raw } // only for internal use
    
    private func showState() {
        if Decimal64.enableStateOutput && !Decimal64.state.isEmpty { print("Warning: \(Decimal64.state)") }
        Decimal64.state = .clearFlags
    }
    
    /// Binary Integer Decimal encoded 64-bit number
    public init(bid64: UInt64) { x = bid64 }
    
    /// Densely Packed Decimal encoded 64-bit number
    public init(dpd64: UInt64) { x = Decimal64.dpd_to_bid64(dpd64) }
    
    public init(stringLiteral value: String) {
        if value.hasPrefix("0x") {
            var s = value; s.removeFirst(2)
            x = UInt64(s, radix: 16) ?? 0
        } else {
            x = Decimal64.bid64_from_string(value, Decimal64.rounding, &Decimal64.state)
        }
    }
    
    public init(floatLiteral value: Double) {
        x = Decimal64.double_to_bid64(value, Decimal64.rounding, &Decimal64.state)
    }
    
    public init(integerLiteral value: Int) {
        x = Decimal64.bid64_from_int64(Int64(value), Decimal64.rounding, &Decimal64.state)
    }
    
    public init(decimal32: Decimal32) {
        x = Decimal64.bid32_to_bid64(decimal32.x, &Decimal64.state)
    }
    
    public init(decimal128: Decimal128) {
        x = Decimal128.bid128_to_bid64(decimal128.x, Decimal64.rounding, &Decimal64.state)
    }
    
    public init(_ value: Decimal128) { x = Decimal128.bid128_to_bid64(value.x, Decimal64.rounding, &Decimal64.state) }
    public init(_ value: Decimal32) { x = Decimal32.bid32_to_bid64(value.x, &Decimal64.state) }
    
    public init(_ value: Int = 0) { self.init(integerLiteral: value) }
    public init<Source>(_ value: Source) where Source : BinaryInteger { self.init(Int(value)) }
    
    public init?<T>(exactly source: T) where T : BinaryInteger {
        self.init(Int(source))  // FIX ME
    }
    
    public init(sign: FloatingPointSign, exponent: Int, significand: Decimal64) {
        let sgn = sign == .minus ? Decimal64.MASK_SIGN : 0
        var s : (sign: UInt64, exponent: Int, significand: UInt64) = (UInt64(0), 0, UInt64(0))
        self.init()
        if Decimal64.unpack_BID64(&s.sign, &s.exponent, &s.significand, significand.x) {
            x = Decimal64.get_BID64(sgn, exponent, s.significand, Decimal64.rounding, &Decimal64.state)
        }
    }
    
    public init(signOf: Decimal64, magnitudeOf: Decimal64) {
        let sign = signOf.isSignMinus
        self = sign ? -magnitudeOf.magnitude : magnitudeOf.magnitude
    }
    
    public init(sign: FloatingPointSign, exponentBitPattern: UInt, significandDigits: [UInt8]) {
        let mantissa = significandDigits.reduce(into: 0) { $0 = $0 * 10 + Int($1) }
        self.init(sign: sign, exponent: Int(exponentBitPattern), significand: Decimal64(mantissa))
    }
    
    public var description: String { Decimal64.bid64_to_string(x) }

}

extension Decimal64 : AdditiveArithmetic, Comparable, SignedNumeric, Strideable, FloatingPoint {

    public mutating func negate() { x ^= Decimal64.SIGN_MASK64 }
    
    public mutating func round(_ rule: FloatingPointRoundingRule) {
        x = Decimal64.bid64_round_integral_exact(x, rule, &Decimal64.state)
    }
    
    public mutating func formRemainder(dividingBy other: Decimal64) {
        x = Decimal64.bid64_rem(self.x, other.x, &Decimal32.state)
    }
    
    public mutating func formTruncatingRemainder(dividingBy other: Decimal64) {
        let q = (self/other).rounded(.towardZero)
        self -= q * other
    }
    
    public mutating func formSquareRoot() { x = Decimal64.sqrt(x, Decimal64.rounding, &Decimal64.state) }
    public mutating func addProduct(_ lhs: Decimal64, _ rhs: Decimal64) {
        x = Decimal64.bid64_fma(lhs.x, rhs.x, self.x, Decimal64.rounding, &Decimal64.state)
    }

    //////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: - Strideable compliance
    
    public func distance(to other: Decimal64) -> Decimal64 { other - self }
    public func advanced(by n: Decimal64) -> Decimal64 { self + n }
    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: - Basic arithmetic operations
    
    public func isEqual(to other: Decimal64) -> Bool { Decimal64.equal(self.x, other.x, &Decimal64.state) }
    public func isLess(than other: Decimal64) -> Bool { Decimal64.lessThan(self.x, other.x, &Decimal64.state) }
    public func isLessThanOrEqualTo(_ other: Decimal64) -> Bool { self < other || self == other }
    public static func == (lhs: Decimal64, rhs: Decimal64) -> Bool { lhs.isEqual(to: rhs) }
    public static func < (lhs: Decimal64, rhs: Decimal64) -> Bool { lhs.isLess(than: rhs) }
    
    public static func + (lhs: Decimal64, rhs: Decimal64) -> Decimal64 {
        Decimal64(raw: Decimal64.add(lhs.x, rhs.x, Decimal64.rounding, &Decimal64.state))
    }
    
    public static func / (lhs: Decimal64, rhs: Decimal64) -> Decimal64 {
        Decimal64(raw: Decimal64.div(lhs.x, rhs.x, Decimal64.rounding, &Decimal64.state))
    }
    
    public static func * (lhs: Decimal64, rhs: Decimal64) -> Decimal64 {
        Decimal64(raw: Decimal64.mul(lhs.x, rhs.x, Decimal64.rounding, &Decimal64.state))
    }
    
    public static func /= (lhs: inout Decimal64, rhs: Decimal64) { lhs = lhs / rhs }
    public static func *= (lhs: inout Decimal64, rhs: Decimal64) { lhs = lhs * rhs }
    public static func - (lhs: Decimal64, rhs: Decimal64) -> Decimal64 { lhs + (-rhs) }
    
}

extension Decimal64 : DecimalFloatingPoint {

    //////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: - DecimalFloatingPoint-required State variables
    
    public typealias RawExponent = UInt
    
    public static var exponentMaximum: Int          { MAX_EXPON }
    public static var exponentBias: Int             { EXPONENT_BIAS }
    public static var significandMaxDigitCount: Int { MAX_DIGITS }
    
    public var significandDigitCount: Int {
        guard let x = unpack() else { return -1 }
        return Decimal64.digitsIn(x.significand)
    }
    
    public var exponentBitPattern: UInt {
        let x = unpack()
        return UInt(x?.exponent ?? 0)
    }
    
    public var significandDigits: [UInt8] {
        guard let x = unpack() else { return [] }
        return Array(String(x.significand)).map { UInt8($0.wholeNumberValue!) }
    }
    
    public var decade: Decimal64 {
        var res = UInt64(), exp = 0
        Decimal64.frexp(x, &res, &exp)
        return Decimal64(raw: return_bid64(0, exp+Decimal64.exponentBias, 1))
    }
}

public extension Decimal64 {
    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: - Numeric State variables
    var sign: FloatingPointSign { x & Decimal64.SIGN_MASK64 != 0 ? .minus : .plus }
    var magnitude: Decimal64    { Decimal64(raw: x & ~Decimal64.SIGN_MASK64) }
    var decimal32: Decimal32    { Decimal32(raw: Decimal64.bid64_to_bid32(x, Decimal64.rounding, &Decimal64.state)) }
    var decimal128: Decimal128  { Decimal128(raw: Decimal64.bid64_to_bid128(x, &Decimal64.state)) }
    var dpd64: UInt64           { Decimal64.bid_to_dpd64(x) }
    var int: Int                { Decimal64.bid64_to_int(x, &Decimal64.state) }
    var double: Double          { Decimal64.bid64_to_double(x, Decimal64.rounding, &Decimal64.state) }
    
    private func unpack () -> (sign: UInt64, exponent: Int, significand: UInt64)? {
        var s : (sign: UInt64, exponent: Int, significand: UInt64) = (UInt64(0), 0, UInt64(0))
        guard Decimal64.unpack_BID64(&s.sign, &s.exponent, &s.significand, x) else { return nil }
        return s
    }
    
    var significand: Decimal64 {
        var exp = 0, m = UInt64()
        Decimal64.frexp(x, &m, &exp)
        return Decimal64(raw: m)
    }
    
    var decimal: Decimal {
        // Not optimized but should be ok since this is rarely used -- feel free to fix me
        Decimal(string: self.description) ?? Decimal()
    }
    
    var exponent: Int {
        var exp = 0, m = UInt64()
        Decimal64.frexp(x, &m, &exp)
        return exp
    }
    
    private var _isZero: Bool {
        if (x & Decimal64.INFINITY_MASK64) == Decimal64.INFINITY_MASK64 { return false }
        if (Decimal64.MASK_STEERING_BITS & x) == Decimal64.MASK_STEERING_BITS {
            return ((x & Decimal64.MASK_BINARY_SIG2) | Decimal64.MASK_BINARY_OR2) > Decimal64.MAX_NUMBER
        } else {
            return (x & Decimal64.MASK_BINARY_SIG1) == 0
        }
    }
    
    private var _isCanonical: Bool {
        let res:Bool
        if ((x & Decimal64.MASK_NAN) == Decimal64.MASK_NAN) {    // NaN
            if (x & 0x01fc000000000000) != 0 {
                res = false
            } else if (x & 0x0003ffffffffffff) > 999999999999999 {    // payload
                res = false
            } else {
                res = true
            }
        } else if (x & Decimal64.MASK_INF) == Decimal64.MASK_INF {
            res = (x & 0x03ffffffffffffff) == 0
        } else if (x & Decimal64.MASK_STEERING_BITS) == Decimal64.MASK_STEERING_BITS {    // 54-bit coeff.
            res = ((x & Decimal64.MASK_BINARY_SIG2) | Decimal64.MASK_BINARY_OR2) <= 9999999999999999
        } else {    // 53-bit coeff.
            res = true
        }
        return res
    }
    
    static private func validDecode(_ x: UInt64) -> (exp:Int, sig:UInt64)? {
        let exp_x:Int
        let sig_x:UInt64
        if (x & INFINITY_MASK64) == INFINITY_MASK64 { return nil }
        if (x & MASK_STEERING_BITS) == MASK_STEERING_BITS {
            sig_x = (x & MASK_BINARY_SIG2) | MASK_BINARY_OR2
            // check for zero or non-canonical
            if sig_x > Decimal64.MAX_NUMBER || sig_x == 0 { return nil } // zero or non-canonical
            exp_x = Int((x & MASK_BINARY_EXPONENT2) >> 51)
        } else {
            sig_x = (x & MASK_BINARY_SIG1)
            if sig_x == 0 { return nil } // zero
            exp_x = Int((x & MASK_BINARY_EXPONENT1) >> 53)
        }
        return (exp_x, sig_x)
    }
    
    private var _isNormal: Bool {
        guard let res = Decimal64.validDecode(x) else { return false }
        
        // if exponent is less than -383, the number may be subnormal
        // if (exp_x - 398 = -383) the number may be subnormal
        if res.exp < 15 {
            var sig_x_prime = UInt128()
            __mul_64x64_to_128MACH(&sig_x_prime, res.sig, bid_mult_factor[res.exp])
            return !(sig_x_prime.hi == 0 && sig_x_prime.lo < 1000000000000000)
        }
        return true    // normal
    }
    
    private var _isSubnormal:Bool {
        guard let res = Decimal64.validDecode(x) else { return false }
        
        // if exponent is less than -383, the number may be subnormal
        // if (exp_x - 398 = -383) the number may be subnormal
        if res.exp < 15 {
            var sig_x_prime = UInt128()
            __mul_64x64_to_128MACH(&sig_x_prime, res.sig, bid_mult_factor[res.exp])
            return sig_x_prime.hi == 0 && sig_x_prime.lo < 1000000000000000
        }
        return false    // normal
    }
    
    var isZero: Bool         { _isZero }
    var isSignMinus: Bool    { sign == .minus }
    var isInfinite: Bool     { ((x & Decimal64.MASK_INF) == Decimal64.MASK_INF) && !isNaN }
    var isNaN: Bool          { (x & Decimal64.MASK_NAN) == Decimal64.MASK_NAN }
    var isSignalingNaN: Bool { (x & Decimal64.MASK_SNAN) == Decimal64.MASK_SNAN }
    var isFinite: Bool       { (x & Decimal64.MASK_INF) != Decimal64.MASK_INF }
    var isNormal: Bool       { _isNormal }
    var isSubnormal: Bool    { _isSubnormal }
    var isCanonical: Bool    { _isCanonical }
    var isBIDFormat: Bool    { true }
    var ulp: Decimal64       { nextUp - self }
    var nextUp: Decimal64    { Decimal64(raw: Decimal64.bid64_nextup(x, &Decimal64.state)) }
    
}

