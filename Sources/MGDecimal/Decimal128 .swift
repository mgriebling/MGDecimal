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
    
    public var significandDigitCount: Int {
//        guard let x = unpack() else { return -1 }
        return 0 /* Decimal64.digitsIn(x.significand) */
    }
    
    public var exponentBitPattern: UInt { 0
//        let x = unpack()
//        return UInt64(x?.exponent ?? 0)
    }
    
    public var significandDigits: [UInt8] { []
//        guard let x = unpack() else { return [] }
//        return Array(String(x.significand)).map { UInt8($0.wholeNumberValue!) }
    }
    
    public var decade: Decimal128 { self /* TBD */
//        var res = UInt64(), exp = 0
//        Decimal64.frexp(x, &res, &exp)
//        return Decimal64(raw: return_bid64(0, exp+Decimal64.exponentBias, 1))
    }
    
    static func _isZero(_ x:UInt128) -> Bool {
        return false
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
    public var isNormal: Bool          { /*_isNormal*/ true }
    public var isSubnormal: Bool       { /*_isSubnormal*/ false }
    public var isCanonical: Bool       { /*_isCanonical*/ true }
    public var isBIDFormat: Bool       { true }
    public var ulp: Decimal128         { nextUp - self }
    public var nextUp: Decimal128      { /* Decimal128(raw: Decimal128.bid128_nextup(x, &Decimal128.state))*/ self }
    
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
    
    mutating public func round(_ rule: FloatingPointRoundingRule) { assertionFailure("Unimplemented \(#function) function") }
    mutating public func formRemainder(dividingBy other: Decimal128) { assertionFailure("Unimplemented \(#function) function") }
    mutating public func formTruncatingRemainder(dividingBy other: Decimal128) { assertionFailure("Unimplemented \(#function) function") }
    mutating public func formSquareRoot() { x = Decimal128.sqrt(x, Decimal128.rounding, &Decimal128.state) }
    mutating public func addProduct(_ lhs: Decimal128, _ rhs: Decimal128) { assertionFailure("Unimplemented \(#function) function") }
    
    public func distance(to other: Decimal128) -> Decimal128 { other - self }
    public func advanced(by n: Decimal128) -> Decimal128 { self + n }
    
}

