//
//  Decimal128-String.swift
//  
//
//  Created by Mike Griebling on 2022-03-21.
//

import Foundation

extension Decimal128 {
    
    static func bid128_to_string (_ x: UInt128, _ showPlus: Bool = false) -> String {
        //  save_fpsf = *pfpsf; // dummy
        let plus = showPlus ? "+" : ""
        let sign = (x.hi & MASK_SIGN) != 0 ? "-" : plus
        var x = x
        var str = ""
        var C1 = UInt128()
        BID_SWAP128(&x)
        
        // check for NaN or Infinity
        if (x.hi & MASK_SPECIAL) == MASK_SPECIAL {
            // x is special
            if (x.hi & MASK_NAN) == MASK_NAN {
                if (x.hi & MASK_SNAN) == MASK_SNAN {
                    str = "SNaN" // x is SNAN
                } else {
                    str = "NaN"  // x is QNaN
                }
            } else { // x is not a NaN, so it must be infinity
                str = "Inf"
            }
            return sign + str
        } else if (x.hi & MASK_COEFF) == 0x0 && x.lo == 0x0 {
            //determine if +/-
            return sign + "0"
        } else { // x is not special and is not zero
            // unpack x
            // let x_sign = x.hi & MASK_SIGN // 0 for positive, MASK_SIGN for negative
            var x_exp = x.hi & MASK_EXP   // biased and shifted left 49 bit positions
            if (x.hi & MASK_STEERING_BITS) == MASK_STEERING_BITS {
                x_exp = (x.hi<<2) & MASK_EXP // biased and shifted left 49 bit positions
            }
            C1.hi = x.hi & MASK_COEFF
            C1.lo = x.lo
            
            // determine coefficient"s representation as a decimal string
            // if zero or non-canonical, set coefficient to "0"
            if (C1.hi > 0x0001ed09bead87c0) || (C1.hi == 0x0001ed09bead87c0 && C1.lo > 0x378d8e63ffffffff) ||
               (x.hi & MASK_STEERING_BITS) == MASK_STEERING_BITS || (C1.hi == 0 && C1.lo == 0) {
                str += "0"
            } else {
                /* ****************************************************
                 This takes a bid coefficient in C1.hi,C1.lo
                 and put the converted character sequence at location
                 starting at &(str[k]). The function returns the number
                 of MiDi returned. Note that the character sequence
                 does not have leading zeros EXCEPT when the input is of
                 zero value. It will then output 1 character "0"
                 The algorithm essentailly tries first to get a sequence of
                 Millenial Digits "MiDi" and then uses table lookup to get the
                 character strings of these MiDis.
                 **************************************************** */
                /* Algorithm first decompose possibly 34 digits in hi and lo
                 18 digits. (The high can have at most 16 digits). It then
                 uses macro that handle 18 digit portions.
                 The first step is to get hi and lo such that
                 2^(64) C1.hi + C1.lo = hi * 10^18  + lo,   0 <= lo < 10^18.
                 We use a table lookup method to obtain the hi and lo 18 digits.
                 [C1.hi,C1.lo] = c_8 2^(107) + c_7 2^(101) + ... + c_0 2^(59) + d
                 where 0 <= d < 2^59 and each c_j has 6 bits. Because d fits in
                 18 digits,  we set hi = 0, and lo = d to begin with.
                 We then retrieve from a table, for j = 0, 1, ..., 8
                 that gives us A and B where c_j 2^(59+6j) = A * 10^18 + B.
                 hi += A ; lo += B; After each accumulation into lo, we normalize
                 immediately. So at the end, we have the decomposition as we need. */
                var Tmp = C1.lo >> 59
                var LO_18Dig = (C1.lo << 5) >> 5
                Tmp += (C1.hi << 5)
                var HI_18Dig = UInt64(0)
                var k_lcv = 0
                
                // Tmp = {C1.hi{49:0}, C1.lo{63:59}}
                // Lo_18Dig = {C1.lo{58:0}}
                while Tmp != 0 {
                    var midi_ind = Int(Tmp & 0x000000000000003F)
                    midi_ind <<= 1
                    Tmp >>= 6
                    HI_18Dig += mod10_18_tbl[k_lcv][midi_ind]; midi_ind += 1
                    LO_18Dig += mod10_18_tbl[k_lcv][midi_ind]; k_lcv += 1
                    __L0_Normalize_10to18(&HI_18Dig, &LO_18Dig)
                }
                var MiDi = [UInt32]()
                if HI_18Dig == 0 {
                    __L1_Split_MiDi_6_Lead (LO_18Dig, &MiDi)
                } else {
                    __L1_Split_MiDi_6_Lead (HI_18Dig, &MiDi)
                    __L1_Split_MiDi_6(LO_18Dig, &MiDi)
                }
                let len = MiDi.count
                
                /* now convert the MiDi into character strings */
                __L0_MiDi2Str_Lead (MiDi[0], &str)
                for k_lcv in 1..<len {
                    __L0_MiDi2Str (MiDi[k_lcv], &str)
                }
            }
            
            // print E and sign of exponent
            let exp = Int(x_exp >> 49) - DECIMAL_EXPONENT_BIAS_128 + (str.count - 1)
            str = addDecimalPointAndExponent(str, exp, MAX_FORMAT_DIGITS_128)
        }
        return sign + str
    }

    static func bid128_from_string (_ ps: String, _ rnd_mode: Rounding, _ pfpsf: inout Status) -> UInt128  {
        //  save_rnd_mode = rnd_mode; // dummy
        //  save_fpsf = *pfpsf; // dummy
        var res = UInt128()
        var sign_x : UInt64
        var right_radix_leading_zeros = 0, rdx_pt_enc = false
        
        // if null string, return NaN
        if ps.isEmpty {
            res.hi = MASK_NAN
            res.lo = 0
            return res
        }
        
        // eliminate leading white space
        var ps = ps.trimmingCharacters(in: .whitespaces).lowercased()
        
        // c gets first character
        var c = ps.isEmpty ? "\0" : ps.removeFirst()
        
        // if c is null or not equal to a (radix point, negative sign,
        // positive sign, or number) it might be SNaN, sNaN, Infinity
        if c == "\0" || (c != "." && c != "-" && c != "+" && !c.isWholeNumber) {
            res.lo = 0
            // Infinity?
            if c == "i" && (ps.hasPrefix("nfinity") || ps.hasPrefix("nf")) {
                res.hi = MASK_INF
                return res
            }
            // return sNaN
            if c == "s" && ps.hasPrefix("nan") {
                // case insensitive check for snan
                res.hi = MASK_SNAN // 0x7e00000000000000
                return res
            } else {
                // return qNaN
                res.hi = MASK_NAN // 0x7c00000000000000
                return res
            }
        }
        // if +Inf, -Inf, +Infinity, or -Infinity (case insensitive check for inf)
        if ps.hasPrefix("infinity") || ps.hasPrefix("inf") { // ci check for infinity
            res.lo = 0
            if c == "+" {
                res.hi = MASK_INF // 0x7800000000000000
            } else if c == "-" {
                res.hi = MASK_INF | MASK_SIGN  // 0xf800000000000000
            } else {
                res.hi = MASK_NAN // 0x7c00000000000000
            }
            return res
        }
        
        // if +sNaN, +SNaN, -sNaN, or -SNaN
        if ps.hasPrefix("snan") {
            res.lo = 0
            if c == "-"  {
                res.hi = MASK_SNAN | MASK_SIGN  // 0xfe00000000000000
            } else {
                res.hi = MASK_SNAN // 0x7e00000000000000
            }
            return res
        }
        
        // set up sign_x to be OR"ed with the upper word later
        if c == "-" {
            sign_x = MASK_SIGN
        } else {
            sign_x = 0
        }
        
        // go to next character if leading sign
        if c == "-" || c == "+" {
            c = ps.isEmpty ? "\0" : ps.removeFirst()
        }
        
        // if c isn't a decimal point or a decimal digit, return NaN
        if c != "." && !c.isWholeNumber {
            res.hi = MASK_NAN | sign_x
            res.lo = 0
            return res
        }
        if c == "." {
            rdx_pt_enc = true
            c = ps.isEmpty ? "\0" : ps.removeFirst()
        }
        
        // detect zero (and eliminate/ignore leading zeros)
        if c == "0" {
            // if all numbers are zeros (with possibly 1 radix point, the number is zero
            // should catch cases such as: 000.0
            while c == "0" {
                c = ps.isEmpty ? "\0" : ps.removeFirst()
                
                // for numbers such as 0.0000000000000000000000000000000000001001,
                // we want to count the leading zeros
                if rdx_pt_enc {
                    right_radix_leading_zeros += 1
                }
                
                // if this character is a radix point, make sure we haven"t already
                // encountered one
                if c == "." {
                    if !rdx_pt_enc {
                        rdx_pt_enc = true
                        // if this is the first radix point, and the next character is NULL,
                        // we have a zero
                        if ps.isEmpty {
                            res.hi = UInt64(0x3040000000000000 - (right_radix_leading_zeros << 49)) | sign_x
                            res.lo = 0
                            return res
                        }
                        c = ps.isEmpty ? "\0" : ps.removeFirst()
                    } else {
                        // if 2 radix points, return NaN
                        res.hi =  MASK_NAN | sign_x // 0x7c00000000000000
                        res.lo = 0
                        return res
                    }
                } else if !ps.isEmpty {
                    if right_radix_leading_zeros > DECIMAL_EXPONENT_BIAS_128 { right_radix_leading_zeros = DECIMAL_EXPONENT_BIAS_128 }
                    res.hi = UInt64(0x3040000000000000 - (right_radix_leading_zeros << 49)) | sign_x
                    res.lo = 0
                    return res
                }
            }
        }
        
        // initialize local variables
        var ndigits_before = 0, ndigits_after = 0, ndigits_total = 0
        var sgn_exp = 0
        var set_inexact = false
        var buffer = ""
        var CX = UInt128()
        
        if !rdx_pt_enc {
            // investigate string (before radix point)
            while c.isWholeNumber {
                if ndigits_before < MAX_FORMAT_DIGITS_128 {
                    buffer.append(c)
                } else if(ndigits_before < MAX_STRING_DIGITS_128) {
                    buffer.append(c)
                    if c > "0" { set_inexact = true }
                } else if c > "0" {
                    set_inexact = true
                }
                c = ps.isEmpty ? "\0" : ps.removeFirst()
                ndigits_before += 1
            }
            
            ndigits_total = ndigits_before
            if c == "." {
                c = ps.isEmpty ? "\0" : ps.removeFirst()
                if c != "\0" {
                    // investigate string (after radix point)
                    while c.isWholeNumber {
                        if ndigits_total < MAX_FORMAT_DIGITS_128 {
                            buffer.append(c)
                        } else if ndigits_total < MAX_STRING_DIGITS_128 {
                            buffer.append(c)
                            if c > "0" { set_inexact = true }
                        } else if c > "0" {
                            set_inexact = true
                        }
                        c = ps.isEmpty ? "\0" : ps.removeFirst()
                        ndigits_total += 1
                    }
                    ndigits_after = ndigits_total - ndigits_before
                }
            }
        } else {
            // we encountered a radix point while detecting zeros
            c = ps.isEmpty ? "\0" : ps.removeFirst()
            ndigits_total = 0
            // investigate string (after radix point)
            while c >= "0" && c <= "9" {
                if ndigits_total < MAX_FORMAT_DIGITS_128  {
                    buffer.append(c)
                } else if ndigits_total < MAX_STRING_DIGITS_128  {
                    buffer.append(c)
                    if (c>"0") { set_inexact = true }
                } else if c>"0" {
                    set_inexact = true
                }
                c = ps.isEmpty ? "\0" : ps.removeFirst()
                ndigits_total += 1
            }
            ndigits_after = ndigits_total - ndigits_before
        }
        
        // get exponent
        var dec_expon = 0
        if c != "\0" {
            if c != "e" {
                // return NaN
                res.hi = MASK_NAN //0x7c00000000000000
                res.lo = 0
                return res
            }
            c = ps.isEmpty ? "\0" : ps.removeFirst()
            
            if !c.isWholeNumber && ((c != "+" && c != "-") || !c.isWholeNumber) {
                // return NaN
                res.hi = MASK_NAN //0x7c00000000000000
                res.lo = 0
                return res
            }
            
            if c == "-" {
                sgn_exp = -1
                c = ps.isEmpty ? "\0" : ps.removeFirst()
            } else if c == "+" {
                c = ps.isEmpty ? "\0" : ps.removeFirst()
            }
            
            dec_expon = c.wholeNumberValue ?? 0
            var i = 1
            c = ps.isEmpty ? "\0" : ps.removeFirst()
            
            if dec_expon == 0 {
                while c == "0" { c = ps.isEmpty ? "\0" : ps.removeFirst() }
            }
            
            var digit = c.wholeNumberValue ?? -1
            while digit <= 9 && i < 7 {
                let d2 = dec_expon + dec_expon
                dec_expon = (d2 << 2) + d2 + digit
                c = ps.isEmpty ? "\0" : ps.removeFirst()
                digit = c.wholeNumberValue ?? -1
                i += 1
            }
        }
        
        dec_expon = (dec_expon + sgn_exp) ^ sgn_exp
        
        var coeff_high, coeff_low: UInt64
        let dbuffer = buffer.map { UInt64($0.wholeNumberValue ?? 0) } // convert character to uints
        if ndigits_total <= MAX_FORMAT_DIGITS_128 {
            dec_expon += DECIMAL_EXPONENT_BIAS_128 - ndigits_after - right_radix_leading_zeros
            if dec_expon < 0 {
                res.hi = 0 | sign_x
                res.lo = 0
            }
            if ndigits_total == 0 {
                CX.lo = 0
                CX.hi = 0
            } else if ndigits_total <= 19 {
                coeff_high = dbuffer[0]
                for i in 1..<ndigits_total {
                    let coeff2 = coeff_high + coeff_high
                    coeff_high = (coeff2 << 2) + coeff2 + dbuffer[i]
                }
                CX.lo = coeff_high
                CX.hi = 0
            } else {
                coeff_high = dbuffer[0]
                var iv = ndigits_total-17
                for i in 1..<iv {
                    let coeff2 = coeff_high + coeff_high
                    coeff_high = (coeff2 << 2) + coeff2 + dbuffer[i]
                }
                coeff_low = dbuffer[iv]
                iv += 1
                while iv < ndigits_total {
                    let coeff_l2 = coeff_low + coeff_low
                    coeff_low = (coeff_l2 << 2) + coeff_l2 + dbuffer[iv]
                    iv += 1
                }
                // now form the coefficient as coeff_high*10^19+coeff_low+carry
                let scale_high = UInt64(100000000000000000)
                __mul_64x64_to_128_fast(&CX, coeff_high, scale_high)
                
                CX.lo += coeff_low;
                if CX.lo < coeff_low {
                    CX.hi+=1
                }
            }
            return bid_get_BID128(sign_x, dec_expon, CX, rnd_mode, &pfpsf)
        } else {
            // simply round using the digits that were read
            dec_expon += ndigits_before + DECIMAL_EXPONENT_BIAS_128 - MAX_FORMAT_DIGITS_128 - right_radix_leading_zeros
            
            if dec_expon < 0 {
                res.hi = 0 | sign_x
                res.lo = 0
            }
            
            coeff_high = dbuffer[0]
            var iv = MAX_FORMAT_DIGITS_128 - 17
            for i in 1..<iv {
                let coeff2 = coeff_high + coeff_high;
                coeff_high = (coeff2 << 2) + coeff2 + dbuffer[i]
            }
            coeff_low = dbuffer[iv]
            iv += 1
            while iv < MAX_FORMAT_DIGITS_128 {
                let coeff_l2 = coeff_low + coeff_low
                coeff_low = (coeff_l2 << 2) + coeff_l2 + dbuffer[iv]
                iv += 1
            }
            var carry = UInt64(0)
            switch rnd_mode {
                case BID_ROUNDING_TO_NEAREST:
                    carry = (4 &- dbuffer[iv]) >> 31
                    if ((dbuffer[iv] == 5 && (coeff_low & 1 == 0)) || dec_expon < 0) {
                        if dec_expon >= 0 {
                            carry = 0
                            iv+=1
                        }
                        while iv < ndigits_total {
                            if dbuffer[iv] > 0 {
                                carry = 1
                                break;
                            }
                            iv += 1
                        }
                    }
                case BID_ROUNDING_DOWN:
                    if sign_x != 0 {
                        while iv < ndigits_total {
                            if dbuffer[iv] > 0 {
                                carry = 1
                                break
                            }
                            iv += 1
                        }
                    }
                case BID_ROUNDING_UP:
                    if sign_x == 0 {
                        while iv < ndigits_total {
                            if dbuffer[iv] > 0 {
                                carry = 1
                                break
                            }
                            iv += 1
                        }
                    }
                case BID_ROUNDING_TO_ZERO:
                    carry=0
                case BID_ROUNDING_TIES_AWAY:
                    carry = (4 - dbuffer[iv]) >> 31
                    if dec_expon < 0 {
                        while iv < ndigits_total {
                            if dbuffer[iv] > 0 {
                                carry = 1
                                break
                            }
                            iv += 1
                        }
                    }
                default: break
            }
            
            // now form the coefficient as coeff_high*10^17+coeff_low+carry
            var scale_high = UInt64(100_000_000_000_000_000)
            if dec_expon < 0 {
                if dec_expon > -MAX_FORMAT_DIGITS_128 {
                    scale_high = 1000000000000000000
                    coeff_low = (coeff_low << 3) + (coeff_low << 1)
                    dec_expon-=1
                }
                if dec_expon == -MAX_FORMAT_DIGITS_128 && coeff_high > 50000000000000000 {
                    carry = 0
                }
            }
            
            __mul_64x64_to_128_fast(&CX, coeff_high, scale_high)
            
            coeff_low += carry
            CX.lo += coeff_low
            if CX.lo < coeff_low {
                CX.hi+=1
            }
            
            if set_inexact {
                pfpsf.insert(.inexact)
            }
            
            return bid_get_BID128(sign_x, dec_expon, CX, rnd_mode, &pfpsf)
        }
    }
    
}
