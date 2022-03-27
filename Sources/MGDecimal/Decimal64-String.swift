//
//  File.swift
//  
//
//  Created by Mike Griebling on 2022-03-20.
//

import Foundation


extension Decimal64 {

    static func bid64_to_string (_ x: UInt64, _ showPlus: Bool = false) -> String {
        // unpack arguments, check for NaN or Infinity
        let plus = showPlus ? "+" : ""
        var ps = ""
        var sign_x = UInt64(), exponent_x = 0, coefficient_x = UInt64()
        
        if !unpack_BID64 (&sign_x, &exponent_x, &coefficient_x, x) {
            // x is Inf. or NaN or 0
            // Inf or NaN?
            if (x & INFINITY_MASK64) == INFINITY_MASK64 {
                if (x & MASK_ANY_INF) == MASK_ANY_INF {
                    ps = sign_x != 0 ? "-" : plus
                    if (x & MASK_SNAN) == MASK_SNAN { ps.append("S") }
                    ps += "NaN"
                    return ps
                }
                // x is Inf
                ps = sign_x != 0 ? "-" : plus
                ps += "Inf"
                return ps
            }

            ps = sign_x != 0 ? "-" : plus
            ps += "0"
            return ps
        }
        
        // if zero or non-canonical, set coefficient to "0"
        if coefficient_x > MAX_NUMBER || coefficient_x == 0 {
            // non-canonical or significand is zero
            ps = sign_x != 0 ? "-" : plus
            ps += "0"
        } else {
            /* ****************************************************
             This takes a bid coefficient in C1.w[1],C1.w[0]
             and put the converted character sequence at location
             starting at &(str[k]). The function returns the number
             of MiDi returned. Note that the character sequence
             does not have leading zeros EXCEPT when the input is of
             zero value. It will then output 1 character "0"
             The algorithm essentially tries first to get a sequence of
             Millenial Digits "MiDi" and then uses table lookup to get the
             character strings of these MiDis.
             **************************************************** */
            /* Algorithm first decompose possibly 34 digits in hi and lo
             18 digits. (The high can have at most 16 digits). It then
             uses macro that handle 18 digit portions.
             The first step is to get hi and lo such that
             2^(64) C1.w[1] + C1.w[0] = hi * 10^18  + lo,   0 <= lo < 10^18.
             We use a table lookup method to obtain the hi and lo 18 digits.
             [C1.w[1],C1.w[0]] = c_8 2^(107) + c_7 2^(101) + ... + c_0 2^(59) + d
             where 0 <= d < 2^59 and each c_j has 6 bits. Because d fits in
             18 digits,  we set hi = 0, and lo = d to begin with.
             We then retrieve from a table, for j = 0, 1, ..., 8
             that gives us A and B where c_j 2^(59+6j) = A * 10^18 + B.
             hi += A ; lo += B; After each accumulation into lo, we normalize
             immediately. So at the end, we have the decomposition as we need. */
            var Tmp = coefficient_x >> 59
            var LO_18Dig = (coefficient_x << 5) >> 5
            var HI_18Dig = UInt64()
            var k_lcv = 0
            
            while Tmp != 0 {
                var midi_ind = Int(Tmp & 0x000000000000003F)
                midi_ind <<= 1
                Tmp >>= 6
                HI_18Dig += mod10_18_tbl[k_lcv][midi_ind]; midi_ind += 1
                LO_18Dig += mod10_18_tbl[k_lcv][midi_ind]; k_lcv += 1
                __L0_Normalize_10to18 (&HI_18Dig, &LO_18Dig)
            }
            
            var MiDi = [UInt32]()
            __L1_Split_MiDi_6_Lead(LO_18Dig, &MiDi)
            let len = MiDi.count
            
            /* now convert the MiDi into character strings */
            __L0_MiDi2Str_Lead(MiDi[0], &ps)
            for k_lcv in 1..<len {
                __L0_MiDi2Str(MiDi[k_lcv], &ps)
            }
            
            exponent_x -= EXPONENT_BIAS - (ps.count - 1)
            return (sign_x != 0 ? "-" : plus) + addDecimalPointAndExponent(ps, exponent_x, MAX_DIGITS)
        }
        return (sign_x != 0 ? "-" : plus) + ps
    }


    static func bid64_from_string (_ ps: String, _ rnd_mode: Rounding, _ pfpsf: inout Status) -> UInt64 {
        //  save_fpsf = *pfpsf; // place holder only
        // eliminate leading whitespace
        var ps = ps.trimmingCharacters(in: .whitespaces).lowercased()
        var res: UInt64
        
        // get first non-whitespace character
        var c = ps.isEmpty ? "\0" : ps.removeFirst()
        
        // detect special cases (INF or NaN)
        if c == "\0" || (c != "." && c != "-" && c != "+" && (c < "0" || c > "9")) {
            // Infinity?
            if c == "i" && (ps.hasPrefix("nfinity") || ps.hasPrefix("nf")) {
                return INFINITY_MASK64
            }
            // return sNaN
            if c == "s" && ps.hasPrefix("nan") {
                // case insensitive check for snan
                return SNAN_MASK64
            } else {
                // return qNaN
                return NAN_MASK64
            }
        }
        
        // detect +INF or -INF
        if ps.hasPrefix("infinity") || ps.hasPrefix("inf") {
            if c == "+" {
                res = INFINITY_MASK64
            } else if c == "-" {
                res = SINFINITY_MASK64
            } else {
                res = NAN_MASK64
            }
            return res
        }
        
        // if +sNaN, +SNaN, -sNaN, or -SNaN
        if ps.hasPrefix("snan") {
            if c == "-" {
                res = SSNAN_MASK64
            } else {
                res = SNAN_MASK64
            }
            return res
        }
        
        // determine sign
        var sign_x = UInt64(0)
        if c == "-" {
            sign_x = SIGN_MASK64
        }
        
        // get next character if leading +/- sign
        if c == "-" || c == "+" {
            c = ps.isEmpty ? "\0" : ps.removeFirst()
        }
        
        // if c isn't a decimal point or a decimal digit, return NaN
        if c != "." && (c < "0" || c > "9") {
            // return NaN
            return NAN_MASK64 | sign_x
        }
        
        var rdx_pt_enc = false
        var right_radix_leading_zeros = 0
        var coefficient_x = UInt64(0)
        
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
                // if this character is a radix point, make sure we haven"t already
                // encountered one
                if c == "." {
                    if !rdx_pt_enc {
                        rdx_pt_enc = true
                        // if this is the first radix point, and the next character is NULL,
                        // we have a zero
                        if ps.isEmpty {
                            return (UInt64(EXPONENT_BIAS - right_radix_leading_zeros) << 53) | sign_x
                        }
                        c = ps.isEmpty ? "\0" : ps.removeFirst()
                    } else {
                        // if 2 radix points, return NaN
                        return NAN_MASK64 | sign_x
                    }
                } else if !ps.isEmpty {
                    //pres->w[1] = 0x3040000000000000 | sign_x;
                    return (UInt64(EXPONENT_BIAS - right_radix_leading_zeros) << 53) | sign_x
                }
            }
        }
        
        var ndigits = 0
        var midpoint = false
        var dec_expon_scale = 0
        var rounded = false
        var rounded_up = false
        var add_expon = 0
        while (c >= "0" && c <= "9") || c == "." {
            if c == "." {
                if rdx_pt_enc {
                    // return NaN
                    return NAN_MASK64 | sign_x
                }
                rdx_pt_enc = true
                c = ps.isEmpty ? "\0" : ps.removeFirst()
                continue
            }
            if rdx_pt_enc { dec_expon_scale += 1 }
            
            ndigits+=1
            if ndigits <= 16 {
                coefficient_x = (coefficient_x << 1) + (coefficient_x << 3);
                coefficient_x += UInt64(c.wholeNumberValue ?? 0)
            } else if ndigits == 17 {
                // coefficient rounding
                switch rnd_mode {
                    case BID_ROUNDING_TO_NEAREST:
                        midpoint = c == "5" && (coefficient_x & 1) == 0
                        // if coefficient is even and c is 5, prepare to round up if
                        // subsequent digit is nonzero
                        // if str[MAXDIG+1] > 5, we MUST round up
                        // if str[MAXDIG+1] == 5 and coefficient is ODD, ROUND UP!
                        if c > "5" || (c == "5" && coefficient_x & 1 != 0) {
                            coefficient_x+=1
                            rounded_up = true
                        }
                    case BID_ROUNDING_DOWN:
                        if sign_x != 0 { coefficient_x+=1; rounded_up = true }
                    case BID_ROUNDING_UP:
                        if sign_x == 0 { coefficient_x+=1; rounded_up = true }
                    case BID_ROUNDING_TIES_AWAY:
                        if (c>="5") { coefficient_x+=1; rounded_up = true }
                    default: break
                }
                if coefficient_x == 10000000000000000 {
                    coefficient_x = 1000000000000000
                    add_expon = 1
                }
                if c > "0" {
                    rounded = true
                }
                add_expon += 1
            } else { // ndigits > 17
                add_expon+=1
                if midpoint && c > "0" {
                    coefficient_x+=1
                    midpoint = false
                    rounded_up = true
                }
                if c > "0" {
                    rounded = true
                }
            }
            c = ps.isEmpty ? "\0" : ps.removeFirst()
        }
        
        add_expon -= dec_expon_scale + right_radix_leading_zeros
        
        if c == "\0" {
            if rounded {
                pfpsf.insert(.inexact)
            }
            return fast_get_BID64_check_OF(sign_x, add_expon+EXPONENT_BIAS, coefficient_x, .toNearestOrEven, &pfpsf)
        }
        
        if c != "e" {
            // return NaN
            return NAN_MASK64 | sign_x
        }
        c = ps.isEmpty ? "\0" : ps.removeFirst()
        let sgn_expon = c == "-"
        var expon_x = 0
        if c == "-" || c == "+" {
            c = ps.isEmpty ? "\0" : ps.removeFirst()
        }
        if ps.isEmpty || c < "0" || c > "9" {
            // return NaN
            return NAN_MASK64 | sign_x
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
            return NAN_MASK64 | sign_x
        }
        
        if rounded {
            pfpsf.insert(.inexact)
        }
        
        if sgn_expon {
            expon_x = -expon_x
        }
        
        expon_x += add_expon + EXPONENT_BIAS
        
        if expon_x < 0 {
            if rounded_up {
                coefficient_x-=1
            }
            return get_BID64_UF (sign_x, expon_x, coefficient_x, rounded ? 1 : 0, .toNearestOrEven, &pfpsf)
        }
        return get_BID64 (sign_x, expon_x, coefficient_x, rnd_mode, &pfpsf)
    }

}
