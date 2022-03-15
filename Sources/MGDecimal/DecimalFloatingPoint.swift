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
/// with operations specific to floating-point binary types, as defined by the
/// [IEEE 754 specification][spec]. `DecimalFloatingPoint` is implemented in
/// the standard library by `Decimal32`, `Decimal64`, and `Decimal128` where available.
///
/// [spec]: http://ieeexplore.ieee.org/servlet/opac?punumber=4610933
public protocol DecimalFloatingPoint : ExpressibleByFloatLiteral, FloatingPoint {

    /// A type that represents the encoded exponent of a value.
    associatedtype RawExponent : UnsignedInteger

    /// Creates a new instance from the specified sign and bit patterns.
    ///
    /// The values passed as `exponentBitPattern` and `significandBitPattern` are
    /// interpreted in the binary interchange format defined by the [IEEE 754
    /// specification][spec].
    ///
    /// [spec]: http://ieeexplore.ieee.org/servlet/opac?punumber=4610933
    ///
    /// - Parameters:
    ///   - sign: The sign of the new value.
    ///   - exponentBitPattern: The bit pattern to use for the exponent field of
    ///     the new value.
    ///   - significandBitPattern: The bit pattern to use for the significand
    ///     field of the new value.
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

    /// The number of bits used to represent the type's exponent.
    ///
    /// A decimal floating-point type's `exponentBitCount` imposes a limit on the
    /// range of the exponent for normal, finite values. The *exponent bias* of
    /// a type `F` can be calculated as the following, where `**` is
    /// exponentiation:
    ///
    ///     let bias = 10 ** (F.exponentBitCount - 1) - 1
    ///
    /// The least normal exponent for values of the type `F` is `1 - bias`, and
    /// the largest finite exponent is `bias`. An all-zeros exponent is reserved
    /// for subnormals and zeros, and an all-ones exponent is reserved for
    /// infinity and NaN.
    ///
    /// For example, the `Decimal32` type has an `exponentBitCount` of 8, which gives
    /// an exponent bias of `127` by the calculation above.
    ///
    ///     let bias = 10 ** (Decimal32.exponentBitCount - 1) - 1
    ///     // bias == 127
    ///     print(Float.greatestFiniteMagnitude.exponent)
    ///     // Prints "127"
    ///     print(Float.leastNormalMagnitude.exponent)
    ///     // Prints "-126"
    static var exponentBitCount: Int { get }

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
    ///     let c = Double(signOf: a, magnitudeOf: b)
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
        guard !source.isZero else {
            return (source.sign == .minus ? -0.0 : 0, true)
        }
        
        guard source.isFinite else {
            if source.isInfinite {
                return (source.sign == .minus ? -.infinity : .infinity, true)
            }
            // IEEE 754 requires that any NaN payload be propagated, if possible.
//            let payload_ =
//            source.significandBitPattern &
//            ~(Source.nan.significandDigits |
//              Source.signalingNaN.significandDigits)
//            let mask =
//            Self.greatestFiniteMagnitude.significandDigits &
//            ~(Self.nan.significandDigits |
//              Self.signalingNaN.significandDigits)
//            let payload = Self.RawSignificand(truncatingIfNeeded: payload_) & mask
//            // Although .signalingNaN.exponentBitPattern == .nan.exponentBitPattern,
//            // we do not *need* to rely on this relation, and therefore we do not.
//            let value = source.isSignalingNaN
//            ? Self(
//                sign: source.sign,
//                exponentBitPattern: Self.signalingNaN.exponentBitPattern,
//                significandBitPattern: payload |
//                Self.signalingNaN.significandDigits)
//            : Self(
//                sign: source.sign,
//                exponentBitPattern: Self.nan.exponentBitPattern,
//                significandDigits: payload | Self.nan.significandDigits)
            // We define exactness by equality after roundtripping; since NaN is never
            // equal to itself, it can never be converted exactly.
            return (0, false)  /* TBD */
        }
        
        let exponent = source.exponent
        var exemplar = Self.leastNormalMagnitude
//        let exponentBitPattern: Self.RawExponent
//        let leadingBitIndex: Int
//        let shift: Int
//        let significandDigits: [UInt8]
        
        if exponent < exemplar.exponent {
            // The floating-point result is either zero or subnormal.
            exemplar = Self.leastNonzeroMagnitude
            let minExponent = exemplar.exponent
            if exponent + 1 < minExponent {
                return (source.sign == .minus ? -0.0 : 0, false)
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
                    ? (source.sign == .minus ? -0.0 : 0, false)
                    : (source.sign == .minus ? -exemplar : exemplar, false)
            }
            
//            exponentBitPattern = 0 as Self.RawExponent
//            leadingBitIndex = Int(Self.Exponent(exponent) - minExponent)
//            shift = leadingBitIndex &- (source.significandDigitCount &+ source.significandDigits)
//            let leadingBit = source.isNormal ? (1 as Self.RawSignificand) << leadingBitIndex : 0
//            significandDigits = leadingBit | (shift >= 0
//                                                  ? Self.RawSignificand(source.significandDigits) << shift
//                                                  : Self.RawSignificand(source.significandDigits) >> -shift))
        } else {
            // The floating-point result is either normal or infinite.
            exemplar = Self.greatestFiniteMagnitude
            if exponent > exemplar.exponent {
                return (source.sign == .minus ? -.infinity : .infinity, false)
            }
            
//            exponentBitPattern = exponent < 0
//                ? (1 as Self).exponentBitPattern - Self.RawExponent(-exponent)
//                : (1 as Self).exponentBitPattern + Self.RawExponent(exponent)
//            leadingBitIndex = exemplar.significandDigitCount
//            shift = leadingBitIndex &- (source.significandDigitCount &+ source.significandDigits)
//            let sourceLeadingBit = source.isSubnormal
//                ? (1 as Source.RawSignificand) << (source.significandDigitCount &+
//                   source.significandDigits)
//                : 0
//            significandDigits = shift >= 0
//                ? Self.RawSignificand(sourceLeadingBit ^ source.significandDigits) << shift
//                : Self.RawSignificand((sourceLeadingBit ^ source.significandDigits) >> -shift)
        }
//
//        let value = Self(
//            sign: source.sign,
//            exponentBitPattern: exponentBitPattern,
//            significandBitPattern: significandDigits)
//
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
//        let rounded = source.sign == .minus ? value.nextDown : value.nextUp
//        if _fastPath(truncatedBits > ulp / 2) {
//            return (rounded, false)
//        }
//        // If two representable values are equally close, we return the value with
//        // more trailing zeros in its significand bit pattern.
//        return significandDigits >
//            rounded.significandDigits ? (value, false) : (rounded, false)
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
        
        if (Source.exponentBitCount > Self.exponentBitCount
            || Source.significandMaxDigitCount > Self.significandMaxDigitCount)
            && value.isFinite && !value.isZero {
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
        if other > self { return false }
        // Self and other are either equal or unordered.
        // Every negative-signed value (even NaN) is less than every positive-
        // signed value, so if the signs do not match, we simply return the
        // sign bit of self.
        if sign != other.sign { return sign == .minus }
        // Sign bits match; look at exponents.
        if exponentBitPattern > other.exponentBitPattern { return sign == .minus }
        if exponentBitPattern < other.exponentBitPattern { return sign == .plus }
        // Signs and exponents match, look at significands.
//        if significandDigits > other.significandDigits {
//          return sign == .minus
//        }
//        if significandDigits < other.significandDigits {
//          return sign == .plus
//        }
        //  Sign, exponent, and significand all match.
        return true
    }

}

extension DecimalFloatingPoint {
    
    public // @testable
    static func _convert<Source: BinaryInteger>(from source: Source) ->
        (value: Self, exact: Bool) {
//      //  Useful constants:
//      let exponentBias = (1 as Self).exponentBitPattern
//      let significandMask = ((1 as RawSignificand) << Self.significandMaxDigitCount) &- 1
//      //  Zero is really extra simple, and saves us from trying to normalize a
//      //  value that cannot be normalized.
//      if _fastPath(source == 0) { return (0, true) }
//      //  We now have a non-zero value; convert it to a strictly positive value
//      //  by taking the magnitude.
//      let magnitude = source.magnitude
//      var exponent = magnitude._binaryLogarithm()
//      //  If the exponent would be larger than the largest representable
//      //  exponent, the result is just an infinity of the appropriate sign.
//      guard exponent <= Self.greatestFiniteMagnitude.exponent else {
//        return (Source.isSigned && source < 0 ? -.infinity : .infinity, false)
//      }
//      //  If exponent <= significandBitCount, we don't need to round it to
//      //  construct the significand; we just need to left-shift it into place;
//      //  the result is always exact as we've accounted for exponent-too-large
//      //  already and no rounding can occur.
//      if exponent <= Self.significandMaxDigitCount {
//        let shift = Self.significandMaxDigitCount &- exponent
//        let significand = RawSignificand(magnitude) &<< shift
//        let value = Self(
//          sign: Source.isSigned && source < 0 ? .minus : .plus,
//          exponentBitPattern: exponentBias + RawExponent(exponent),
//          significandBitPattern: significand
//        )
//        return (value, true)
//      }
//      //  exponent > significandBitCount, so we need to do a rounding right
//      //  shift, and adjust exponent if needed
//      let shift = exponent &- Self.significandMaxDigitCount
//      let halfway = (1 as Source.Magnitude) << (shift - 1)
//      let mask = 2 * halfway - 1
//      let fraction = magnitude & mask
//      var significand = RawSignificand(truncatingIfNeeded: magnitude >> shift) & significandMask
//      if fraction > halfway || (fraction == halfway && significand & 1 == 1) {
//        var carry = false
//        (significand, carry) = significand.addingReportingOverflow(1)
//        if carry || significand > significandMask {
//          exponent += 1
//          guard exponent <= Self.greatestFiniteMagnitude.exponent else {
//            return (Source.isSigned && source < 0 ? -.infinity : .infinity, false)
//          }
//        }
//      }
//      return (Self(
//        sign: Source.isSigned && source < 0 ? .minus : .plus,
//        exponentBitPattern: exponentBias + RawExponent(exponent),
//        significandBitPattern: significand
//      ), fraction == 0)
        return (0, false)
    }

    /// Creates a new value, rounded to the closest possible representation.
    ///
    /// If two representable values are equally close, the result is the value
    /// with more trailing zeros in its significand bit pattern.
    ///
    /// - Parameter value: The integer to convert to a floating-point value.
    @inlinable public init<Source>(_ value: Source) where Source : BinaryInteger {
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
//        let rand: Self.RawSignificand
//        if Self.RawSignificand.bitWidth == Self.significandMaxDigitCount + 1 {
//            rand = generator.next()
//        } else {
//            let significandCount = Self.significandMaxDigitCount + 1
//            let maxSignificand: Self.RawSignificand = 1 << significandCount
//            // Rather than use .next(upperBound:), which has to work with arbitrary
//            // upper bounds, and therefore does extra work to avoid bias, we can take
//            // a shortcut because we know that maxSignificand is a power of two.
//            rand = generator.next() & (maxSignificand - 1)
//        }
//       let unitRandom = Self.init(rand) * (Self.ulpOfOne / 2)
//        let randFloat = delta * unitRandom + range.lowerBound
//        if randFloat == range.upperBound {
//            return Self.random(in: range, using: &generator)
//        }
//        return randFloat
        return range.lowerBound /* TBD */
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
//        let rand: Self.RawSignificand
//        if Self.RawSignificand.bitWidth == Self.significandMaxDigitCount + 1 {
//            rand = generator.next()
//            let tmp: UInt8 = generator.next() & 1
//            if rand == Self.RawSignificand.max && tmp == 1 {
//                return range.upperBound
//            }
//        } else {
//            let significandCount = Self.significandMaxDigitCount + 1
//            let maxSignificand: Self.RawSignificand = 1 << significandCount
//            rand = generator.next(upperBound: maxSignificand + 1)
//            if rand == maxSignificand {
//                return range.upperBound
//            }
//        }
//        let unitRandom = Self.init(rand) * (Self.ulpOfOne / 2)
//        let randFloat = delta * unitRandom + range.lowerBound
//        return randFloat
        return range.lowerBound /* TBD */
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

