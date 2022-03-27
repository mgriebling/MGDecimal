//
//  File.swift
//  
//
//  Created by Mike Griebling on 2022-03-24.
//

import Foundation

public struct UInt128 : Equatable, Comparable, Codable, CustomStringConvertible, ExpressibleByStringLiteral,
                        ExpressibleByIntegerLiteral, Hashable {

    var hi: UInt64, lo: UInt64
    
    /// encapsulate the endianness here
    static let HIGHWORD = isBigEndian ? 0 : 1
    static let LOWWORD  = isBigEndian ? 1 : 0
    
    /// basic initializers
    init(w: [UInt64]) { hi=w[UInt128.HIGHWORD]; lo=w[UInt128.LOWWORD] } // internal use
    public init(_ value:UInt = 0) { self.init(upper: 0, lower: UInt64(value)) }
    public init(upper:UInt64, lower:UInt64) { hi=upper; lo=lower }
    public init(stringLiteral value: String) { self.init(value, radix: 10)! }
    public init(integerLiteral value: UInt) { self.init(value) }
    public init(_ value:Int) {
        if value < 0 { self.init() }
        self.init(UInt(value))
    }
    
    public init?(_ value: String, radix:Int=10) {
        // clean up the input string, ignoring white space, signs and underscores
        guard radix > 1 && radix <= 36 else { return nil }
        let trimSet = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "+-"))
        var s = value.trimmingCharacters(in: trimSet).replacingOccurrences(of: "_", with: "")
        
        // set the radix if needed
        var radix = UInt64(radix)
        if s.hasPrefix("0x") { radix = 16; s.removeFirst(2) }
        if s.hasPrefix("0o") { radix =  8; s.removeFirst(2) }
        if s.hasPrefix("0b") { radix =  2; s.removeFirst(2) }
        
        // determine how many digits we can convert at once -- limited by UInt64.max
        var scale = UInt64(1)
        var digits = 0
        while scale < UInt64.max/radix {
            scale *= radix; digits += 1
        }
        
        // optimization for multiple of two radices
        var bitShift = 0
        if radix & (radix-1) == 0 {
            // radices that are multiples of two
            bitShift = digits * radix.trailingZeroBitCount
        }
        
        // convert the string into an extended integer
        var x = UInt128(), c = UInt64()
        while !s.isEmpty {
            let piece = s.prefix(digits); s = String(s.dropFirst(digits))
            if piece.count < digits {
                // determine new scaling/shift values
                digits = piece.count
                if bitShift != 0 { bitShift = digits * radix.trailingZeroBitCount }
                else { scale=1; while digits>0 { scale *= radix; digits-=1 } }
            }
            guard let n = UInt64(piece, radix: Int(radix)) else { return nil }
            if bitShift != 0 {
                // multiples of two can be optimized by shifting: x <<= bitShift
                x = sll128(x.hi, x.lo, bitShift)
            } else {
                // x *= scale
                __mul_64x128_full(&c, &x, scale, x)
            }
            __add_128_64(&x, x, n)  // x += n
        }
        self = x
    }
    
    func getBit<T:FixedWidthInteger>(x:T, bit:Int) -> Int {
        guard bit >= 0 && bit < T.bitWidth else { return 0 }
        let b = x & (T(1) << bit)
        return b != T(0) ? 1 : 0
    }
    
    // algorithm from Verilog hardware binary/BCD converter by Nic McDonald
    func binaryToBCD(x:UInt128) -> [UInt8] {
        let bits = x.bitWidth - x.leadingZeroBitCount
        var x = x
        var res = [UInt8](repeating: 0, count: 40) // 40 digit answer
        for _ in 1...bits {
            // adjust digits
            for j in 0..<res.count {
                if res[j] >= 5 { res[j] += 3 }
            }
            
            // shift digits left one position
            var carry = UInt8(getBit(x: x, bit: bits-1))
            x = sll128(x.hi, x.lo, 1) //x << 1
            for j in (0..<res.count).reversed() {
                res[j] = (res[j] << 1 | carry)
                carry = res[j] >> 4; res[j] &= 0xF
            }
        }
        return Array(res.drop { $0 == 0 } )  // drop leading zeros
    }
    
    /// CustomStringConvertible compliance
    public var description: String { binaryToBCD(x: self).reduce(into: "") { $0 += String($1, radix: 10) } }
    
    /// Comparable compliance
    public static func < (lhs: UInt128, rhs: UInt128) -> Bool { (lhs.hi < rhs.hi) || (lhs.hi == rhs.hi && lhs.lo < rhs.lo) }
    
    /// Equatable compliance
    public static func == (lhs: UInt128, rhs: UInt128) -> Bool { lhs.lo == rhs.lo && lhs.hi == rhs.hi }
    public static func != (lhs: UInt128, rhs: UInt128) -> Bool { lhs.lo != rhs.lo || lhs.hi != rhs.hi }
    
}

extension UInt128 : FixedWidthInteger {
    
    public init?<T>(exactly source: T) where T : BinaryFloatingPoint {
        if source.isZero { self = UInt128() }
        else if source.exponent < 0 || source.rounded() != source { return nil }
        else { self = UInt128(UInt64(source)) }
    }
    public init<T>(_ source: T) where T : BinaryInteger { self.init(UInt(source)) }
    public init<T:BinaryFloatingPoint>(_ source: T) { self.init(UInt64(source)) }
    public init(bigEndian value: UInt128) { self = value.bigEndian }
    public init(littleEndian value: UInt128) { self = value.littleEndian }
    
    /// Creates a UInt128 from a given value, with the input's value
    /// truncated to a size no larger than what UInt128 can handle.
    /// Since the input is constrained to an UInt, no truncation needs
    /// to occur, as a UInt is currently 64 bits at the maximum.
    public init(_truncatingBits bits: UInt) { self.init(upper: 0, lower: UInt64(bits)) }
    
}

extension UInt128 : UnsignedInteger {
    
    public var bigEndian: UInt128 { self }
    public var littleEndian: UInt128 { self }
    
    public var byteSwapped: UInt128 { UInt128(upper: lo.byteSwapped, lower: hi.byteSwapped) }
 
}

extension UInt128 : BinaryInteger {
    
    public static var max: UInt128 { UInt128(upper: UInt64.max, lower: UInt64.max) }
    public static var min: UInt128 { UInt128(0) }
    
    public func addingReportingOverflow(_ rhs: UInt128) -> (partialValue: UInt128, overflow: Bool) {
        var res: UInt128 = 0, c = UInt64(), s = UInt64()
        __add_128_128(&res, self, rhs)
        __add_carry_out(&s, &c, self.hi, rhs.hi)
        return (res, c != 0)
    }
    
    public func subtractingReportingOverflow(_ rhs: UInt128) -> (partialValue: UInt128, overflow: Bool) {
        var res: UInt128 = 0, c = UInt64(), s = UInt64()
        __sub_128_128(&res, self, rhs)
        __sub_borrow_out(&s, &c, self.hi, rhs.hi)
        return (res, c != 0)
    }
    
    public func multipliedReportingOverflow(by rhs: UInt128) -> (partialValue: UInt128, overflow: Bool) {
        var ph = UInt128(), pl = UInt128()
        __mul_128x128_full(&ph, &pl, self, rhs)
        return (pl, ph != 0)
    }
    
    public func dividedReportingOverflow(by rhs: UInt128) -> (partialValue: UInt128, overflow: Bool) {
        assert(false, "\(#function) not implemented")
        return (0, false)
    }
    
    public func remainderReportingOverflow(dividingBy rhs: UInt128) -> (partialValue: UInt128, overflow: Bool) {
        assert(false, "\(#function) not implemented")
        return (0, false)
    }
    
    public func dividingFullWidth(_ dividend: (high: UInt128, low: UInt128)) -> (quotient: UInt128, remainder: UInt128) {
        assert(false, "\(#function) not implemented")
        return (0, 0) /* TBD */
    }

    public typealias Words = [UInt]
    public var words: [UInt] { [UInt(lo), UInt(hi)] }
    
    public static var isSigned: Bool { false }
    public static var bitWidth: Int { UInt64.bitWidth * 2 }
    
    public var leadingZeroBitCount: Int { hi == 0 ? hi.bitWidth + lo.leadingZeroBitCount : hi.leadingZeroBitCount }
    public var nonzeroBitCount: Int { hi.nonzeroBitCount + lo.nonzeroBitCount }
    public var trailingZeroBitCount: Int { lo.trailingZeroBitCount }
    public var bitWidth: Int { lo.bitWidth * 2 }
    public var magnitude: UInt128 { self }
    
    public static func - (lhs: UInt128, rhs: UInt128) -> UInt128 {
        let res = lhs.subtractingReportingOverflow(rhs)
        assert(!res.overflow, "UInt128: subtraction overflow!")
        return res.partialValue
    }
    
    public static func + (lhs: UInt128, rhs: UInt128) -> UInt128 {
        let res = lhs.addingReportingOverflow(rhs)
        assert(!res.overflow, "UInt128: addition overflow!")
        return res.partialValue
    }
    
    public static func * (lhs: UInt128, rhs: UInt128) -> UInt128 {
        let res = lhs.multipliedReportingOverflow(by: rhs)
        assert(!res.overflow, "UInt128: multiplication overflow!")
        return res.partialValue
    }
    
    public static func / (lhs: UInt128, rhs: UInt128) -> UInt128 {
        assert(rhs != 0, "UInt128: division by zero")
        guard lhs >= rhs else { return 0 } // underflow
        if lhs == rhs { return 1 }
        if lhs == 0 { return 0 }
        let res = lhs.dividedReportingOverflow(by: rhs)
        assert(!res.overflow, "UInt128: division overflow!")
        return res.partialValue
    }
    
    public static func % (lhs: UInt128, rhs: UInt128) -> UInt128 {
        assert(false, "\(#function) not implemented")
        return lhs /* TBD */
    }
    
    public static func & (lhs: UInt128, rhs: UInt128) -> UInt128 { UInt128(upper:lhs.hi & rhs.hi, lower:lhs.lo & rhs.lo) }
    public static func | (lhs: UInt128, rhs: UInt128) -> UInt128 { UInt128(upper:lhs.hi | rhs.hi, lower:lhs.lo | rhs.lo) }
    public static func ^ (lhs: UInt128, rhs: UInt128) -> UInt128 { UInt128(upper:lhs.hi ^ rhs.hi, lower:lhs.lo ^ rhs.lo) }
    public static func << <RHS:BinaryInteger>(lhs: UInt128, rhs: RHS) -> UInt128 { sll128(lhs.hi, lhs.lo, Int(rhs)) }
    public static func >> <RHS:BinaryInteger>(lhs: UInt128, rhs: RHS) -> UInt128 { srl128(lhs.hi, lhs.lo, Int(rhs)) }
    
    public static func *= (lhs: inout UInt128, rhs: UInt128) { lhs = lhs * rhs }
    public static func %= (lhs: inout UInt128, rhs: UInt128) { lhs = lhs % rhs }
    public static func /= (lhs: inout UInt128, rhs: UInt128) { lhs = lhs / rhs }
    public static func &= (lhs: inout UInt128, rhs: UInt128) { lhs = lhs & rhs }
    public static func |= (lhs: inout UInt128, rhs: UInt128) { lhs = lhs | rhs }
    public static func ^= (lhs: inout UInt128, rhs: UInt128) { lhs = lhs ^ rhs }
    public static func <<= <RHS:BinaryInteger>(lhs: inout UInt128, rhs: RHS) { lhs = lhs << rhs }
    public static func >>= <RHS:BinaryInteger>(lhs: inout UInt128, rhs: RHS) { lhs = lhs >> rhs }
  
}
