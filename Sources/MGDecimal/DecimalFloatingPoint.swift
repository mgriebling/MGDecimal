//
//  DecimalFloatingPoint.swift
//  
//
//  Created by Mike Griebling on 2022-03-13.
//

import Foundation

/// A radix-10 (decimal) floating-point type.
///
/// The `DecimalFloatingPoint` protocol extends the `FloatingPoint` protocol
/// with operations specific to floating-point decimal types, as defined by the
/// [IEEE 754 specification][spec]. `DecimalFloatingPoint` is implemented in
/// the standard library by `Decimal32`, `Decimal64`, and `Decimal128` where available.
///
/// [spec]: http://ieeexplore.ieee.org/servlet/opac?punumber=4610933
public protocol DecimalFloatingPoint : ExpressibleByFloatLiteral, FloatingPoint {

    /// A type that represents the encoded exponent of a value.
    associatedtype RawExponent : UnsignedInteger

    /// Creates a new instance from the specified sign and bit patterns.
    ///
    /// The values passed as `exponentBitPattern` is interpreted in the
    /// binary interchange format defined by the [IEEE 754 specification][spec].
    ///
    /// [spec]: http://ieeexplore.ieee.org/servlet/opac?punumber=4610933
    ///
    /// The `significandDigits` are the single-digit-per-element, big-endian
    /// decimal digits of the number.  For example, the number [3, 1, 4,]
    /// represents a significand of `314`.
    ///
    /// - Parameters:
    ///   - sign: The sign of the new value.
    ///   - exponentBitPattern: The bit pattern to use for the exponent field of
    ///     the new value.
    ///   - significandDigits: The binary-coded decimal digits, one per UInt8
    ///     instance of the new value.
    init(sign: FloatingPointSign, exponentBitPattern: Self.RawExponent, significandDigits: [UInt8])

    /// Creates a new instance from the given value, rounded to the closest
    /// possible representation.
    ///
    /// - Parameter value: A floating-point value to be converted.
    init(_ value: Decimal32)

    /// Creates a new instance from the given value, rounded to the closest
    /// possible representation.
    ///
    /// - Parameter value: A floating-point value to be converted.
    init(_ value: Decimal64)

    /// Creates a new instance from the given value, rounded to the closest
    /// possible representation.
    ///
    /// - Parameter value: A floating-point value to be converted.
    init(_ value: Decimal128)

    /// Creates a new instance from the given value, rounded to the closest
    /// possible representation.
    ///
    /// If two representable values are equally close, the result is the value
    /// with more trailing zeros in its significand bit pattern.
    ///
    /// - Parameter value: A floating-point value to be converted.
    init<Source>(_ value: Source) where Source : DecimalFloatingPoint

    /// Creates a new instance from the given value, if it can be represented
    /// exactly.
    ///
    /// If the given floating-point value cannot be represented exactly, the
    /// result is `nil`. A value that is NaN ("not a number") cannot be
    /// represented exactly if its payload cannot be encoded exactly.
    ///
    /// - Parameter value: A floating-point value to be converted.
    init?<Source>(exactly value: Source) where Source : DecimalFloatingPoint

    /// The maximum value of the `exponent` for normal, finite values
    /// with the bias removed.
    ///
    /// The least normal exponent for values of the type `F` is `-exponentMaximum+1`,
    /// and the largest finite exponent is `exponentMaximum`. An all-zeros exponent
    /// is reserved for subnormals and zeros, and an all-ones exponent is reserved
    /// for infinity and NaN.
    ///
    /// For example, the `Decimal32` type has an `exponentMaximum` of `191` and
    /// an exponent bias of `101`.  The unbiased `exponent` is given by
    ///
    ///     exponent = exponentBitPattern - exponentBias + (significandMaxDigitCount-1)
    ///
    ///     let bias = Decimal32.exponentBias
    ///     // bias == 101
    ///     print(Decimal32.greatestFiniteMagnitude.exponent)
    ///     // Prints "96"
    ///     print(Decimal32.leastNormalMagnitude.exponent)
    ///     // Prints "-95"
    static var exponentMaximum: Int { get }
    
    /// The exponent bias is an offset applied to the `exponent` when encoding
    /// to the Decimaln format.
    static var exponentBias: Int { get }

    /// The maximum number of significand decimal digits.
    ///
    /// For fixed-width floating-point types, this is the maximum possible number of
    /// significand digits.
    ///
    /// For extensible floating-point types, `significandMaxDigitCount` should be the
    /// maximum allowed significand digits. If there is no upper limit, then
    /// `significandMaxDigitCount` should be `Int.max`.
    static var significandMaxDigitCount: Int { get }

    /// The raw encoding of the value's exponent field.
    ///
    /// This value is unadjusted by the type's exponent bias.
    var exponentBitPattern: Self.RawExponent { get }

    /// The digits comprising the significand field with most significant digit first.
    var significandDigits: [UInt8] { get }

    /// The floating-point value with the same sign and exponent as this value,
    /// but with a significand of 1.0.
    ///
    /// A *decade* is a set of decimal floating-point values that all have the
    /// same sign and exponent. The `decade` property is a member of the same
    /// decade as this value, but with a unit significand.
    ///
    /// In this example, `x` has a value of `21.5`, which is stored as
    /// `2.15 * 10**1`, where `**` is exponentiation. Therefore, `x.decade` is
    /// equal to `1.0 * 10**1`, or `10.0`.
    ///
    ///     let x = 21.5
    ///     // x.significand == 2.15
    ///     // x.exponent == 1
    ///
    ///     let y = x.decade
    ///     // y == 10.0
    ///     // y.significand == 1.0
    ///     // y.exponent == 1
    var decade: Self { get }
    
    /// True if the internal number encoding is binary integer decimal or BID.
    /// The alternative allowed by the IEEE standard is densely packed decimal or DPD.
    ///
    /// There are initializers from both DPD and BID. Converters to both
    /// formats are also available.
    var isBIDFormat: Bool { get }

    /// The number of bits required to represent the value's significand.
    ///
    /// If this value is a finite nonzero number, `significandDigitCount` is the
    /// number of decimal digits required to represent the value of
    /// `significand`; otherwise, `significandDigitCount` is -1. The value of
    /// `significandDigitCount` is always -1 or from one to the
    /// `significandMaxDigitCount`. For example:
    ///
    /// - For any representable power of ten, `significandDigitCount` is one, because
    ///   `significand` is `1`.
    /// - If `x` is 10, `x.significand` is `10` in decimal, so
    ///   `x.significandDigitCount` is 2.
    /// - If `x` is Decimal32.pi, `x.significand` is `3.141593` in
    ///   decimal, and `x.significandDigitCount` is 7.
    var significandDigitCount: Int { get }
}

extension DecimalFloatingPoint {

    /// The radix, or base of exponentiation, for a floating-point type.
    ///
    /// The magnitude of a floating-point value `x` of type `F` can be calculated
    /// by using the following formula, where `**` is exponentiation:
    ///
    ///     let magnitude = x.significand * F.radix ** x.exponent
    ///
    /// A conforming type may use any integer radix, but values other than 2 (for
    /// binary floating-point types) or 10 (for decimal floating-point types)
    /// are extraordinarily rare in practice.
    @inlinable public static var radix: Int { 10 }

    /// Creates a new floating-point value using the sign of one value and the
    /// magnitude of another.
    ///
    /// The following example uses this initializer to create a new `Double`
    /// instance with the sign of `a` and the magnitude of `b`:
    ///
    ///     let a = -21.5
    ///     let b = 305.15
    ///     let c = Decimal32(signOf: a, magnitudeOf: b)
    ///     print(c)
    ///     // Prints "-305.15"
    ///
    /// This initializer implements the IEEE 754 `copysign` operation.
    ///
    /// - Parameters:
    ///   - signOf: A value from which to use the sign. The result of the
    ///     initializer has the same sign as `signOf`.
    ///   - magnitudeOf: A value from which to use the magnitude. The result of
    ///     the initializer has the same magnitude as `magnitudeOf`.
    @inlinable public init(signOf: Self, magnitudeOf: Self) {
        self.init(
          sign: signOf.sign,
          exponentBitPattern: magnitudeOf.exponentBitPattern,
          significandDigits: magnitudeOf.significandDigits
        )
    }
    
    public // @testable
    static func _convert<Source: DecimalFloatingPoint>(from source: Source) -> (value: Self, exact: Bool) {
        let isMinus = source.sign == .minus
        guard !source.isZero else { return (isMinus ? -0.0 : 0, true) }
        
        guard source.isFinite else {
            if source.isInfinite { return (isMinus ? -.infinity : .infinity, true) }
            
            // IEEE 754 requires that any NaN payload be propagated, if possible.
            let digitsAllowed = Self.significandMaxDigitCount
            let digitsAvailable = source.significandDigits.count
            let payload = Array(source.significandDigits.dropLast(max(0,digitsAvailable-digitsAllowed)))

            // Although .signalingNaN.exponentBitPattern == .nan.exponentBitPattern,
            // we do not *need* to rely on this relation, and therefore we do not.
            let value = source.isSignalingNaN
            ? Self(
                sign: source.sign,
                exponentBitPattern: Self.signalingNaN.exponentBitPattern,
                significandDigits: payload)
            : Self(
                sign: source.sign,
                exponentBitPattern: Self.nan.exponentBitPattern,
                significandDigits: payload)
            // We define exactness by equality after roundtripping; since NaN is never
            // equal to itself, it can never be converted exactly.
            return (value, false)
        }
        
        let exponent = source.exponent
        var exemplar = Self.leastNormalMagnitude
        let exponentBitPattern: Self.RawExponent
        let significandDigits = source.significandDigits
        
        if exponent < exemplar.exponent {
            // The floating-point result is either zero or subnormal.
            exemplar = Self.leastNonzeroMagnitude
            let minExponent = exemplar.exponent
            if exponent + 1 < minExponent {
                return (isMinus ? -0.0 : 0, false)
            }
            if _slowPath(exponent + 1 == minExponent) {
                // Although the most significant bit (MSB) of a subnormal source
                // significand is explicit, Swift BinaryFloatingPoint APIs actually
                // omit any explicit MSB from the count represented in
                // significandWidth. For instance:
                //
                //   Double.leastNonzeroMagnitude.significandWidth == 0
                //
                // Therefore, we do not need to adjust our work here for a subnormal
                // source.
                return source.significandDigitCount == 0
                    ? (isMinus ? -0.0 : 0, false)
                    : (isMinus ? -exemplar : exemplar, false)
            }
            
            exponentBitPattern = 0 as Self.RawExponent
        } else {
            // The floating-point result is either normal or infinite.
            exemplar = Self.greatestFiniteMagnitude
            if exponent > exemplar.exponent {
                return (isMinus ? -.infinity : .infinity, false)
            }
            exponentBitPattern = exponent < 0
                ? (1 as Self).exponentBitPattern - Self.RawExponent(-exponent)
                : (1 as Self).exponentBitPattern + Self.RawExponent(exponent)
        }

        let value = Self(
            sign: source.sign,
            exponentBitPattern: exponentBitPattern,
            significandDigits: significandDigits)

//        if source.significandDigitCount <= leadingBitIndex {
//            return (value, true)
//        }
//        // We promise to round to the closest representation. Therefore, we must
//        // take a look at the bits that we've just truncated.
//        let ulp = (1 as Source.RawSignificand) << -shift
//        let truncatedBits = source.significandDigits & (ulp - 1)
//        if truncatedBits < ulp / 2 {
//            return (value, false)
//        }
//        let rounded = isMinus ? value.nextDown : value.nextUp
//        if _fastPath(truncatedBits > ulp / 2) {
//            return (rounded, false)
//        }
//        // If two representable values are equally close, we return the value with
//        // more trailing zeros in its significand bit pattern.
//        return significandDigits > rounded.significandDigits ? (value, false) : (rounded, false)
        return (0, false)
    }

    /// Creates a new instance from the given value, rounded to the closest
    /// possible representation.
    ///
    /// If two representable values are equally close, the result is the value
    /// with more trailing zeros in its significand bit pattern.
    ///
    /// - Parameter value: A floating-point value to be converted.
    @inlinable public init<Source>(_ value: Source) where Source : DecimalFloatingPoint {
        self = Self(value)
    }

    /// Creates a new instance from the given value, if it can be represented
    /// exactly.
    ///
    /// If the given floating-point value cannot be represented exactly, the
    /// result is `nil`.
    ///
    /// - Parameter value: A floating-point value to be converted.
    public init?<Source>(exactly value: Source) where Source : DecimalFloatingPoint {
        if value.isNaN { return nil }
        
        if (Source.exponentMaximum > Self.exponentMaximum ||
            Source.significandMaxDigitCount > Self.significandMaxDigitCount) &&
            value.isFinite && !value.isZero {
            let exponent = value.exponent
            if exponent < Self.leastNormalMagnitude.exponent {
                if exponent < Self.leastNonzeroMagnitude.exponent { return nil }
                if value.significandDigitCount >
                    Int(Self.Exponent(exponent) - Self.leastNonzeroMagnitude.exponent) {
                    return nil
                }
            } else {
                if exponent > Self.greatestFiniteMagnitude.exponent { return nil }
                if value.significandDigitCount > Self.greatestFiniteMagnitude.significandDigitCount {
                    return nil
                }
            }
        }
        
        self = Self(value)
    }

    /// Returns a Boolean value indicating whether this instance should precede
    /// or tie positions with the given value in an ascending sort.
    ///
    /// This relation is a refinement of the less-than-or-equal-to operator
    /// (`<=`) that provides a total order on all values of the type, including
    /// signed zeros and NaNs.
    ///
    /// The following example uses `isTotallyOrdered(belowOrEqualTo:)` to sort an
    /// array of floating-point values, including some that are NaN:
    ///
    ///     var numbers = [2.5, 21.25, 3.0, .nan, -9.5]
    ///     numbers.sort { !$1.isTotallyOrdered(belowOrEqualTo: $0) }
    ///     print(numbers)
    ///     // Prints "[-9.5, 2.5, 3.0, 21.25, nan]"
    ///
    /// The `isTotallyOrdered(belowOrEqualTo:)` method implements the total order
    /// relation as defined by the [IEEE 754 specification][spec].
    ///
    /// [spec]: http://ieeexplore.ieee.org/servlet/opac?punumber=4610933
    ///
    /// - Parameter other: A floating-point value to compare to this value.
    /// - Returns: `true` if this value is ordered below or the same as `other`
    ///   in a total ordering of the floating-point type; otherwise, `false`.
    public func isTotallyOrdered(belowOrEqualTo other: Self) -> Bool {
        // Quick return when possible.
        if self < other { return true }
        if self > other { return false }  // bug in original code? "other > self"
        
        // Self and other are either equal or unordered.
        // Every negative-signed value (even NaN) is less than every positive-
        // signed value, so if the signs do not match, we simply return the
        // sign bit of self.
        if sign != other.sign { return sign == .minus }
        
        // Handle Nan and infinity
        if isNaN && !other.isNaN { return false }
        if !isNaN && other.isNaN { return true }
        if isInfinite && !other.isInfinite { return false }
        if !isInfinite && other.isInfinite { return true }
        
        // Sign bits match; look at exponents.
        if exponentBitPattern > other.exponentBitPattern { return sign == .minus }
        if exponentBitPattern < other.exponentBitPattern { return sign == .plus }
        
        // Signs and exponents match, look at significands.
        if significandDigits.count > other.significandDigits.count {
            return sign == .minus
        }
        if significandDigits.count < other.significandDigits.count {
            return sign == .plus
        }
        
        // Same sized significands -- compare them
        if significandDigits.lexicographicallyPrecedes(other.significandDigits) { return sign == .minus }
        if other.significandDigits.lexicographicallyPrecedes(significandDigits) { return sign == .plus }
        //  Sign, exponent, and significand all match.
        return true
    }

}

extension DecimalFloatingPoint {
    
    
    static func _decimalLogarithm<Source:BinaryInteger>(_ x:Source) -> (exp:Int, digits:[UInt8]) {
        assert(x > (0 as Source))  // negatives and zero are illegal
        var digits = [UInt8]()
        let ten = (10 as Source)
        var expx10 = 0
        var n = x
        while n > ten {
            expx10 += 1
            let x = n.quotientAndRemainder(dividingBy: ten)
            digits.append(UInt8(x.remainder))
            n = x.quotient
        }
        return (expx10, digits)
    }
    
    public // @testable
    static func _convert<Source:BinaryInteger>(from source: Source) -> (value: Self, exact: Bool) {
        //  Note: Self's exponent is x10ⁿ where n is the radix 10 exponent whereas Source's
        //  exponent is x2ª where a is the radix 2 exponent.
        //  Useful constants:
        let exponentBias = (1 as Self).exponentBitPattern
        
        //  Zero is really extra simple, and saves us from trying to normalize a
        //  value that cannot be normalized.
        if _fastPath(source == 0) { return (0, true) }
        
        //  We now have a non-zero value; convert it to a strictly positive value
        //  by taking the magnitude.
        let expMag = _decimalLogarithm(source.magnitude)  // need a x10ⁿ exponent & mantissa digits
        
        //  If the exponent would be larger than the largest representable
        //  exponent, the result is just an infinity of the appropriate sign.
        guard expMag.exp <= Self.greatestFiniteMagnitude.exponent else {
            return (Source.isSigned && source < 0 ? -.infinity : .infinity, false)
        }
        
        //  Rounding occurs automatically based on the number of
        //  significandDigits in the initializer.
        let value = Self(
            sign: Source.isSigned && source < 0 ? .minus : .plus,
            exponentBitPattern: exponentBias,
            significandDigits: expMag.digits
        )
        return (value, expMag.exp <= Self.significandMaxDigitCount)
    }

    /// Creates a new value, rounded to the closest possible representation.
    ///
    /// If two representable values are equally close, the result is the value
    /// with more trailing zeros in its significand bit pattern.
    ///
    /// - Parameter value: The integer to convert to a floating-point value.
    @inlinable public init<Source:BinaryInteger>(_ value: Source) {
        self = Self._convert(from: value).value
    }

    /// Creates a new value, if the given integer can be represented exactly.
    ///
    /// If the given integer cannot be represented exactly, the result is `nil`.
    ///
    /// - Parameter value: The integer to convert to a floating-point value.
    @inlinable public init?<Source>(exactly value: Source) where Source : BinaryInteger {
        let (value_, exact) = Self._convert(from: value)
        guard exact else { return nil }
        self = value_
    }

    /// Returns a random value within the specified range, using the given
    /// generator as a source for randomness.
    ///
    /// Use this method to generate a floating-point value within a specific
    /// range when you are using a custom random number generator. This example
    /// creates three new values in the range `10.0 ..< 20.0`.
    ///
    ///     for _ in 1...3 {
    ///         print(Double.random(in: 10.0 ..< 20.0, using: &myGenerator))
    ///     }
    ///     // Prints "18.1900709259179"
    ///     // Prints "14.2286325689993"
    ///     // Prints "13.1485686260762"
    ///
    /// The `random(in:using:)` static method chooses a random value from a
    /// continuous uniform distribution in `range`, and then converts that value
    /// to the nearest representable value in this type. Depending on the size
    /// and span of `range`, some concrete values may be represented more
    /// frequently than others.
    ///
    /// - Note: The algorithm used to create random values may change in a future
    ///   version of Swift. If you're passing a generator that results in the
    ///   same sequence of floating-point values each time you run your program,
    ///   that sequence may change when your program is compiled using a
    ///   different version of Swift.
    ///
    /// - Parameters:
    ///   - range: The range in which to create a random value.
    ///     `range` must be finite and non-empty.
    ///   - generator: The random number generator to use when creating the
    ///     new random value.
    /// - Returns: A random value within the bounds of `range`.
    @inlinable public static func random<T>(in range: Range<Self>, using generator: inout T) -> Self where T : RandomNumberGenerator {
        precondition(!range.isEmpty, "Can't get random value with an empty range")
        let delta = range.upperBound - range.lowerBound
        //  TODO: this still isn't quite right, because the computation of delta
        //  can overflow (e.g. if .upperBound = .maximumFiniteMagnitude and
        //  .lowerBound = -.upperBound); this should be re-written with an
        //  algorithm that handles that case correctly, but this precondition
        //  is an acceptable short-term fix.
        precondition(delta.isFinite, "There is no uniform distribution on an infinite range")
        let max = delta.significandDigits.reduce(into: 0) { $0 = $0 * 10 + UInt($1) } // delta maximum as integer
        let r = generator.next(upperBound: max) // get a random integer up to the maximum
        
        // convert the integer to a Decimal number and scale to delta range
        var d = Self.init(sign: delta.sign, exponent: Self.Exponent(delta.exponentBitPattern), significand: Self.init(r))
        d += range.lowerBound // add the lower bound
        if d == range.upperBound { return random(in: range, using: &generator) }  // try again
        return d
    }

    /// Returns a random value within the specified range.
    ///
    /// Use this method to generate a floating-point value within a specific
    /// range. This example creates three new values in the range
    /// `10.0 ..< 20.0`.
    ///
    ///     for _ in 1...3 {
    ///         print(Double.random(in: 10.0 ..< 20.0))
    ///     }
    ///     // Prints "18.1900709259179"
    ///     // Prints "14.2286325689993"
    ///     // Prints "13.1485686260762"
    ///
    /// The `random()` static method chooses a random value from a continuous
    /// uniform distribution in `range`, and then converts that value to the
    /// nearest representable value in this type. Depending on the size and span
    /// of `range`, some concrete values may be represented more frequently than
    /// others.
    ///
    /// This method is equivalent to calling `random(in:using:)`, passing in the
    /// system's default random generator.
    ///
    /// - Parameter range: The range in which to create a random value.
    ///   `range` must be finite and non-empty.
    /// - Returns: A random value within the bounds of `range`.
    @inlinable public static func random(in range: Range<Self>) -> Self {
        var g = SystemRandomNumberGenerator()
        return random(in: range, using: &g)
    }

    /// Returns a random value within the specified range, using the given
    /// generator as a source for randomness.
    ///
    /// Use this method to generate a floating-point value within a specific
    /// range when you are using a custom random number generator. This example
    /// creates three new values in the range `10.0 ... 20.0`.
    ///
    ///     for _ in 1...3 {
    ///         print(Double.random(in: 10.0 ... 20.0, using: &myGenerator))
    ///     }
    ///     // Prints "18.1900709259179"
    ///     // Prints "14.2286325689993"
    ///     // Prints "13.1485686260762"
    ///
    /// The `random(in:using:)` static method chooses a random value from a
    /// continuous uniform distribution in `range`, and then converts that value
    /// to the nearest representable value in this type. Depending on the size
    /// and span of `range`, some concrete values may be represented more
    /// frequently than others.
    ///
    /// - Note: The algorithm used to create random values may change in a future
    ///   version of Swift. If you're passing a generator that results in the
    ///   same sequence of floating-point values each time you run your program,
    ///   that sequence may change when your program is compiled using a
    ///   different version of Swift.
    ///
    /// - Parameters:
    ///   - range: The range in which to create a random value. Must be finite.
    ///   - generator: The random number generator to use when creating the
    ///     new random value.
    /// - Returns: A random value within the bounds of `range`.
    @inlinable public static func random<T>(in range: ClosedRange<Self>, using generator: inout T) -> Self where T : RandomNumberGenerator {
        precondition(!range.isEmpty, "Can't get random value with an empty range")
        let delta = range.upperBound - range.lowerBound
        //  TODO: this still isn't quite right, because the computation of delta
        //  can overflow (e.g. if .upperBound = .maximumFiniteMagnitude and
        //  .lowerBound = -.upperBound); this should be re-written with an
        //  algorithm that handles that case correctly, but this precondition
        //  is an acceptable short-term fix.
        precondition(delta.isFinite, "There is no uniform distribution on an infinite range")
        let max = delta.significandDigits.reduce(into: 0) { $0 = $0 * 10 + UInt($1) } // delta maximum as integer
        let r = generator.next(upperBound: max) // get a random integer up to the maximum
        
        // convert the integer to a Decimal number and scale to delta range
        var d = Self.init(sign: delta.sign, exponent: Self.Exponent(delta.exponentBitPattern), significand: Self.init(r))
        d += range.lowerBound // add the lower bound
        return d
    }

    /// Returns a random value within the specified range.
    ///
    /// Use this method to generate a floating-point value within a specific
    /// range. This example creates three new values in the range
    /// `10.0 ... 20.0`.
    ///
    ///     for _ in 1...3 {
    ///         print(Double.random(in: 10.0 ... 20.0))
    ///     }
    ///     // Prints "18.1900709259179"
    ///     // Prints "14.2286325689993"
    ///     // Prints "13.1485686260762"
    ///
    /// The `random()` static method chooses a random value from a continuous
    /// uniform distribution in `range`, and then converts that value to the
    /// nearest representable value in this type. Depending on the size and span
    /// of `range`, some concrete values may be represented more frequently than
    /// others.
    ///
    /// This method is equivalent to calling `random(in:using:)`, passing in the
    /// system's default random generator.
    ///
    /// - Parameter range: The range in which to create a random value. Must be finite.
    /// - Returns: A random value within the bounds of `range`.
    @inlinable public static func random(in range: ClosedRange<Self>) -> Self {
        var g = SystemRandomNumberGenerator()
        return random(in: range, using: &g)
    }
}

