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

    /// A type that represents the encoded significand of a value.
    associatedtype RawSignificand : UnsignedInteger

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
    init(sign: FloatingPointSign, exponentBitPattern: Self.RawExponent, significandBitPattern: Self.RawSignificand)

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
    /// A binary floating-point type's `exponentBitCount` imposes a limit on the
    /// range of the exponent for normal, finite values. The *exponent bias* of
    /// a type `F` can be calculated as the following, where `**` is
    /// exponentiation:
    ///
    ///     let bias = 2 ** (F.exponentBitCount - 1) - 1
    ///
    /// The least normal exponent for values of the type `F` is `1 - bias`, and
    /// the largest finite exponent is `bias`. An all-zeros exponent is reserved
    /// for subnormals and zeros, and an all-ones exponent is reserved for
    /// infinity and NaN.
    ///
    /// For example, the `Float` type has an `exponentBitCount` of 8, which gives
    /// an exponent bias of `127` by the calculation above.
    ///
    ///     let bias = 2 ** (Float.exponentBitCount - 1) - 1
    ///     // bias == 127
    ///     print(Float.greatestFiniteMagnitude.exponent)
    ///     // Prints "127"
    ///     print(Float.leastNormalMagnitude.exponent)
    ///     // Prints "-126"
    static var exponentBitCount: Int { get }

    /// The available number of fractional significand bits.
    ///
    /// For fixed-width floating-point types, this is the actual number of
    /// fractional significand bits.
    ///
    /// For extensible floating-point types, `significandBitCount` should be the
    /// maximum allowed significand width (without counting any leading integral
    /// bit of the significand). If there is no upper limit, then
    /// `significandBitCount` should be `Int.max`.
    static var significandBitCount: Int { get }

    /// The raw encoding of the value's exponent field.
    ///
    /// This value is unadjusted by the type's exponent bias.
    var exponentBitPattern: Self.RawExponent { get }

    /// The raw encoding of the value's significand field.
    ///
    /// The `significandBitPattern` property does not include the leading
    /// integral bit of the significand, even for types like `Float80` that
    /// store it explicitly.
    var significandBitPattern: Self.RawSignificand { get }

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
    ///     let y = x.binade
    ///     // y == 10.0
    ///     // y.significand == 1.0
    ///     // y.exponent == 1
    var decade: Self { get }

    /// The number of bits required to represent the value's significand.
    ///
    /// If this value is a finite nonzero number, `significandWidth` is the
    /// number of fractional bits required to represent the value of
    /// `significand`; otherwise, `significandWidth` is -1. The value of
    /// `significandWidth` is always -1 or between zero and
    /// `significandBitCount`. For example:
    ///
    /// - For any representable power of two, `significandWidth` is zero, because
    ///   `significand` is `1.0`.
    /// - If `x` is 10, `x.significand` is `1.01` in binary, so
    ///   `x.significandWidth` is 2.
    /// - If `x` is Float.pi, `x.significand` is `1.10010010000111111011011` in
    ///   binary, and `x.significandWidth` is 23.
    var significandWidth: Int { get }
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
        let s = signOf.sign
        self = s == .minus ? -magnitudeOf.magnitude : magnitudeOf.magnitude
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
        nil /* TBD */
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
        true /* TBD */
    }

}

extension DecimalFloatingPoint where Self.RawSignificand : FixedWidthInteger {

    /// Creates a new value, rounded to the closest possible representation.
    ///
    /// If two representable values are equally close, the result is the value
    /// with more trailing zeros in its significand bit pattern.
    ///
    /// - Parameter value: The integer to convert to a floating-point value.
    @inlinable public init<Source>(_ value: Source) where Source : BinaryInteger {
        self.init(0) /* TBD */
    }

    /// Creates a new value, if the given integer can be represented exactly.
    ///
    /// If the given integer cannot be represented exactly, the result is `nil`.
    ///
    /// - Parameter value: The integer to convert to a floating-point value.
    @inlinable public init?<Source>(exactly value: Source) where Source : BinaryInteger {
        self.init(0) /* TBD */
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
        random(in: range.lowerBound...range.upperBound, using: &generator)
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
        var r = SystemRandomNumberGenerator()
        return random(in: range, using: &r)
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
        range.lowerBound /* TBD */
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
        var r = SystemRandomNumberGenerator()
        return random(in: range, using: &r)
    }
}

