//
//  Decimal32-String.swift
//  
//
//  Created by Mike Griebling on 2022-03-20.
//

import Foundation

extension Decimal32 {
    
    static func bid32_to_string (_ x: UInt32, _ showPlus: Bool = false) -> String {
        
        func stripZeros(_ d: UInt64, _ addDecimal: Bool = false) -> String {
            var digs = bid_midi_tbl[Int(d)]
            if digs.first! == "0" { digs.removeFirst() }
            if digs.first! == "0" && digs.count == 2 { digs.removeFirst() }
            return digs
        }
        
        // unpack arguments, check for NaN or Infinity
        let addDecimal = true
        let plus = showPlus ? "+" : ""
        var sign_x = UInt32(0), coefficient_x = UInt32(0), exponent_x = 0
        let special = !unpack_BID32 (&sign_x, &exponent_x, &coefficient_x, x)
        
        if special {
            // x is Inf. or NaN or 0
            var ps = sign_x != 0 ? "-" : plus
            if (x&NAN_MASK32) == NAN_MASK32 {
                if (x & SNAN_MASK32) == SNAN_MASK32 { ps.append("S") }
                ps.append("NaN")
                return ps
            }
            if (x&INFINITY_MASK32) == INFINITY_MASK32 {
                ps.append("Inf")
                return ps
            }
            ps.append("0")
            return ps
        } else {
            // x is not special
            var ps = ""
            if coefficient_x >= 1_000_000 {
                var CT = UInt64(coefficient_x) * 0x431B_DE83
                CT >>= 32
                var d = CT >> (50-32)
                
                // upper digit
                ps.append(String(d))
                coefficient_x -= UInt32(d * 1_000_000)
                
                // get lower 6 digits
                CT = UInt64(coefficient_x) * 0x20C4_9BA6
                CT >>= 32
                d = CT >> (39-32)
                ps += bid_midi_tbl[Int(d)]
                d = UInt64(coefficient_x) - d * 1000
                ps += bid_midi_tbl[Int(d)]
            } else if coefficient_x >= 1000 {
                // get 4 to 6 digits
                var CT = UInt64(coefficient_x) * 0x20C4_9BA6
                CT >>= 32
                var d = CT >> (39-32)
                ps += stripZeros(d, addDecimal)
                d = UInt64(coefficient_x) - d*1000
                ps += bid_midi_tbl[Int(d)]
            } else {
                // get 1 to 3 digits
                ps += stripZeros(UInt64(coefficient_x), addDecimal)
            }
            
            exponent_x -= EXPONENT_BIAS - (ps.count - 1)
            return (sign_x != 0 ? "-" : plus) + addDecimalPointAndExponent(ps, exponent_x, MAX_DIGITS)
        }
    }
    
    
    static func bid32_from_string (_ ps: String, _ rnd_mode: Rounding, _ pfpsf: inout Status) -> UInt32 {
        // eliminate leading whitespace
        var ps = ps.trimmingCharacters(in: .whitespaces).lowercased()
        var res: UInt32
        
        // get first non-whitespace character
        var c = ps.isEmpty ? "\0" : ps.removeFirst()
        
        // detect special cases (INF or NaN)
        if c == "\0" || (c != "." && c != "-" && c != "+" && (c < "0" || c > "9")) {
            // Infinity?
            if c == "i" && (ps.hasPrefix("nfinity") || ps.hasPrefix("nf")) {
                return INFINITY_MASK32
            }
            // return sNaN
            if c == "s" && ps.hasPrefix("nan") {
                // case insensitive check for snan
                return SNAN_MASK32
            } else {
                // return qNaN
                return NAN_MASK32
            }
        }
        
        // detect +INF or -INF
        if ps.hasPrefix("infinity") || ps.hasPrefix("inf") {
            if c == "+" {
                res = INFINITY_MASK32
            } else if c == "-" {
                res = SINFINITY_MASK32
            } else {
                res = NAN_MASK32
            }
            return res
        }
        
        // if +sNaN, +SNaN, -sNaN, or -SNaN
        if ps.hasPrefix("snan") {
            if c == "-" {
                res = SSNAN_MASK32
            } else {
                res = SNAN_MASK32
            }
            return res
        }
        
        // determine sign
        var sign_x = UInt32(0)
        if c == "-" {
            sign_x = SIGN_MASK32
        }
        
        // get next character if leading +/- sign
        if c == "-" || c == "+" {
            c = ps.isEmpty ? "\0" : ps.removeFirst()
        }
        
        // if c isn"t a decimal point or a decimal digit, return NaN
        if c != "." && (c < "0" || c > "9") {
            // return NaN
            return NAN_MASK32 | sign_x
        }
        
        var rdx_pt_enc = false
        var right_radix_leading_zeros = 0
        var coefficient_x = 0
        
        // detect zero (and eliminate/ignore leading zeros)
        if c == "0" || c == "." {
            if c == "." {
                rdx_pt_enc = true
                c = ps.isEmpty ? "\0" : ps.removeFirst()
            }
            // if all numbers are zeros (with possibly 1 radix point, the number is zero
            // should catch cases such as: 000.0
            while c == "0" {
                c = ps.isEmpty ? "\0" : ps.removeFirst()
                // for numbers such as 0.0000000000000000000000000000000000001001,
                // we want to count the leading zeros
                if rdx_pt_enc {
                    right_radix_leading_zeros+=1
                }
                // if this character is a radix point, make sure we haven't already
                // encountered one
                if c == "." {
                    if !rdx_pt_enc {
                        rdx_pt_enc = true
                        // if this is the first radix point, and the next character is NULL,
                        // we have a zero
                        if ps.isEmpty {
                            right_radix_leading_zeros = EXPONENT_BIAS - right_radix_leading_zeros
                            if right_radix_leading_zeros < 0 {
                                right_radix_leading_zeros = 0
                            }
                            return (UInt32(right_radix_leading_zeros) << 23) | sign_x
                        }
                        c = ps.isEmpty ? "\0" : ps.removeFirst()
                    } else {
                        // if 2 radix points, return NaN
                        return NAN_MASK32 | sign_x
                    }
                } else if ps.isEmpty {
                    right_radix_leading_zeros = EXPONENT_BIAS - right_radix_leading_zeros
                    if right_radix_leading_zeros < 0 {
                        right_radix_leading_zeros = 0
                    }
                    return (UInt32(right_radix_leading_zeros) << 23) | sign_x
                }
            }
        }
        
        var ndigits = 0
        var dec_expon_scale = 0
        var midpoint = 0
        var rounded_up = 0
        var add_expon = 0
        var rounded = 0
        while (c >= "0" && c <= "9") || c == "." {
            if c == "." {
                if rdx_pt_enc {
                    // return NaN
                    return NAN_MASK32 | sign_x
                }
                rdx_pt_enc = true
                c = ps.isEmpty ? "\0" : ps.removeFirst()
                continue
            }
            if rdx_pt_enc { dec_expon_scale += 1 }
            
            ndigits+=1
            if ndigits <= 7 {
                coefficient_x = (coefficient_x << 1) + (coefficient_x << 3);
                coefficient_x += c.wholeNumberValue ?? 0
            } else if ndigits == 8 {
                // coefficient rounding
                switch rnd_mode {
                    case BID_ROUNDING_TO_NEAREST:
                        midpoint = (c == "5" && (coefficient_x & 1 == 0)) ? 1 : 0;
                        // if coefficient is even and c is 5, prepare to round up if
                        // subsequent digit is nonzero
                        // if str[MAXDIG+1] > 5, we MUST round up
                        // if str[MAXDIG+1] == 5 and coefficient is ODD, ROUND UP!
                        if c > "5" || (c == "5" && (coefficient_x & 1) != 0) {
                            coefficient_x+=1
                            rounded_up = 1
                        }
                    case BID_ROUNDING_DOWN:
                        if sign_x != 0 { coefficient_x+=1; rounded_up=1 }
                    case BID_ROUNDING_UP:
                        if sign_x == 0 { coefficient_x+=1; rounded_up=1 }
                    case BID_ROUNDING_TIES_AWAY:
                        if c >= "5" { coefficient_x+=1; rounded_up=1 }
                    default: break
                }
                if coefficient_x == 10000000 {
                    coefficient_x = 1000000
                    add_expon = 1;
                }
                if c > "0" {
                    rounded = 1;
                }
                add_expon += 1;
            } else { // ndigits > 8
                add_expon+=1
                if midpoint != 0 && c > "0" {
                    coefficient_x+=1
                    midpoint = 0;
                    rounded_up = 1;
                }
                if c > "0" {
                    rounded = 1;
                }
            }
            c = ps.isEmpty ? "\0" : ps.removeFirst()
        }
        
        add_expon -= dec_expon_scale + Int(right_radix_leading_zeros)
        
        if c == "\0" {
            if rounded != 0 {
                pfpsf.insert(.inexact)
            }
            return get_BID32(sign_x, add_expon+EXPONENT_BIAS, UInt32(coefficient_x), .toNearestOrEven, &pfpsf)
        }
        
        if c != "e" {
            // return NaN
            return NAN_MASK32 | sign_x
        }
        c = ps.isEmpty ? "\0" : ps.removeFirst()
        let sgn_expon = (c == "-") ? 1 : 0
        var expon_x = 0
        if c == "-" || c == "+" {
            c = ps.isEmpty ? "\0" : ps.removeFirst()
        }
        if c == "\0" || c < "0" || c > "9" {
            // return NaN
            return NAN_MASK32 | sign_x
        }
        
        while (c >= "0") && (c <= "9") {
            if expon_x < (1<<20) {
                expon_x = (expon_x << 1) + (expon_x << 3)
                expon_x += c.wholeNumberValue ?? 0
            }
            c = ps.isEmpty ? "\0" : ps.removeFirst()
        }
        
        if c != "\0" {
            // return NaN
            return NAN_MASK32 | sign_x
        }
        
        if rounded != 0 {
            pfpsf.insert(.inexact)
        }
        
        if sgn_expon != 0 {
            expon_x = -expon_x
        }
        
        expon_x += add_expon + EXPONENT_BIAS;
        
        if expon_x < 0 {
            if rounded_up != 0 {
                coefficient_x-=1
            }
            return get_BID32_UF (sign_x, expon_x, UInt64(coefficient_x), rounded, .toNearestOrEven, &pfpsf)
        }
        return get_BID32 (sign_x, expon_x, UInt32(coefficient_x), rnd_mode, &pfpsf)
    }
    
}
