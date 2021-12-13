import Foundation

public struct MGDecimal128  {
    
    // Binary Integer Decimal implementation
    private typealias BID128 = UInt128
    private let dn128: BID128     // Note: this includes a sign bit, 17-bit combination, and 110-bits of significand
    
    // Masks
    private static let infinityMask = UInt(0b11111)
    private static let infinity = UInt(0b11110)
    private static let signalBit = UInt(1) << 11
    private static let Nan = UInt(0b11111)
    private static let mask2Bits = UInt(0b11)
    private static let negativeBit = UInt128(1) << 127
    private static let significandMask = ~UInt128(negativeBit | UInt128(0x1FFFF) << 110)
    private static let maxExponent = 6144
    
    private static let maxSignificand = UInt128("9999999999999999999999999999999999")
    
    public static func test() {
//        let x = UInt128(1000)
//        let a = Decimal(2)
//        let y = MGDecimal128.maxSignificand
        let x = MGDecimal128(Int64(-1234567890))
        let s = x.description
        print(s)
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
    
    public init(_ value: Int64) {
        // add the sign bit
        if value < 0 {
            self.init(sign: .minus, exponent: 0, mantissa: UInt128(-value))
        } else {
            self.init(sign: .plus, exponent: 0, mantissa: UInt128(value))
        }
    }
    
    public init(_ value: UInt64 = 0) {
        // exponent will always be zero in this case since only 63 bits are used
        self.init(sign: .plus, exponent: 0, mantissa: UInt128(Int64(value)))
    }
    
    private init(sign: FloatingPointSign, exponent: Int, mantissa: UInt128) {
        let maxExponent = MGDecimal128.maxExponent
        let maxSignificand = MGDecimal128.maxSignificand
        let negativeBit = MGDecimal128.negativeBit
        var num: UInt128 = 0
        let exp = exponent < 0 ? UInt(0x2000 - max(exponent, 1-maxExponent)) : UInt(min(maxExponent, exponent)) // convert to unsigned number from 0x0000 - 0x1FFF
        var significand = (mantissa > maxSignificand) ? 0 : mantissa  // standard says overflow on input is zero
        var combination = UInt(0)
        
        // add in negative bit
        if sign == .minus {
            num |= negativeBit
        }
        
        // generate combination field
        let sigNibble = UInt(significand >> 110)
        significand &= ~(UInt128(0b1111) << 110)  // clear significand upper nibble
        switch sigNibble {
            case 0b0000...0b0111:
                combination = (exp << 3) | sigNibble
            case 0b1000...0b1001:
                combination = (0b11 << 15) | (exp << 1) | (sigNibble & 0b1)
            default:
                break // shouldn't reach here
        }
        
        // add the combination & significand fields
        let shiftedBits =  UInt128(combination) << 110
        let combined = shiftedBits | significand
        num |= combined
        self.init(num)
    }
    
}

/// Numerical properties
///
extension MGDecimal128 {
    
    public var sign: FloatingPointSign { dn128 & MGDecimal128.negativeBit != 0 ? .minus : .plus }
    
    private var combinationField: UInt { UInt((dn128 >> 110) & 0x1FFFF) }
    private var upperBits: UInt { (combinationField >> 12) & MGDecimal128.infinityMask }
    
    private var _significand : BID128 {
        var significand = dn128 & MGDecimal128.significandMask
        let combField = combinationField
        let upperBits = (combField >> 12) & MGDecimal128.infinityMask
        if upperBits>>2 == MGDecimal128.mask2Bits {
            // dealing with two leading '1's
            significand |= UInt128((combField & 1) | 0b1000) << 110  // add lower bit of combination field + "1000" to upper bits of significand
        } else {
            // dealing with leading '01', '10', or '00'
            significand |= UInt128(combField & 0b111) << 110   // add lower 3 bits of combination field to upper bits of significand
        }
        return significand
    }
    
    public var significand: MGDecimal128 { MGDecimal128(sign: .plus, exponent: 0, mantissa: _significand) }
    
    public var decimal: Decimal {
        return 0
    }
    
    public var exponent: Int {
        let combField = combinationField
        let upperBits = (combField >> 12) & MGDecimal128.infinityMask
        let exp: UInt
        if upperBits>>2 == MGDecimal128.mask2Bits {
            // dealing with two leading '1's
            exp = UInt((combField >> 1) & 0x3FFF)         // exp = mid 14 bits of combination field after '11' prefix
        } else {
            // dealing with leading '01', '10', or '00'
            exp = UInt(combField >> 3)                    // exp = upper 14 bits of combination field
        }
        
        // Convert exponent to a signed integer
        return exp > MGDecimal128.maxExponent ? Int(exp) - 0x2000 : Int(exp)
    }
    
    public var isZero: Bool { significand == 0 }
    public var isSignMinus: Bool { sign == .minus }
    public var isInfinite: Bool { upperBits == MGDecimal128.infinity }
    public var isNaN: Bool { upperBits == MGDecimal128.Nan }
    public var isSignaling: Bool { isNaN && (combinationField & MGDecimal128.signalBit != 0) }
    public var isFinite: Bool { isZero || !(isInfinite || isNaN) }
    
}

/// special constants
///
extension MGDecimal128 {
   
    static let greatestFiniteMagnitude = MGDecimal128(sign: .plus, exponent: 0, mantissa: 0)
    static let leastFiniteMagnitude = MGDecimal128()
    
    static let radix = 10
    static let pi = MGDecimal128()
    static let nan = MGDecimal128()
    static let quietNaN = MGDecimal128()

}

extension MGDecimal128 : SignedNumeric {

    public init?<T>(exactly source: T) where T : BinaryInteger {
        self.init(Int64(source))
    }
    
    public var magnitude: MGDecimal128 {
        return 0
    }
    
    public static func * (lhs: MGDecimal128, rhs: MGDecimal128) -> MGDecimal128 {
        return lhs
    }
    
    public static func *= (result: inout MGDecimal128, arg: MGDecimal128) {
        // TBD
    }

}

extension MGDecimal128 : Comparable {
    
    public static func < (lhs: MGDecimal128, rhs: MGDecimal128) -> Bool {
        return true
    }
    
}

extension MGDecimal128 : AdditiveArithmetic {
    
    public static func - (lhs: MGDecimal128, rhs: MGDecimal128) -> MGDecimal128 {
        return lhs
    }
    
    public static func + (lhs: MGDecimal128, rhs: MGDecimal128) -> MGDecimal128 {
        return lhs
    }
    
}

extension MGDecimal128 : ExpressibleByIntegerLiteral {
    
    public init(integerLiteral value: Int64) { self.init(value) }
  
}

extension MGDecimal128 : ExpressibleByFloatLiteral {
    
    public init(floatLiteral value: Double) {
        // TBD
        self.init()
    }

}

extension MGDecimal128 : Strideable {
    
    public func distance(to other: MGDecimal128) -> MGDecimal128 {
        return 0
    }
    
    public func advanced(by n: MGDecimal128) -> MGDecimal128 {
        return 0
    }
     
}

extension MGDecimal128 : Codable { }  // Supported by default methods
extension MGDecimal128 : Hashable { } // Supported by default methods

extension MGDecimal128 : CustomStringConvertible {
    
    // Produce a textual representation of the number
    public var description: String {
        var string = isSignMinus ? "-" : ""
        
        // Check for special numbers & extract exponent and significand
        if isInfinite { return string + "Infinity" }
        else if isNaN { return "NaN" } // ignore sign
        else if isZero { return "0" }
        
        // Convert the significand to a string
        string += _significand.description
        if exponent != 0 {
            string += "e" + exponent.description
        }
        return string
    }
   
}
