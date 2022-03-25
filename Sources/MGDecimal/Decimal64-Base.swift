//
//  Decimal64.swift
//  
//
//  Created by Mike Griebling on 2022-03-12.
//

import Foundation

public struct Decimal64 : ExpressibleByStringLiteral, ExpressibleByFloatLiteral, CustomStringConvertible,
                          ExpressibleByIntegerLiteral {

    private static var enableStateOutput = false   // set to true to monitor variable state (i.e., invalid operations, etc.)
    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: - Decimal number storage
    var x: UInt64
    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: - Class State variables
    public static private(set) var state = Status.clearFlags
    public static private(set) var rounding = Rounding.toNearestOrEven
    
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
        x = Decimal64.bid64_from_string(value, Decimal64.rounding, &Decimal64.state)
    }
    
    public init(floatLiteral value: Double) {
        x = Decimal64.double_to_bid64(value, Decimal64.rounding, &Decimal64.state)
    }
    
    public init(integerLiteral value: Int) {
        x = Decimal64.bid64_from_int64(Int64(value), Decimal64.rounding, &Decimal64.state)
    }
    
    public init(decimal32: Decimal32) {
        x = Decimal64.BID32_to_BID64(decimal32.x, &Decimal64.state)
    }
    
    public init(_ value: Decimal128) { x = Decimal128.bid128_to_bid64(value.x, Decimal64.rounding, &Decimal64.state) }
    public init(_ value: Decimal32) { x = Decimal32.bid32_to_bid64(value.x, &Decimal64.state) }
    
    public var description: String { Decimal64.bid64_to_string(x) }

}

public extension Decimal64 {
    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: - Numeric State variables
    var sign: FloatingPointSign { x & Decimal64.SIGN_MASK64 != 0 ? .minus : .plus }
    var magnitude: Decimal64    { Decimal64(raw: x & ~Decimal64.SIGN_MASK64) }
    var decimal32: Decimal32    { Decimal32(raw: Decimal64.bid64_to_bid32(x, Decimal64.rounding, &Decimal64.state)) }
    var dpd64: UInt64           { Decimal64.bid_to_dpd64(x) }
    var int: Int                { Decimal64.bid64_to_int(x, &Decimal64.state) }
    var double: Double          { Decimal64.bid64_to_double(x, Decimal64.rounding, &Decimal64.state) }
    
    private func unpack () -> (sign: UInt64, exponent: Int, significand: UInt64)? {
        var s : (sign: UInt64, exponent: Int, significand: UInt64) = (UInt64(0), 0, UInt64(0))
        guard Decimal64.unpack_BID64(&s.sign, &s.exponent, &s.significand, x) else { return nil }
        return s
    }
    
    var significand: Decimal64 {
        let /* exp = 0, */ m = UInt64()
//        Decimal64.frexp(x, &m, &exp)
        return Decimal64(raw: m)
    }
    
    var decimal: Decimal {
        // Not optimized but should be ok since this is rarely used -- feel free to fix me
        Decimal(string: self.description) ?? Decimal()
    }
    
    var exponent: Int {
        let exp = 0 
//        Decimal64.frexp(x, &m, &exp)
        return exp
    }
    
    private var _isZero: Bool {
        if (x & Decimal64.INFINITY_MASK64) == Decimal64.INFINITY_MASK64 { return false }
        if (Decimal64.MASK_STEERING_BITS & x) == Decimal64.MASK_STEERING_BITS {
            return (x & Decimal64.MASK_BINARY_SIG2) | Decimal64.MASK_BINARY_OR2 > Decimal64.BID64_SIG_MAX
        } else {
            return (x & Decimal64.MASK_BINARY_SIG1) == 0
        }
    }
    
    private var _isCanonical: Bool {
        if self.isNaN {    // NaN
            if (x & 0x01f00000) != 0 {
                return false
            } else if (x & 0x000fffff) > 999999 {
                return false
            } else {
                return true
            }
        } else if (x & Decimal64.MASK_INF) == Decimal64.MASK_INF {
            return (x & 0x03ffffff) == 0
        } else if (x & Decimal64.MASK_STEERING_BITS) == Decimal64.MASK_STEERING_BITS { // 24-bit
            return ((x & Decimal64.MASK_BINARY_SIG2) | Decimal64.MASK_BINARY_OR2) <= Decimal64.BID64_SIG_MAX
        } else { // 23-bit coeff.
            return true
        }
    }
    
    static private func validDecode(_ x: UInt64) -> (exp:Int, sig:UInt64)? {
        let exp_x:Int
        let sig_x:UInt64
        if (x & INFINITY_MASK64) == INFINITY_MASK64 { return nil }
        if (x & MASK_STEERING_BITS) == MASK_STEERING_BITS {
            sig_x = (x & MASK_BINARY_SIG2) | MASK_BINARY_OR2
            // check for zero or non-canonical
            if sig_x > Decimal64.BID64_SIG_MAX || sig_x == 0 { return nil } // zero or non-canonical
            exp_x = Int((x & MASK_BINARY_EXPONENT2) >> 21)
        } else {
            sig_x = (x & MASK_BINARY_SIG1)
            if sig_x == 0 { return nil } // zero
            exp_x = Int((x & MASK_BINARY_EXPONENT1) >> 23)
        }
        return (exp_x, sig_x)
    }
    
    private var _isNormal: Bool {
        guard let result = Decimal64.validDecode(x) else { return false }
        
        // if exponent is less than -95, the number may be subnormal
        // if (exp_x - 101 = -95) the number may be subnormal
        if result.exp < 6 {
//            let sig_x_prime = UInt64(result.sig) * UInt64(Decimal64.bid_mult_factor[result.exp])
//            return sig_x_prime >= 1000000 // subnormal test
            return false
        } else {
            return true // normal
        }
    }
    
    private var _isSubnormal:Bool {
        guard let result = Decimal64.validDecode(x) else { return false }
        
        // if exponent is less than -95, the number may be subnormal
        // if (exp_x - 101 = -95) the number may be subnormal
        if result.exp < 6 {
//            let sig_x_prime = UInt64(result.sig) * UInt64(Decimal64.bid_mult_factor[result.exp])
//            return sig_x_prime < 1000000  // subnormal test
            return false
        } else {
            return false // normal
        }
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
//    var ulp: Decimal64       { nextUp - self }
//    var nextUp: Decimal64    { Decimal64(raw: Decimal64.bid32_nextup(x, &Decimal64.state)) }
    
}

