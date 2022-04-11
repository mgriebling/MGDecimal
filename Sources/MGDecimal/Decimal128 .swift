import Foundation

/// Decimal128 implementation according to IEEE 754.
/// A UInt128 implementation is included as part of this library. (maybe)
public struct Decimal128 : CustomStringConvertible, ExpressibleByStringLiteral, ExpressibleByIntegerLiteral,
                           ExpressibleByFloatLiteral, Codable, Hashable {

    private static var enableStateOutput = false   // set to true to monitor variable state (i.e., invalid operations, etc.)
    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: - Decimal number storage
    var x:UInt128      // Note: this includes a sign bit, 17-bit combination, and 110-bits of significand
    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: - Class State variables
    public static var state = Status.clearFlags
    public static var rounding = Rounding.toNearestOrEven
    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: - Class State constants
    public static let zero = Decimal128(raw: return_bid128_zero(0))
    public static let radix = 10
    public static let pi = Decimal128(stringLiteral: "3.1415926535897932384626433832795028841971693993751")
    public static let nan = Decimal128(raw: return_bid128_nan(0, 0, 0))
    public static let quietNaN = Decimal128(raw: return_bid128_nan(0, 0, 0))
    public static let signalingNaN = Decimal128(raw: UInt128(upper: Decimal64.SNAN_MASK64, lower: 0))
    public static let infinity = Decimal128(raw: return_bid128_inf(0))
    
    public static var greatestFiniteMagnitude: Decimal128 { Decimal128(raw: return_bid128_max(0)) }
    public static var leastNormalMagnitude: Decimal128    { Decimal128(raw: return_bid128(0, 0, 54210108624275, 4089650035136921600)) }
    public static var leastNonzeroMagnitude: Decimal128   { Decimal128(raw: return_bid128(0, 0, 0, 1)) }
    
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
    
    public init(_ value: Int = 0) { self.init(integerLiteral: value) }
    public init<Source>(_ value: Source) where Source : BinaryInteger { self.init(Int(value)) }
    
    public init?<T>(exactly source: T) where T : BinaryInteger {
        self.init(Int(source))  // FIX ME
    }
    
    public init(sign: FloatingPointSign, exponentBitPattern: UInt, significandDigits: [UInt8]) {
        self.init() /* TBD */
    }
    
    public init(sign: FloatingPointSign, exponent: Int, significand: Decimal128) {
//        let sgn = sign == .minus ? Decimal64.MASK_SIGN : 0
//        var s : (sign: UInt128, exponent: Int, significand: UInt128) = (UInt128(), 0, UInt128())
        self.init()
//        if Decimal128.unpack_BID128(&s.sign, &s.exponent, &s.significand, significand.x) {
//            x = Decimal128.get_BID128(sgn, exponent, s.significand, Decimal64.rounding, &Decimal64.state)
//        }
    }
    
    public init(signOf: Decimal128, magnitudeOf: Decimal128) {
        let sign = signOf.isSignMinus
        self = sign ? -magnitudeOf.magnitude : magnitudeOf.magnitude
    }
    
    public var description: String { Decimal128.bid128_to_string(x) }
    
}

/// Numerical properties
///
extension Decimal128 : DecimalFloatingPoint {
    
    public static var exponentMaximum: Int          { MAX_EXPON }
    public static var exponentBias: Int             { EXPONENT_BIAS }
    public static var significandMaxDigitCount: Int { MAX_FORMAT_DIGITS_128 }
    
    private func unpack () -> (sign: UInt64, exponent: Int, significand: UInt128)? {
        var s : (sign: UInt64, exponent: Int, significand: UInt128) = (UInt64(0), 0, UInt128(0))
        guard Decimal128.unpack_BID128(&s.sign, &s.exponent, &s.significand, x) else { return nil }
        return s
    }
    
    public var significandDigitCount: Int {
        guard let x = unpack() else { return -1 }
        return Decimal128.digitsIn(x.significand.hi, lo: x.significand.lo)
    }
    
    public var exponentBitPattern: UInt {
        let x = unpack()
        return UInt(x?.exponent ?? 0)
    }
    
    public var significandDigits: [UInt8] {
        guard let x = unpack() else { return [] }
        return Array(String(x.significand)).map { UInt8($0.wholeNumberValue!) }
    }
    
    public var decade: Decimal128 {
        var res = UInt128(), exp = 0
        Decimal128.frexp(x, &res, &exp)
        return Decimal128(raw: return_bid128(0, exp+Decimal128.exponentBias, 0, 1))
    }
    
    static func _isZero(_ x:UInt128) -> Bool {
        var sig_x = UInt128(), x = x
        BID_SWAP128(&x)
        if (x.hi & MASK_INF) == MASK_INF { return false }
        sig_x.hi = x.lo & 0x0001ffffffffffff
        sig_x.lo = x.lo
        if (sig_x.hi > Ten34M1.hi) || ((sig_x.hi == Ten34M1.hi) && (sig_x.lo > Ten34M1.lo)) ||    // significand is non-canonical
           ((x.hi & MASK_STEERING_BITS) == MASK_STEERING_BITS) || (sig_x.hi == 0 && sig_x.lo == 0) {    // significand is 0
            return true
        }
        return false
    }
    
    static private func validDecode(_ x: UInt128) -> (exp:Int, digits:Int)? {
        let Ten34M1 = Decimal128.Ten34M1
        let MASK_STEERING_BITS = Decimal128.MASK_STEERING_BITS
        var x = x
        BID_SWAP128(&x)
        
        // test for special values - infinity or NaN
        if (x.hi & Decimal128.MASK_SPECIAL) == Decimal128.MASK_SPECIAL {
            // x is special
            return nil
        }
        
        // unpack x
        let x_exp = x.hi & Decimal128.MASK_EXP   // biased and shifted left 49 bit positions
        let C1_hi = x.hi & Decimal128.MASK_COEFF
        let C1_lo = x.lo
        
        // test for zero
        if C1_hi == 0 && C1_lo == 0 {
            return nil
        }
        
        // test for non-canonical values of the argument x
        if (((C1_hi > Ten34M1.hi) || ((C1_hi == Ten34M1.hi) && (C1_lo > Ten34M1.lo))) &&
           ((x.hi & MASK_STEERING_BITS) != MASK_STEERING_BITS)) || ((x.hi & MASK_STEERING_BITS) == MASK_STEERING_BITS) {
            return nil
        }
        
        // x is subnormal or normal
        // determine the number of digits q in the significand
        // q = nr. of decimal digits in x
        // determine first the nr. of bits in x
        let q = digitsIn(C1_hi, lo: C1_lo)
//        if C1_hi == 0 {
//            if C1_lo >= Decimal128.LARGE_COEFF_HIGH_BIT64 {    // x >= 2^53
//                // split the 64-bit value in two 32-bit halves to avoid rounding errors
//                tmp1 = Double(C1_lo >> 32)    // exact conversion
//                x_nr_bits = 33 + Int(((tmp1.bitPattern >> 52)) & 0x7ff) - BINARY_EXPONENT_BIAS
//            } else {    // if x < 2^53
//                tmp1 = Double(C1_lo)    // exact conversion
//                x_nr_bits = 1 + Int(((tmp1.bitPattern >> 52)) & 0x7ff) - BINARY_EXPONENT_BIAS
//            }
//        } else {    // C1_hi != 0 => nr. bits = 64 + nr_bits (C1_hi)
//            tmp1 = Double(C1_hi)    // exact conversion
//            x_nr_bits = 65 + Int(((tmp1.bitPattern >> 52)) & 0x7ff) - BINARY_EXPONENT_BIAS
//        }
//        var q = Int(bid_nr_digits[x_nr_bits - 1].digits)
//        if q == 0 {
//            q = Int(bid_nr_digits[x_nr_bits - 1].digits1)
//            if (C1_hi > bid_nr_digits[x_nr_bits - 1].threshold_hi ||
//                (C1_hi == bid_nr_digits[x_nr_bits - 1].threshold_hi && C1_lo >= bid_nr_digits[x_nr_bits - 1].threshold_lo)) {
//                q+=1
//            }
//        }
        let exp = Int(x_exp >> 49) - Decimal128.EXPONENT_BIAS
        return (exp, q)
    }
    
    static func digitsIn(_ hi:UInt64, lo:UInt64) -> Int {
        let C1_hi = hi, C1_lo = lo
        var tmp1 = 0.0, x_nr_bits = 0
        if C1_hi == 0 {
            if C1_lo >= LARGE_COEFF_HIGH_BIT64 {    // x >= 2^53
                // split the 64-bit value in two 32-bit halves to avoid rounding errors
                tmp1 = Double(C1_lo >> 32)    // exact conversion
                x_nr_bits = 33 + Int(((tmp1.bitPattern >> 52)) & 0x7ff) - BINARY_EXPONENT_BIAS
            } else {    // if x < 2^53
                tmp1 = Double(C1_lo)    // exact conversion
                x_nr_bits = 1 + Int(((tmp1.bitPattern >> 52)) & 0x7ff) - BINARY_EXPONENT_BIAS
            }
        } else {    // C1_hi != 0 => nr. bits = 64 + nr_bits (C1_hi)
            tmp1 = Double(C1_hi)    // exact conversion
            x_nr_bits = 65 + Int(((tmp1.bitPattern >> 52)) & 0x7ff) - BINARY_EXPONENT_BIAS
        }
        var q = Int(bid_nr_digits[x_nr_bits - 1].digits)
        if q == 0 {
            q = Int(bid_nr_digits[x_nr_bits - 1].digits1)
            if (C1_hi > bid_nr_digits[x_nr_bits - 1].threshold_hi ||
               (C1_hi == bid_nr_digits[x_nr_bits - 1].threshold_hi && C1_lo >= bid_nr_digits[x_nr_bits - 1].threshold_lo)) {
                q+=1
            }
        }
        return q
    }
    
    private var _isNormal: Bool {
        guard let res = Decimal128.validDecode(x) else { return false }
        
        // test for subnormal values of x
        return res.exp + res.digits > -6143
    }
    
    private var _isSubnormal:Bool {
        guard let res = Decimal128.validDecode(x) else { return false }
        
        // test for subnormal values of x
        return res.exp + res.digits <= -6143
    }
    
    private var _isCanonical:Bool {
        let Ten34M1 = Decimal128.Ten34M1, Ten33M1 = Decimal128.Ten33M1
        let MASK_STEERING_BITS = Decimal128.MASK_STEERING_BITS
        var x = x, sig_x = UInt128()
        BID_SWAP128(&x)
        
        if (x.hi & Decimal128.MASK_NAN) == Decimal128.MASK_NAN {    // NaN
            if (x.hi & 0x01ffc00000000000) != 0 {
                return false
            }
            sig_x.hi = x.hi & 0x00003fffffffffff    // 46 bits
            sig_x.lo = x.lo    // 64 bits
            
            // payload must be < 10^33 = 0x0000314dc6448d93_38c15b0a00000000
            return sig_x.hi < Ten33M1.hi || (sig_x.hi == Ten33M1.hi && sig_x.lo < Ten33M1.lo+1)
        } else if (x.hi & Decimal128.MASK_INF) == Decimal128.MASK_INF {    // infinity
            return (x.hi & 0x03ffffffffffffff) == 0 && x.lo == 0
        }
        
        // not NaN or infinity; extract significand to ensure it is canonical
        sig_x.hi = x.hi & 0x0001ffffffffffff
        sig_x.lo = x.lo
        
        // a canonical number has a coefficient < 10^34
        //    (0x0001ed09_bead87c0_378d8e64_00000000)
        if ((sig_x.hi > Ten34M1.hi) ||    // significand is non-canonical
            ((sig_x.hi == Ten34M1.hi) && (sig_x.lo > Ten34M1.lo)) ||    // significand is non-canonical
            ((x.hi & MASK_STEERING_BITS) == MASK_STEERING_BITS)) {
            return false
        } else {
            return true
        }
    }
    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: - Numeric State variables
    public var sign: FloatingPointSign { x.hi & Decimal128.MASK_SIGN != 0 ? .minus : .plus }
    public var magnitude: Decimal128   { Decimal128(raw: UInt128(w: [x.lo, x.hi & ~Decimal128.MASK_SIGN])) }
    public var decimal32: Decimal32    { Decimal32(raw: Decimal128.bid128_to_bid32(x, Decimal128.rounding, &Decimal128.state)) }
    public var decimal64: Decimal64    { Decimal64(raw: Decimal128.bid128_to_bid64(x, Decimal128.rounding, &Decimal128.state)) }
    public var dpd128: UInt128         { Decimal128.bid_to_dpd128(x) }
    public var int: Int                { Decimal128.bid128_to_int(x, &Decimal128.state) }
    public var double: Double          { Decimal128.bid128_to_double(x, Decimal128.rounding, &Decimal128.state) }
    public var isZero: Bool            { Decimal128._isZero(x) }
    public var isSignMinus: Bool       { sign == .minus }
    public var isInfinite: Bool        { ((x.hi & Decimal64.MASK_INF) == Decimal128.MASK_INF) && !isNaN }
    public var isNaN: Bool             { (x.hi & Decimal64.MASK_NAN) == Decimal128.MASK_NAN }
    public var isSignalingNaN: Bool    { (x.hi & Decimal64.MASK_SNAN) == Decimal128.MASK_SNAN }
    public var isFinite: Bool          { (x.hi & Decimal64.MASK_INF) != Decimal128.MASK_INF }
    public var isNormal: Bool          { _isNormal }
    public var isSubnormal: Bool       { _isSubnormal }
    public var isCanonical: Bool       { _isCanonical }
    public var isBIDFormat: Bool       { true }
    public var ulp: Decimal128         { nextUp - self }
    public var nextUp: Decimal128      { Decimal128(raw: Decimal128.nextup(x, &Decimal128.state)) }
    
}

extension Decimal128 : FloatingPoint {
    
    public var exponent: Int {
        var exp = 0, m = UInt128()
        Decimal128.frexp(x, &m, &exp)
        return exp
    }
    
    public var significand: Decimal128 {
        var exp = 0, m = UInt128()
        Decimal128.frexp(x, &m, &exp)
        return Decimal128(raw: m)
    }

    public mutating func negate() { x.hi = x.hi ^ Decimal64.SIGN_MASK64 }
    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: - Basic arithmetic operations
    
    public func isEqual(to other: Decimal128) -> Bool { Decimal128.equal(self.x, other.x, &Decimal128.state) }
    public func isLess(than other: Decimal128) -> Bool { Decimal128.lessThan(self.x, other.x, &Decimal128.state) }
    public func isLessThanOrEqualTo(_ other: Decimal128) -> Bool { self < other || self == other }
    public static func == (lhs: Decimal128, rhs: Decimal128) -> Bool { lhs.isEqual(to: rhs) }
    public static func < (lhs: Decimal128, rhs: Decimal128) -> Bool { lhs.isLess(than: rhs) }
    
    public static func + (lhs: Decimal128, rhs: Decimal128) -> Decimal128 {
        Decimal128(raw: Decimal128.add(lhs.x, rhs.x, Decimal128.rounding, &Decimal128.state))
    }
    
    public static func / (lhs: Decimal128, rhs: Decimal128) -> Decimal128 {
        Decimal128(raw: Decimal128.div(lhs.x, rhs.x, Decimal128.rounding, &Decimal128.state))
    }
    
    public static func * (lhs: Decimal128, rhs: Decimal128) -> Decimal128 {
        Decimal128(raw: Decimal128.mul(lhs.x, rhs.x, Decimal128.rounding, &Decimal128.state))
    }
    
    public static func /= (lhs: inout Decimal128, rhs: Decimal128) { lhs = lhs / rhs }
    public static func *= (lhs: inout Decimal128, rhs: Decimal128) { lhs = lhs * rhs }
    public static func - (lhs: Decimal128, rhs: Decimal128) -> Decimal128 { lhs + (-rhs) }
    
    mutating public func round(_ rule: FloatingPointRoundingRule) {
        x = Decimal128.round(x, Decimal128.rounding, &Decimal128.state)
    }
    mutating public func formRemainder(dividingBy other: Decimal128) {
        x = Decimal128.rem(self.x, other.x, Decimal128.rounding, &Decimal128.state)
    }
    mutating public func formTruncatingRemainder(dividingBy other: Decimal128) {
        let q = (self/other).rounded(.towardZero)
        self -= q * other
    }
    mutating public func formSquareRoot() { x = Decimal128.sqrt(x, Decimal128.rounding, &Decimal128.state) }
    mutating public func addProduct(_ lhs: Decimal128, _ rhs: Decimal128) {
        x = Decimal128.fma(lhs.x, rhs.x, x, Decimal128.rounding, &Decimal128.state)
    }
    
    public func distance(to other: Decimal128) -> Decimal128 { other - self }
    public func advanced(by n: Decimal128) -> Decimal128 { self + n }
    
}

