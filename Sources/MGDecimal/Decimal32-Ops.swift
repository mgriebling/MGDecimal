//
//  Operations.swift
//  
//
//  Created by Mike Griebling on 2022-03-10.
//

import Foundation

extension Decimal32 {
    
    static func add(_ x:UInt32, _ y:UInt32, _ rmode:Rounding, _ status:inout Status) -> UInt32 {
        // BID_OPT_SAVE_BINARY_FLAGS()
        var sign_x = UInt32(0), sign_y = UInt32(0), exponent_x = 0, exponent_y = 0
        var coefficient_x = UInt32(0), coefficient_y = UInt32(0)
        let valid_x = unpack_BID32 (&sign_x, &exponent_x, &coefficient_x, x)
        let valid_y = unpack_BID32 (&sign_y, &exponent_y, &coefficient_y, y)
        
        // unpack arguments, check for NaN or Infinity
        if !valid_x {
            // x is Inf. or NaN
            
            // test if x is NaN
            if (x & NAN_MASK32) == NAN_MASK32 {
                if ((x & SNAN_MASK32) == SNAN_MASK32) || ((y & SNAN_MASK32) == SNAN_MASK32) {
                    status.insert(.invalidOperation)
                }
                return coefficient_x & QUIET_MASK32
            }
            // x is Infinity?
            if (x & INFINITY_MASK32) == INFINITY_MASK32 {
                // check if y is Inf
                if (y & NAN_MASK32) == INFINITY_MASK32 {
                    if sign_x == (y & SIGN_MASK32) {
                        return coefficient_x
                    } else {
                        // return NaN
                        status.insert(.invalidOperation)
                        return NAN_MASK32
                    }
                }
                // check if y is NaN
                if (y & NAN_MASK32) == NAN_MASK32 {
                    let res = coefficient_y & QUIET_MASK32
                    if (y & SNAN_MASK32) == SNAN_MASK32 {
                        status.insert(.invalidOperation)
                    }
                    return res
                } else {
                    // otherwise return +/-Inf
                    return coefficient_x
                }
            } else {
                // x is 0
                if ((y & INFINITY_MASK32) != INFINITY_MASK32) && (coefficient_y != 0) {
                    if exponent_y <= exponent_x {
                        return y
                    }
                }
            }
        }
        if !valid_y {
            // y is Inf. or NaN?
            if (y & INFINITY_MASK32) == INFINITY_MASK32 {
                if (y & SNAN_MASK32) == SNAN_MASK32 {   // sNaN
                    status.insert(.invalidOperation)
                }
                return coefficient_y & QUIET_MASK32
            }
            // y is 0
            if coefficient_x == 0 {    // x==0
                var res:UInt32
                if exponent_x <= exponent_y {
                    res = UInt32(exponent_x) << 23
                } else {
                    res = UInt32(exponent_y) << 23
                }
                if sign_x == sign_y {
                    res |= sign_x
                }
                if rmode == BID_ROUNDING_DOWN && sign_x != sign_y {
                    res |= SIGN_MASK32
                }
                return res
            } else if exponent_y >= exponent_x {
                return x
            }
        }
        
        // sort arguments by exponent
        var sign_a, coefficient_a, sign_b, coefficient_b: UInt32
        var exponent_a, exponent_b: Int
        if exponent_x < exponent_y {
            sign_a = sign_y
            exponent_a = exponent_y
            coefficient_a = coefficient_y
            sign_b = sign_x
            exponent_b = exponent_x
            coefficient_b = coefficient_x
        } else {
            sign_a = sign_x
            exponent_a = exponent_x
            coefficient_a = coefficient_x
            sign_b = sign_y
            exponent_b = exponent_y
            coefficient_b = coefficient_y
        }
        
        // exponent difference
        var diff_dec_expon = exponent_a - exponent_b
        
        if diff_dec_expon > MAX_DIGITS {
            let tempx = Double(coefficient_a)
            let bin_expon = Int((tempx.bitPattern & Decimal64.MASK_BINARY_EXPONENT) >> 52) - BINARY_EXPONENT_BIAS
            let scale_ca = bid_estimate_decimal_digits[bin_expon]
            
            let d2 = 16 - scale_ca
            if diff_dec_expon > d2 {
                diff_dec_expon = Int(d2)
                exponent_b = exponent_a - diff_dec_expon;
            }
        }
        
        var sign_ab = (Int64(sign_a ^ sign_b))<<32
        sign_ab = Int64(sign_ab) >> 63
        let CB = (Int64(coefficient_b) + sign_ab) ^ sign_ab
        
        let SU = UInt64(coefficient_a) * bid_power10_table_128[diff_dec_expon].w[0]
        var S = Int64(SU) + CB
        
        if S<0 {
            sign_a ^= SIGN_MASK32
            S = -S
        }
        var P = UInt64(S)
        var n_digits:Int
        if P == 0 {
            sign_a = 0
            if rmode == BID_ROUNDING_DOWN { sign_a = SIGN_MASK32 }
            if coefficient_a == 0 { sign_a = sign_x }
            n_digits=0;
        } else {
            let tempx = Double(P)
            let bin_expon = Int((tempx.bitPattern & Decimal64.MASK_BINARY_EXPONENT) >> 52) - BINARY_EXPONENT_BIAS
            n_digits = Int(bid_estimate_decimal_digits[bin_expon])
            if P >= bid_power10_table_128[n_digits].w[0] {
                n_digits+=1
            }
        }
        
        if n_digits <= MAX_DIGITS {
            return get_BID32(sign_a, exponent_b, UInt32(P), rmode, &status)
        }
        
        let extra_digits = n_digits - 7
        
        let irmode = roundboundIndex(rmode, sign_a != 0, 0)
//        if (sign_a != 0 && (irmode - 1) < 2) {
//            irmode = 3 - irmode;
//        }
        
        // add a constant to P, depending on rounding mode
        // 0.5*10^(digits_p - 16) for round-to-nearest
        P += bid_round_const_table[irmode][extra_digits]
        var Tmp = UInt128()
        __mul_64x64_to_128(&Tmp, P, bid_reciprocals10_64[extra_digits])
        
        // now get P/10^extra_digits: shift Q_high right by M[extra_digits]-64
        let amount = bid_short_recip_scale[extra_digits]
        var Q = Tmp.w[1] >> amount
        
        // remainder
        let R = P - Q * bid_power10_table_128[extra_digits].w[0]
        if R==bid_round_const_table[irmode][extra_digits] {
            status = []
        } else {
            status.insert(.inexact)
        }
        
        if rmode == BID_ROUNDING_TO_NEAREST {
            if R==0 {
                Q &= 0xffff_fffe
            }
        }
        return get_BID32(sign_a, exponent_b+extra_digits, UInt32(Q), rmode, &status)
    }
    
    static let bid_mult_factor : [UInt32] = [
        1, 10, 100, 1000, 10000, 100000, 1000000
    ]
    
    fileprivate static func extractExpSig(_ x: UInt32) -> (exp: Int, sig: UInt32, non_canon: Bool) {
        if (x & MASK_STEERING_BITS32) == MASK_STEERING_BITS32 {
            let exp = Int(x & MASK_BINARY_EXPONENT2_32) >> 21
            let sig = (x & MASK_BINARY_SIG2_32) | MASK_BINARY_OR2_32
            return (exp, sig, sig > MAX_NUMBER)
        } else {
            let exp = Int(x & MASK_BINARY_EXPONENT1_32) >> 23
            let sig = x & MASK_BINARY_SIG1_32
            return (exp, sig, false)
        }
    }
    
    fileprivate static func extractExpSig(_ x: UInt32) -> (exp: Int, sig: UInt32) {
        if (x & MASK_STEERING_BITS32) == MASK_STEERING_BITS32 {
            let exp = Int(x & MASK_BINARY_EXPONENT2_32) >> 21
            let sig = (x & MASK_BINARY_SIG2_32) | MASK_BINARY_OR2_32
            if sig > MAX_NUMBER { return (0, 0) }
            return (exp, sig)
        } else {
            let exp = Int(x & MASK_BINARY_EXPONENT1_32) >> 23
            let sig = x & MASK_BINARY_SIG1_32
            return (exp, sig)
        }
    }
    
    static func equal (_ x: UInt32, _ y: UInt32, _ status: inout Status) -> Bool {
        // NaN (CASE1)
        // if either number is NAN, the comparison is unordered,
        // rather than equal : return 0
        if ((x & MASK_NAN32) == MASK_NAN32) || ((y & MASK_NAN32) == MASK_NAN32) {
            if (x & MASK_SNAN32) == Decimal32.MASK_SNAN32 || (y & MASK_SNAN32) == MASK_SNAN32 {
                status.insert(.invalidOperation)  // set exception if sNaN
            }
            return false
        }
        // SIMPLE (CASE2)
        // if all the bits are the same, these numbers are equivalent.
        if x == y {
            return true
        }
        
        // INFINITY (CASE3)
        if ((x & MASK_INF32) == MASK_INF32) && ((y & MASK_INF32) == MASK_INF32) {
            return ((x ^ y) & Decimal32.MASK_SIGN32) != Decimal32.MASK_SIGN32
        }
        // ONE INFINITY (CASE3')
        if ((x & MASK_INF32) == MASK_INF32) || ((y & MASK_INF32) == MASK_INF32) {
            return false
        }
        
        // if steering bits are 11 (condition will be 0), then exponent is G[0:w+1] =>
        //var exp_x, sig_x: UInt32; var non_canon_x: Bool
        var (exp_x, sig_x, non_canon_x) = extractExpSig(x)
        
        // if steering bits are 11 (condition will be 0), then exponent is G[0:w+1] =>
        var (exp_y, sig_y, non_canon_y) =  extractExpSig(y)
//        if (y & MASK_STEERING_BITS32) == MASK_STEERING_BITS32 {
//            exp_y = (y & MASK_BINARY_EXPONENT2_32) >> 21
//            sig_y = (y & MASK_BINARY_SIG2_32) | MASK_BINARY_OR2_32
//            non_canon_y = sig_y > BID32_SIG_MAX
//        } else {
//            exp_y = (y & Decimal32.MASK_BINARY_EXPONENT1_32) >> 23
//            sig_y = (y & Decimal32.MASK_BINARY_SIG1_32)
//            non_canon_y = false
//        }
        
        // ZERO (CASE4)
        // some properties:
        // (+ZERO==-ZERO) => therefore ignore the sign
        //    (ZERO x 10^A == ZERO x 10^B) for any valid A, B =>
        //    therefore ignore the exponent field
        //    (Any non-canonical # is considered 0)
        var x_is_zero = false, y_is_zero = false
        if non_canon_x || sig_x == 0 {
            x_is_zero = true
        }
        if non_canon_y || sig_y == 0 {
            y_is_zero = true
        }
        if x_is_zero && y_is_zero {
            return true
        } else if (x_is_zero && !y_is_zero) || (!x_is_zero && y_is_zero) {
            return false
        }
        // OPPOSITE SIGN (CASE5)
        // now, if the sign bits differ => not equal : return 0
        if ((x ^ y) & MASK_SIGN32) != 0 {
            return false
        }
        // REDUNDANT REPRESENTATIONS (CASE6)
        if exp_x > exp_y {
            // to simplify the loop below,
            swap(&exp_x, &exp_y)  // put the larger exp in y,
            swap(&sig_x, &sig_y)  // and the smaller exp in x
        }
        if exp_y - exp_x > 6 {
            return false    // difference cannot be greater than 10^6
        }
        for _ in 0..<(exp_y - exp_x) {
            // recalculate y's significand upwards
            sig_y = sig_y * 10;
            if (sig_y > MAX_NUMBER) {
                return false
            }
        }
        return (sig_y == sig_x)
    }

    
    static func lessThan (_ x: UInt32, _ y: UInt32, _ status: inout Status) -> Bool {
        // NaN (CASE1)
        // if either number is NAN, the comparison is unordered : return 0
        if (x & NAN_MASK32) == NAN_MASK32 || (y & NAN_MASK32) == NAN_MASK32 {
            // set invalid exception if NaN
            status.insert(.invalidOperation)
            return false
        }
        
        // SIMPLE (CASE2)
        // if all the bits are the same, these numbers are equal.
        if x == y { return false }
        
        // INFINITY (CASE3)
        if (x & INFINITY_MASK32) == INFINITY_MASK32 {
            // if x==neg_inf, { res = (y == neg_inf)?0:1; BID_RETURN (res) }
            if (x & SIGN_MASK32) == SIGN_MASK32 {
                // x is -inf, so it is less than y unless y is -inf
                return (((y & INFINITY_MASK32) != INFINITY_MASK32) || (y & SIGN_MASK32) != SIGN_MASK32)
            } else {
                // x is pos_inf, no way for it to be less than y
                return false
            }
        } else if (y & INFINITY_MASK32) == INFINITY_MASK32 {
            // x is finite, so:
            //    if y is +inf, x<y
            //    if y is -inf, x>y
            return (y & SIGN_MASK32) != SIGN_MASK32
        }
        // if steering bits are 11 (condition will be 0), then exponent is G[0:w+1] =>
//        var exp_x, exp_y: Int
//        var sig_x, sig_y: UInt32
//        var non_canon_x, non_canon_y: Bool
        let (exp_x, sig_x, non_canon_x) = extractExpSig(x)
//        if (x & SPECIAL_ENCODING_MASK32) == SPECIAL_ENCODING_MASK32 {
//            exp_x = Int((x & MASK_BINARY_EXPONENT2_32) >> 21)
//            sig_x = (x & SMALL_COEFF_MASK32) | LARGE_COEFF_HIGH_BIT32
//            if sig_x > BID32_SIG_MAX {
//                non_canon_x = true
//            } else {
//                non_canon_x = false
//            }
//        } else {
//            exp_x = Int((x & MASK_BINARY_EXPONENT1_32) >> 23)
//            sig_x = x & LARGE_COEFF_MASK32
//            non_canon_x = false
//        }
        
        // if steering bits are 11 (condition will be 0), then exponent is G[0:w+1] =>
        let (exp_y, sig_y, non_canon_y) = extractExpSig(y)
//        if (y & SPECIAL_ENCODING_MASK32) == SPECIAL_ENCODING_MASK32 {
//            exp_y = Int((y & MASK_BINARY_EXPONENT2_32) >> 21)
//            sig_y = (y & SMALL_COEFF_MASK32) | LARGE_COEFF_HIGH_BIT32
//            if sig_y > BID32_SIG_MAX {
//                non_canon_y = true
//            } else {
//                non_canon_y = false
//            }
//        } else {
//            exp_y = Int((y & MASK_BINARY_EXPONENT1_32) >> 23)
//            sig_y = y & LARGE_COEFF_MASK32
//            non_canon_y = false
//        }
        
        // ZERO (CASE4)
        // some properties:
        // (+ZERO==-ZERO) => therefore ignore the sign, and neither number is greater
        //    (ZERO x 10^A == ZERO x 10^B) for any valid A, B =>
        //      therefore ignore the exponent field
        //    (Any non-canonical # is considered 0)
        var x_is_zero = false, y_is_zero = false
        if non_canon_x || sig_x == 0 {
            x_is_zero = true
        }
        if non_canon_y || sig_y == 0 {
            y_is_zero = true
        }
        
        // if both numbers are zero, they are equal
        if x_is_zero && y_is_zero {
            return false
        } else if x_is_zero {
            // if x is zero, it is less than if Y is positive
            return (y & SIGN_MASK32) != SIGN_MASK32
        } else if y_is_zero {
            // if y is zero, X is less if it is negative
            return (x & SIGN_MASK32) == SIGN_MASK32
        }
        
        // OPPOSITE SIGN (CASE5)
        // now, if the sign bits differ, x is less than if y is positive
        if ((x ^ y) & SIGN_MASK32) == SIGN_MASK32 {
            return (y & SIGN_MASK32) != SIGN_MASK32
        }
        
        // REDUNDANT REPRESENTATIONS (CASE6)
        // if both components are either bigger or smaller
        if sig_x > sig_y && exp_x >= exp_y {
            return (x & SIGN_MASK32) == SIGN_MASK32
        }
        if sig_x < sig_y && exp_x <= exp_y {
            return (x & SIGN_MASK32) != SIGN_MASK32
        }
        
        // if exp_x is 6 greater than exp_y, no need for compensation
        if exp_x - exp_y > 6 {
            return (x & SIGN_MASK32) == SIGN_MASK32
        }
        
        // difference cannot be greater than 10^6
        // if exp_x is 6 less than exp_y, no need for compensation
        if exp_y - exp_x > 6 {
            return (x & SIGN_MASK32) != SIGN_MASK32
        }
        
        // if |exp_x - exp_y| < 6, it comes down to the compensated significand
        var sig_n_prime: UInt64
        if exp_x > exp_y {
            // otherwise adjust the x significand upwards
            sig_n_prime = UInt64(sig_x) * UInt64(bid_mult_factor[exp_x - exp_y])
            
            // return false if values are equal
            if sig_n_prime == sig_y { return false }
            
            // if postitive, return whichever significand abs is smaller
            //     (converse if negative)
            return (sig_n_prime < sig_y) != ((x & SIGN_MASK32) == SIGN_MASK32)
        }
        // adjust the y significand upwards
        sig_n_prime = UInt64(sig_y) * UInt64(bid_mult_factor[Int(exp_y - exp_x)])
        
        // return 0 if values are equal
        if sig_n_prime == sig_x { return false }
        
        // if positive, return whichever significand abs is smaller
        //     (converse if negative)
        return (sig_x < sig_n_prime) != ((x & SIGN_MASK32) == SIGN_MASK32)
    }
    
    /*****************************************************************************
     *  BID32 nextup
     ****************************************************************************/
    static func bid32_nextup (_ x: UInt32, _ pfpsf: inout Status) -> UInt32 {
        var x = x
        var res : UInt32
        
        // check for NaNs and infinities
        if (x & MASK_NAN32) == MASK_NAN32 { // check for NaN
            if (x & 0x000fffff) > 999999 {
                x = x & 0xfe00_0000 // clear G6-G10 and the payload bits
            } else {
                x = x & 0xfe0f_ffff // clear G6-G10
            }
            if (x & MASK_SNAN32) == MASK_SNAN32 { // SNaN
                // set invalid flag
                pfpsf.insert(.invalidOperation)
                // pfpsf |= BID_INVALID_EXCEPTION;
                // return quiet (SNaN)
                res = x & 0xfdff_ffff
            } else {    // QNaN
                res = x
            }
            return res
        } else if (x & MASK_INF32) == MASK_INF32 { // check for Infinity
            if (x & MASK_SIGN32) == 0 { // x is +inf
                res = INFINITY_MASK32
            } else { // x is -inf
                res = 0xf7f8_967f    // -MAXFP = -9999999 * 10^emax
            }
            return res
        }
        // unpack the argument
        let x_sign = x & MASK_SIGN32 // 0 for positive, MASK_SIGN32 for negative
        // var x_exp, C1:UInt32
        // if steering bits are 11 (condition will be 0), then exponent is G[0:7]
        var (x_exp, C1) = extractExpSig(x)
//        if (x & MASK_STEERING_BITS32) == MASK_STEERING_BITS32 {
//            x_exp = (x & MASK_BINARY_EXPONENT2_32) >> 21 // biased
//            C1 = (x & MASK_BINARY_SIG2_32) | MASK_BINARY_OR2_32
//            if C1 > BID32_SIG_MAX {    // non-canonical
//                x_exp = 0
//                C1 = 0
//            }
//        } else {
//            x_exp = (x & MASK_BINARY_EXPONENT1_32) >> 23 // biased
//            C1 = x & MASK_BINARY_SIG1_32
//        }
        
        // check for zeros (possibly from non-canonical values)
        if C1 == 0 {
            // x is 0
            res = 0x00000001 // MINFP = 1 * 10^emin
        } else { // x is not special and is not zero
            if x == LARGEST_BID32 {
                // x = +MAXFP = 9999999 * 10^emax
                res = INFINITY_MASK32 // +inf
            } else if x == 0x80000001 {
                // x = -MINFP = 1...99 * 10^emin
                res = MASK_SIGN32 // -0
            } else { // -MAXFP <= x <= -MINFP - 1 ulp OR MINFP <= x <= MAXFP - 1 ulp
                // can add/subtract 1 ulp to the significand
                
                // Note: we could check here if x >= 10^7 to speed up the case q1 = 7
                // q1 = nr. of decimal digits in x (1 <= q1 <= 7)
                //  determine first the nr. of bits in x
                let q1 = digitsIn(C1)

                // if q1 < P7 then pad the significand with zeros
                if q1 < P7 {
                    let ind:Int
                    if x_exp > (P7 - q1) {
                        ind = P7 - q1; // 1 <= ind <= P7 - 1
                        // pad with P7 - q1 zeros, until exponent = emin
                        // C1 = C1 * 10^ind
                        C1 = C1 * UInt32(bid_ten2k64[ind])
                        x_exp = x_exp - ind
                    } else { // pad with zeros until the exponent reaches emin
                        ind = x_exp
                        C1 = C1 * UInt32(bid_ten2k64[ind])
                        x_exp = MIN_EXPON
                    }
                }
                if x_sign == 0 {    // x > 0
                    // add 1 ulp (add 1 to the significand)
                    C1 += 1
                    if C1 == 10_000_000 { // if  C1 = 10^7
                        C1 = 1_000_000 // C1 = 10^6
                        x_exp += 1
                    }
                    // Ok, because MAXFP = 9999999 * 10^emax was caught already
                } else {    // x < 0
                    // subtract 1 ulp (subtract 1 from the significand)
                    C1 -= 1
                    if C1 == 999_999 && x_exp != 0 { // if  C1 = 10^6 - 1
                        C1 = UInt32(MAX_NUMBER) // C1 = 10^7 - 1
                        x_exp -= 1
                    }
                }
                // assemble the result
                // if significand has 24 bits
                if (C1 & MASK_BINARY_OR2_32) != 0 {
                    res = x_sign | UInt32(x_exp << 21) | MASK_STEERING_BITS32 | (C1 & MASK_BINARY_SIG2_32)
                } else {    // significand fits in 23 bits
                    res = x_sign | UInt32(x_exp << 23) | C1
                }
            } // end -MAXFP <= x <= -MINFP - 1 ulp OR MINFP <= x <= MAXFP - 1 ulp
        } // end x is not special and is not zero
        return res
    }

    
    static func mul (_ x:UInt32, _ y:UInt32, _ rmode:Rounding, _ status:inout Status) -> UInt32  {
        var sign_x = UInt32(0), sign_y = UInt32(0), exponent_x = 0, exponent_y = 0
        var coefficient_x = UInt32(0), coefficient_y = UInt32(0)
        let valid_x = unpack_BID32 (&sign_x, &exponent_x, &coefficient_x, x)
        let valid_y = unpack_BID32 (&sign_y, &exponent_y, &coefficient_y, y)
        
        // unpack arguments, check for NaN or Infinity
        if !valid_x {
            if (y & SNAN_MASK32) == SNAN_MASK32 {
                // y is sNaN
                status.insert(.invalidOperation)
            }
            // x is Inf. or NaN
            
            // test if x is NaN
            if (x & NAN_MASK32) == NAN_MASK32 {
                if (x & SNAN_MASK32) == SNAN_MASK32 {   // sNaN
                    status.insert(.invalidOperation)
                    // __set_status_flags (pfpsf, BID_INVALID_EXCEPTION);
                }
                return (coefficient_x & QUIET_MASK32);
            }
            // x is Infinity?
            if (x & INFINITY_MASK32) == INFINITY_MASK32 {
                // check if y is 0
                if (y & INFINITY_MASK32) != INFINITY_MASK32 && (coefficient_y == 0) {
                    status.insert(.invalidOperation)
                    // y==0 , return NaN
                    return NAN_MASK32
                }
                // check if y is NaN
                if (y & NAN_MASK32) == NAN_MASK32 {
                    // y==NaN , return NaN
                   return coefficient_y & QUIET_MASK32
                }
                // otherwise return +/-Inf
                return ((x ^ y) & SIGN_MASK32) | INFINITY_MASK32
            }
            // x is 0
            if (y & INFINITY_MASK32) != INFINITY_MASK32 {
                if (y & SPECIAL_ENCODING_MASK32) == SPECIAL_ENCODING_MASK32 {
                    exponent_y = Int(UInt32(y >> 21)) & 0xff
                } else {
                    exponent_y = Int(UInt32(y >> 23)) & 0xff
                }
                sign_y = y & SIGN_MASK32
                
                exponent_x += exponent_y - EXPONENT_BIAS
                if (exponent_x > MAX_EXPON) {
                    exponent_x = MAX_EXPON
                } else if (exponent_x < 0) {
                    exponent_x = 0
                }
               return UInt32(UInt64(sign_x ^ sign_y) | (UInt64(exponent_x) << 23))
            }
        }
        if !valid_y {
            // y is Inf. or NaN
            // test if y is NaN
            if (y & NAN_MASK32) == NAN_MASK32 {
                if (y & SNAN_MASK32) == SNAN_MASK32 {
                    // sNaN
                    status.insert(.invalidOperation)
                }
                return coefficient_y & QUIET_MASK32
            }
            // y is Infinity?
            if (y & INFINITY_MASK32) == INFINITY_MASK32 {
                // check if x is 0
                if coefficient_x == 0 {
                    status.insert(.invalidOperation)
                    // x==0, return NaN
                    return (NAN_MASK32);
                }
                // otherwise return +/-Inf
                return ((x ^ y) & SIGN_MASK32) | INFINITY_MASK32
            }
            // y is 0
            exponent_x += exponent_y - EXPONENT_BIAS
            if exponent_x > MAX_EXPON {
                exponent_x = MAX_EXPON
            } else if exponent_x < 0 {
                exponent_x = 0
            }
            return UInt32(UInt64(sign_x ^ sign_y) | (UInt64(exponent_x) << 23))
        }
        
        var P = UInt64(coefficient_x) * UInt64(coefficient_y)
        
        //--- get number of bits in C64 ---
        // version 2 (original)
        let tempx = Double(P)
        let bin_expon_p = (Int(tempx.bitPattern & Decimal64.MASK_BINARY_EXPONENT) >> 52) - BINARY_EXPONENT_BIAS
        var n_digits = Int(bid_estimate_decimal_digits[bin_expon_p])
        if P >= bid_power10_table_128[n_digits].w[0] {
            n_digits+=1
        }
        
        exponent_x += exponent_y - EXPONENT_BIAS
        
        let extra_digits = Int((n_digits<=7) ? 0 : (n_digits - 7))
        
        exponent_x += extra_digits
        
        if extra_digits == 0 {
            return get_BID32 (sign_x ^ sign_y, exponent_x, UInt32(P), rmode, &status)
        }
        
        var rmode1 = roundboundIndex(rmode, (sign_x^sign_y) != 0, 0)
//        if (sign_x ^ sign_y) != 0 && UInt32(rmode1 - 1) < 2 {
//            rmode1 = 3 - rmode1
//        }
        
        if exponent_x < 0 { rmode1 = 3 }  // RZ
        
        // add a constant to P, depending on rounding mode
        // 0.5*10^(digits_p - 16) for round-to-nearest
        P += bid_round_const_table[rmode1][extra_digits]
        var Tmp = UInt128()
        __mul_64x64_to_128(&Tmp, P, bid_reciprocals10_64[extra_digits])
        
        // now get P/10^extra_digits: shift Q_high right by M[extra_digits]-64
        let amount = bid_short_recip_scale[extra_digits];
        var Q = Tmp.w[1] >> amount
        
        // remainder
        let R = P - Q * bid_power10_table_128[extra_digits].w[0]
        
        if R == bid_round_const_table[rmode1][extra_digits] {
            status = []
        } else {
            status.insert(.inexact)
        }
        
        // __set_status_flags (pfpsf, status);
        
        if rmode1 == 0 {    //BID_ROUNDING_TO_NEAREST
            if R==0 {
                Q &= 0xffff_fffe
            }
        }
        
        if (exponent_x == -1) && (Q == MAX_NUMBER) && (rmode != BID_ROUNDING_TO_ZERO) {
            rmode1 = roundboundIndex(rmode, (sign_x^sign_y) != 0, 0)
//            if ((sign_x^sign_y != 0) && UInt32(rmode1 - 1) < 2) {
//                rmode1 = 3 - rmode1
//            }
            
            if ((R != 0) && (rmode == BID_ROUNDING_UP)) || ((rmode1&3 == 0) && (R+R>=bid_power10_table_128[extra_digits].w[0])) {
                return very_fast_get_BID32(sign_x^sign_y, 0, 1000000)
            }
        }
        
        return get_BID32_UF (sign_x^sign_y, Int(exponent_x), Q, Int(R), rmode, &status)
    }
    
    /*****************************************************************************
     *    BID32 divide
     *****************************************************************************
     *
     *  Algorithm description:
     *
     *  if(coefficient_x<coefficient_y)
     *    p = number_digits(coefficient_y) - number_digits(coefficient_x)
     *    A = coefficient_x*10^p
     *    B = coefficient_y
     *    CA= A*10^(15+j), j=0 for A>=B, 1 otherwise
     *    Q = 0
     *  else
     *    get Q=(int)(coefficient_x/coefficient_y)
     *        (based on double precision divide)
     *    check for exact divide case
     *    Let R = coefficient_x - Q*coefficient_y
     *    Let m=16-number_digits(Q)
     *    CA=R*10^m, Q=Q*10^m
     *    B = coefficient_y
     *  endif
     *    if (CA<2^64)
     *      Q += CA/B  (64-bit unsigned divide)
     *    else
     *      get final Q using double precision divide, followed by 3 integer
     *          iterations
     *    if exact result, eliminate trailing zeros
     *    check for underflow
     *    round coefficient to nearest
     *
     ****************************************************************************/
    
    static func div(_ x:UInt32, _ y:UInt32, _ rmode:Rounding, _ status:inout Status) -> UInt32 {
        //      BID_OPT_SAVE_BINARY_FLAGS()
        var sign_x = UInt32(0), sign_y = UInt32(0), exponent_x = 0, exponent_y = 0
        var coefficient_x = UInt32(0), coefficient_y = UInt32(0)
        let valid_x = unpack_BID32 (&sign_x, &exponent_x, &coefficient_x, x)
        let valid_y = unpack_BID32 (&sign_y, &exponent_y, &coefficient_y, y)
        
        // unpack arguments, check for NaN or Infinity
        if !valid_x {
            // x is Inf. or NaN
            if (y & SNAN_MASK32) == SNAN_MASK32 {   // y is sNaN
                status.insert(.invalidOperation)
                //__set_status_flags (pfpsf, BID_INVALID_EXCEPTION);
            }
            
            // test if x is NaN
            if (x & NAN_MASK32) == NAN_MASK32 {
                if (x & SNAN_MASK32) == SNAN_MASK32 {    // sNaN
                    status.insert(.invalidOperation)
                }
                return coefficient_x & QUIET_MASK32
            }
            // x is Infinity?
            if (x & INFINITY_MASK32) == INFINITY_MASK32 {
                // check if y is Inf or NaN
                if (y & INFINITY_MASK32) == INFINITY_MASK32 {
                    // y==Inf, return NaN
                    if (y & NAN_MASK32) == INFINITY_MASK32 {    // Inf/Inf
                        status.insert(.invalidOperation)
                        return NAN_MASK32
                    }
                } else {
                    // otherwise return +/-Inf
                    return ((x ^ y) & SIGN_MASK32) | INFINITY_MASK32
                }
            }
            // x==0
            if ((y & INFINITY_MASK32) != INFINITY_MASK32) && coefficient_y == 0 {
                // y==0 , return NaN
                status.insert(.invalidOperation)
                return NAN_MASK32
            }
            if (y & INFINITY_MASK32) != INFINITY_MASK32 {
                if (y & SPECIAL_ENCODING_MASK32) == SPECIAL_ENCODING_MASK32 {
                    exponent_y = Int((UInt32(y >> 21)) & 0xff)
                } else {
                    exponent_y = Int((UInt32(y >> 23)) & 0xff)
                    sign_y = y & SIGN_MASK32
                }
                
                exponent_x = exponent_x - exponent_y + EXPONENT_BIAS
                if exponent_x > MAX_EXPON {
                    exponent_x = MAX_EXPON
                } else if exponent_x < 0 {
                    exponent_x = 0
                }
                return UInt32(sign_x ^ sign_y) | UInt32(exponent_x) << 23
            }
            
        }
        if !valid_y {
            // y is Inf. or NaN
            // test if y is NaN
            if (y & NAN_MASK32) == NAN_MASK32 {
                if (y & SNAN_MASK32) == SNAN_MASK32 {
                    // sNaN
                    status.insert(.invalidOperation)
                }
                return coefficient_y & QUIET_MASK32
            }
            
            // y is Infinity?
            if (y & INFINITY_MASK32) == INFINITY_MASK32 {
                // return +/-0
                return (x ^ y) & SIGN_MASK32
            }
            
            // y is 0
            status.insert(.divisionByZero)
            return ((sign_x ^ sign_y) | INFINITY_MASK32)
        }
        var diff_expon = exponent_x - exponent_y + EXPONENT_BIAS
        
        var A, B, Q, R: UInt32
        var CA: UInt64
        var ed1, ed2: Int
        if coefficient_x < coefficient_y {
            // get number of decimal digits for c_x, c_y
            //--- get number of bits in the coefficients of x and y ---
            let tempx = Float(coefficient_x)
            let tempy = Float(coefficient_y)
            let bin_index = Int((tempy.bitPattern - tempx.bitPattern) >> 23)
            A = coefficient_x * UInt32(bid_power10_index_binexp[bin_index])
            B = coefficient_y
            
            // compare A, B
            let DU = (A - B) >> 31
            ed1 = 6 + Int(DU)
            ed2 = Int(bid_estimate_decimal_digits[bin_index]) + ed1
            let T = bid_power10_table_128[ed1].w[0]
            CA = UInt64(A) * T
            
            Q = 0
            diff_expon = diff_expon - ed2
            
        } else {
            // get c_x/c_y
            Q = coefficient_x/coefficient_y;
            
            R = coefficient_x - coefficient_y * Q;
            
            // will use to get number of dec. digits of Q
            let tempq = Float(Q)
            let bin_expon_cx = Int(tempq.bitPattern >> 23) - 0x7f
            
            // exact result ?
            if R == 0 {
                return get_BID32 (sign_x ^ sign_y, diff_expon, Q, rmode, &status)
            }
            // get decimal digits of Q
            var DU = UInt32(bid_power10_index_binexp[bin_expon_cx]) - Q - 1;
            DU >>= 31;
            
            ed2 = 7 - Int(bid_estimate_decimal_digits[bin_expon_cx]) - Int(DU)
            
            let T = bid_power10_table_128[ed2].w[0]
            CA = UInt64(R) * T
            B = coefficient_y
            
            Q *= UInt32(bid_power10_table_128[ed2].w[0])
            diff_expon -= ed2
        }
        
        let Q2 = UInt32(CA / UInt64(B))
        let B2 = B + B
        let B4 = B2 + B2
        R = UInt32(CA - UInt64(Q2) * UInt64(B))
        Q += Q2
        
        if R != 0 {
            // set status flags
            status.insert(.inexact)
        } else {
            // eliminate trailing zeros
            // check whether CX, CY are short
            if (coefficient_x <= 1024) && (coefficient_y <= 1024) {
                let i = Int(coefficient_y) - 1;
                let j = Int(coefficient_x) - 1;
                // difference in powers of 2 bid_factors for Y and X
                var nzeros = ed2 - Int(bid_factors[i][0] + bid_factors[j][0])
                // difference in powers of 5 bid_factors
                let d5 = ed2 - Int(bid_factors[i][1] + bid_factors[j][1])
                if d5 < nzeros {
                    nzeros = d5
                }
                
                if nzeros != 0 {
                    var CT = UInt64(Q) * bid_bid_reciprocals10_32[nzeros]
                    CT >>= 32
                    
                    // now get P/10^extra_digits: shift C64 right by M[extra_digits]-128
                    let amount = bid_bid_bid_recip_scale32[nzeros];
                    Q = UInt32(CT >> amount)
                    
                    diff_expon += nzeros
                }
            } else {
                var nzeros = 0
                
                // decompose digit
                let PD = UInt64(Q) * 0x068DB8BB
                var digit_h = UInt32(PD >> 40)
                let digit_low = Q - digit_h * 10000
                
                if digit_low == 0 {
                    nzeros += 4
                } else {
                    digit_h = digit_low
                }
                
                if (digit_h & 1) == 0 {
                    nzeros += Int(3 & UInt32(bid_packed_10000_zeros[Int(digit_h >> 3)] >> digit_h & 7))
                }
                
                if nzeros != 0 {
                    var CT = UInt64(Q) * bid_bid_reciprocals10_32[nzeros];
                    CT >>= 32
                    
                    // now get P/10^extra_digits: shift C64 right by M[extra_digits]-128
                    let amount = bid_bid_bid_recip_scale32[nzeros];
                    Q = UInt32(CT >> amount);
                }
                diff_expon += nzeros
                
            }
            if diff_expon >= 0 {
                return get_BID32 (sign_x ^ sign_y, diff_expon, Q, rmode, &status)
            }
        }
        
        if diff_expon >= 0 {
            let rmode1 = roundboundIndex(rmode, (sign_x ^ sign_y) != 0, 0)
//            if (sign_x ^ sign_y) != 0 && UInt32(rmode1 - 1) < 2 {
//                rmode1 = 3 - rmode1
//            }
            switch rmode1 {
                case 0, 4:
                    // R*10
                    R += R
                    R = (R << 2) + R
                    let B5 = B4 + B
                    // compare 10*R to 5*B
                    R = B5 &- R
                    // correction for (R==0 && (Q&1))
                    R -= ((Q | UInt32(rmode1 >> 2)) & 1)
                    // R<0 ?
                    let D = UInt32(R) >> 31
                    Q += D
                case 1, 3:
                    break
                default:    // rounding up
                    Q+=1
            }
            return get_BID32 (sign_x ^ sign_y, diff_expon, Q, rmode, &status)
        } else {
            // UF occurs
            if diff_expon + 7 < 0 {
                // set status flags
                status.insert(.inexact)
            }
            //rmode = rnd_mode;
            return get_BID32_UF (sign_x ^ sign_y, diff_expon, UInt64(Q), Int(R), rmode, &status)
        }
    }

    
    static func sqrt(_ x: UInt32, _ rmode:Rounding, _ status:inout Status) -> UInt32 {
        // unpack arguments, check for NaN or Infinity
        var sign_x = UInt32(0), exponent_x = 0, coefficient_x = UInt32(0)
        if !unpack_BID32 (&sign_x, &exponent_x, &coefficient_x, x) {
            // x is Inf. or NaN or 0
            if (x & INFINITY_MASK32) == INFINITY_MASK32 {
                var res = coefficient_x
                if (coefficient_x & SSNAN_MASK32) == SINFINITY_MASK32 {   // -Infinity
                    res = NAN_MASK32
                    status.insert(.invalidOperation)
                    //__set_status_flags (pfpsf, BID_INVALID_EXCEPTION);
                }
                if (x & SNAN_MASK32) == SNAN_MASK32 {   // sNaN
                    status.insert(.invalidOperation)
                }
                return res & QUIET_MASK32
            }
            // x is 0
            exponent_x = (exponent_x + EXPONENT_BIAS) >> 1
            return sign_x | (UInt32(exponent_x) << 23)
        }
        // x<0?
        if (sign_x != 0) && (coefficient_x != 0) {
            status.insert(.invalidOperation)
            return NAN_MASK32
        }
        
        //--- get number of bits in the coefficient of x ---
        let tempx = Float32(coefficient_x)
        let bin_expon_cx = Int(((tempx.bitPattern >> 23) & 0xff) - 0x7f)
        var digits_x = bid_estimate_decimal_digits[bin_expon_cx];
        // add test for range
        if coefficient_x >= bid_power10_index_binexp[bin_expon_cx] {
            digits_x+=1
        }
        
        var A10 = coefficient_x
        if exponent_x & 1 == 0 {
            A10 = (A10 << 2) + A10;
            A10 += A10;
        }
        
        let dqe = Foundation.sqrt(Double(A10))
        let QE = UInt32(dqe)
        if QE * QE == A10 {
            return very_fast_get_BID32 (0, (exponent_x + EXPONENT_BIAS) >> 1, QE);
        }
        // if exponent is odd, scale coefficient by 10
        var scale = Int(13 - digits_x)
        var exponent_q = exponent_x + EXPONENT_BIAS - scale
        scale += (exponent_q & 1);    // exp. bias is even
        
        let CT = bid_power10_table_128[scale].w[0]
        let CA = UInt64(coefficient_x) * CT
        let dq = Foundation.sqrt(Double(CA))
        
        exponent_q = (exponent_q) >> 1;
        
        status.insert(.inexact)
        // __set_status_flags (pfpsf, BID_INEXACT_EXCEPTION);
        
        let rnd_mode = roundboundIndex(rmode) >> 2
        var Q:UInt32
        if ((rnd_mode) & 3) == 0 {
            Q = UInt32(dq+0.5)
        } else {
            Q = UInt32(dq)
            
            /*// get sign(sqrt(CA)-Q)
             R = CA - Q * Q;
             R = ((BID_SINT32) R) >> 31;
             D = R + R + 1;
             
             C4 = CA;
             Q += D;
             if ((BID_SINT32) (Q * Q - C4) > 0)
             Q--;*/
            if (rmode == BID_ROUNDING_UP) {
                Q+=1
            }
        }
        return fast_get_BID32 (0, exponent_q, Q);
    }
    
    static func digitsIn(_ sig_x: UInt32) -> Int {
        let tmp = Float(sig_x) // exact conversion
        let x_nr_bits = 1 + Int(((UInt(tmp.bitPattern >> 23)) & 0xff) - 0x7f)
        var q = Int(bid_nr_digits[x_nr_bits - 1].digits)
        if q == 0 {
            q = Int(bid_nr_digits[x_nr_bits - 1].digits1)
            if UInt64(sig_x) >= bid_nr_digits[x_nr_bits - 1].threshold_lo {
                q+=1
            }
        }
        return q
    }
    
    /*
     If x is not a floating-point number, the results are unspecified (this
     implementation returns x and *exp = 0). Otherwise, the frexp function
     returns the value res, such that res has a magnitude in the interval
     [1, 10] or zero, and x = res*2^exp. If x is zero, both parts of the
     result are zero. `frexp` does not raise any exceptions
     */
    static func frexp(_ x: UInt32, _ res: inout UInt32, _ exp: inout Int) {
        if (x & MASK_INF32) == MASK_INF32 {
            // if NaN or infinity
            exp = 0
            res = x
            // the binary frexp quietizes SNaNs, so do the same
            if ((x & MASK_SNAN32) == MASK_SNAN32) { // x is SNAN
                //   // set invalid flag
                //   *pfpsf |= BID_INVALID_EXCEPTION;
                // return quiet (x)
                res = x & 0xfdffffff
                // } else {
                //   res = x;
            }
        } else {
            // x is 0, non-canonical, normal, or subnormal
            // decode number into exponent and significand
            var exp_x = UInt32(), sig_x = UInt32()
            if (x & MASK_STEERING_BITS32) == MASK_STEERING_BITS32 {
                exp_x = (x & MASK_BINARY_EXPONENT2_32) >> 21
                sig_x = (x & MASK_BINARY_SIG2_32) | MASK_BINARY_OR2_32
                // check for zero or non-canonical
                if sig_x > MAX_NUMBER || sig_x == 0 {
                    exp = 0
                    res = (x & SIGN_MASK32) | (exp_x << 23) // zero of the same sign
                    return
                }
            } else {
                exp_x = (x & MASK_BINARY_EXPONENT1_32) >> 23
                sig_x = x & MASK_BINARY_SIG1_32
                if sig_x == 0 {
                    exp = 0
                    res = (x & SIGN_MASK32) | (exp_x << 23) // zero of the same sign
                    return
                }
            }
            // x is normal or subnormal, with exp_x=biased exponent & sig_x=coefficient
            // determine the number of decimal digits in sig_x, which fits in 24 bits
            // q = nr. of decimal digits in sig_x (1 <= q <= 7)
            //  determine first the nr. of bits in sig_x
            var q = digitsIn(sig_x)
            q-=1  // adjust so result is between 1 and 10
            // Do not add trailing zeros if q < 7; leave sig_x with q digits
            // sig_x = sig_x * bid_mult_factor[7 - q]; // sig_x has now 7 digits
            exp = Int(exp_x) - EXPONENT_BIAS + q
            // assemble the result
            if (sig_x < LARGE_COEFF_HIGH_BIT32) { // sig_x < 2^23 (fits in 23 bits)
                // res = (x & SIGN_MASK32) | ((-q + DECIMAL_EXPONENT_BIAS_32) << 23) | sig_x;
                res = UInt32(x & 0x807fffff) | UInt32((-q + EXPONENT_BIAS) << 23) // replace exponent
            } else { // sig_x fits in 24 bits, but not in 23
                // res = (x & SIGN_MASK32) | 0x60000000 |
                //     ((-q + DECIMAL_EXPONENT_BIAS_32) << 21) | (sig_x & 0x001fffff);
                res = UInt32(x & 0xe01fffff) | UInt32((-q + EXPONENT_BIAS) << 21) // replace exponent
            }
        }
    }
    
    //////////////////////////////////////////////////////////////////////////
    //
    //    0*10^ey + cz*10^ez,   ey<ez
    //
    //////////////////////////////////////////////////////////////////////////
    static func add_zero32 (_ exponent_y:Int, _ sign_z:UInt32, _ exponent_z:Int,
                            _ coefficient_z:UInt32, _ rounding_mode:Rounding, _ fpsc:inout Status) -> UInt64 {
        let diff_expon = exponent_z - exponent_y
        var coefficient_z = coefficient_z
        
        let tempx = Double(coefficient_z)
        let bin_expon = Int(((tempx.bitPattern & Decimal64.MASK_BINARY_EXPONENT) >> 52)) - BINARY_EXPONENT_BIAS
        var scale_cz = Int(bid_estimate_decimal_digits[bin_expon])
        if coefficient_z >= bid_power10_table_128[scale_cz].w[0] {
            scale_cz+=1
        }
        
        var scale_k = 7 - scale_cz
        if diff_expon < scale_k {
            scale_k = diff_expon
        }
        coefficient_z *= UInt32(bid_power10_table_128[scale_k].w[0])
        
        return UInt64(get_BID32(sign_z, exponent_z - scale_k, coefficient_z, rounding_mode, &fpsc))
    }
    
    /*****************************************************************************
     *    BID32 fma
     *****************************************************************************
     *
     *  Algorithm description:
     *
     *  if multiplication is guranteed exact (short coefficients)
     *     call the unpacked arg. equivalent of bid32_add(x*y, z)
     *  else
     *     get full coefficient_x*coefficient_y product
     *     call subroutine to perform addition of 32-bit argument
     *                                         to 128-bit product
     *
     ****************************************************************************/
    static func bid32_fma(_ x:UInt32, _ y:UInt32, _ z:UInt32, _ rmode:Rounding, _ pfpsf:inout Status) -> UInt32 {
        var sign_x = UInt32(), exponent_x = 0, coefficient_x = UInt32()
        var sign_y = UInt32(), exponent_y = 0, coefficient_y = UInt32()
        var sign_z = UInt32(), exponent_z = 0, coefficient_z = UInt32()
        let valid_x = unpack_BID32(&sign_x, &exponent_x, &coefficient_x, x)
        let valid_y = unpack_BID32(&sign_y, &exponent_y, &coefficient_y, y)
        let valid_z = unpack_BID32(&sign_z, &exponent_z, &coefficient_z, z)
        
        // unpack arguments, check for NaN, Infinity, or 0
        var res:UInt32
        if !valid_x || !valid_y || !valid_z {
            if (y & NAN_MASK32) == NAN_MASK32 {
                if ((x & SNAN_MASK32) == SNAN_MASK32) || ((y & SNAN_MASK32) == SNAN_MASK32) || ((z & SNAN_MASK32) == SNAN_MASK32) { // sNaN
                    pfpsf.insert(.invalidOperation)
                    //__set_status_flags (pfpsf, BID_INVALID_EXCEPTION);
                }
                return coefficient_y & QUIET_MASK32
            }
            if (z & NAN_MASK32) == NAN_MASK32 {
                if ((x & SNAN_MASK32) == SNAN_MASK32) || ((z & SNAN_MASK32) == SNAN_MASK32) {
                    // sNaN
                    pfpsf.insert(.invalidOperation)
                }
                return coefficient_z & QUIET_MASK32
            }
            if (x & NAN_MASK32) == NAN_MASK32 {
                if (x & SNAN_MASK32) == SNAN_MASK32 {
                    // sNaN
                    pfpsf.insert(.invalidOperation)
                }
                return coefficient_x & QUIET_MASK32
            }
            
            
            if !valid_x {
                // x is Inf. or 0
                
                // x is Infinity?
                if (x & INFINITY_MASK32) == INFINITY_MASK32 {
                    // check if y is 0
                    if coefficient_y == 0 {
                        // y==0, return NaN
                        if (z & SNAN_MASK32) != NAN_MASK32 {
                            pfpsf.insert(.invalidOperation)
                        }
                        return (NAN_MASK32);
                    }
                    // test if z is Inf of oposite sign
                    if (((z & NAN_MASK32) == INFINITY_MASK32) && (((x ^ y) ^ z) & SIGN_MASK32) != 0) {
                        // return NaN
                        pfpsf.insert(.invalidOperation)
                        return NAN_MASK32
                    }
                    // otherwise return +/-Inf
                    return (((x ^ y) & SIGN_MASK32) | INFINITY_MASK32)
                }
                // x is 0
                if (((y & INFINITY_MASK32) != INFINITY_MASK32) && ((z & INFINITY_MASK32) != INFINITY_MASK32)) {
                    
                    if coefficient_z != 0 {
                        exponent_y = exponent_x - EXPONENT_BIAS + exponent_y;
                        
                        sign_z = z & SIGN_MASK32;
                        
                        if (exponent_y >= exponent_z) {
                            return (z);
                        }
                        return UInt32(add_zero32 (exponent_y, sign_z, exponent_z, coefficient_z, rmode, &pfpsf))
                    }
                }
            }
            if !valid_y { // y is Inf. or 0
                // y is Infinity?
                if (y & INFINITY_MASK32) == INFINITY_MASK32 {
                    // check if x is 0
                    if coefficient_x == 0 {
                        // y==0, return NaN
                        pfpsf.insert(.invalidOperation)
                        return NAN_MASK32
                    }
                    // test if z is Inf of oposite sign
                    if (((z & NAN_MASK32) == INFINITY_MASK32) && (((x ^ y) ^ z) & SIGN_MASK32) != 0) {
                        pfpsf.insert(.invalidOperation)
                        // return NaN
                        return NAN_MASK32
                    }
                    // otherwise return +/-Inf
                    return (((x ^ y) & SIGN_MASK32) | INFINITY_MASK32)
                }
                // y is 0
                if (z & INFINITY_MASK32) != INFINITY_MASK32 {
                    
                    if coefficient_z != 0 {
                        exponent_y += exponent_x - EXPONENT_BIAS
                        
                        sign_z = z & SIGN_MASK32
                        
                        if exponent_y >= exponent_z {
                            return z
                        }
                        return UInt32(add_zero32 (exponent_y, sign_z, exponent_z, coefficient_z, rmode, &pfpsf))
                    }
                }
            }
            
            if !valid_z {
                // y is Inf. or 0
                
                // test if y is NaN/Inf
                if (z & INFINITY_MASK32) == INFINITY_MASK32 {
                    return (coefficient_z & QUIET_MASK32);
                }
                // z is 0, return x*y
                if (coefficient_x == 0) || (coefficient_y == 0) {
                    //0+/-0
                    exponent_x += exponent_y - EXPONENT_BIAS;
                    if exponent_x > MAX_EXPON {
                        exponent_x = MAX_EXPON
                    } else if exponent_x < 0 {
                        exponent_x = 0
                        if exponent_x <= exponent_z {
                            res = UInt32(exponent_x) << 23
                        } else {
                            res = UInt32(exponent_z) << 23
                        }
                        if (sign_x ^ sign_y) == sign_z {
                            res |= sign_z
                        } else if rmode == BID_ROUNDING_DOWN {
                            res |= SIGN_MASK32
                        }
                        return res
                    }
                    let d2 = exponent_x + exponent_y - EXPONENT_BIAS
                    if exponent_z > d2 {
                        exponent_z = d2
                    }
                }
            }
        }
        
        let P0 = UInt64(coefficient_x) * UInt64(coefficient_y)
        exponent_x += exponent_y - EXPONENT_BIAS;
        
        // sort arguments by exponent
        var sign_a = UInt32(), exponent_a = 0, coefficient_a = UInt64()
        var sign_b = UInt32(), exponent_b = 0, coefficient_b = UInt64()
        if exponent_x < exponent_z {
            sign_a = sign_z
            exponent_a = exponent_z
            coefficient_a = UInt64(coefficient_z)
            sign_b = sign_x ^ sign_y
            exponent_b = exponent_x
            coefficient_b = P0
        } else {
            sign_a = sign_x ^ sign_y
            exponent_a = exponent_x
            coefficient_a = P0
            sign_b = sign_z
            exponent_b = exponent_z
            coefficient_b = UInt64(coefficient_z)
        }
        
        // exponent difference
        var diff_dec_expon = exponent_a - exponent_b
        var inexact = false
        if diff_dec_expon > 17 {
            let tempx = Double(coefficient_a)
            let bin_expon = Int((tempx.bitPattern & Decimal64.MASK_BINARY_EXPONENT) >> 52) - BINARY_EXPONENT_BIAS
            let scale_ca = Int(bid_estimate_decimal_digits[bin_expon])
            
            let d2 = 31 - scale_ca
            if diff_dec_expon > d2 {
                diff_dec_expon = d2
                exponent_b = exponent_a - diff_dec_expon
            }
            if coefficient_b != 0 {
                inexact=true
            }
        }
        
        var sign_ab = Int64(sign_a ^ sign_b) << 32
        sign_ab = Int64(sign_ab) >> 63
        var CB = UInt128()
        CB.w[0] = UInt64((Int64(coefficient_b) + sign_ab) ^ sign_ab)
        CB.w[1] = UInt64(Int64(CB.w[0]) >> 63)
        
        var Tmp = UInt128(), P = UInt128()
        __mul_64x128_low(&Tmp, coefficient_a, bid_power10_table_128[diff_dec_expon])
        __add_128_128(&P, Tmp, CB)
        if Int64(P.w[1]) < 0 {
            sign_a ^= SIGN_MASK32
            P.w[1] = 0 - P.w[1]
            if P.w[0] != 0 { P.w[1] -= 1 }
            P.w[0] = 0 - P.w[0]
        }
        
        var n_digits = 0
        var bin_expon = 0
        if P.w[1] != 0 {
            let tempx = Double(P.w[1])
            bin_expon = Int((tempx.bitPattern & Decimal64.MASK_BINARY_EXPONENT) >> 52) - BINARY_EXPONENT_BIAS + 64
            n_digits = Int(bid_estimate_decimal_digits[bin_expon])
            if __unsigned_compare_ge_128(P, bid_power10_table_128[n_digits]) {
                n_digits += 1
            }
        } else {
            if P.w[0] != 0 {
                let tempx = Double(P.w[0])
                bin_expon = Int((tempx.bitPattern & Decimal64.MASK_BINARY_EXPONENT) >> 52) - BINARY_EXPONENT_BIAS
                n_digits = Int(bid_estimate_decimal_digits[bin_expon])
                if P.w[0] >= bid_power10_table_128[n_digits].w[0] {
                    n_digits += 1
                }
            } else { // result = 0
                sign_a = 0
                if rmode == BID_ROUNDING_DOWN { sign_a = SIGN_MASK32 }
                if coefficient_a == 0 { sign_a = sign_x }
                n_digits = 0
            }
        }
        
        if n_digits <= MAX_DIGITS {
            return get_BID32_UF (sign_a, exponent_b, P.w[0], 0, rmode, &pfpsf)
        }
        
        let extra_digits = n_digits - 7
        
        var rmode1 = roundboundIndex(rmode, sign_a != 0, 0) // rnd_mode;
        //            if (sign_a && (unsigned) (rmode - 1) < 2) {
        //                rmode = 3 - rmode;
        //            }
        
        
        if exponent_b+extra_digits < 0 { rmode1=3 }  // RZ
        
        // add a constant to P, depending on rounding mode
        // 0.5*10^(digits_p - 16) for round-to-nearest
        var Stemp = UInt128()
        if extra_digits <= 18 {
            __add_128_64(&P, P, bid_round_const_table[rmode1][extra_digits])
        } else {
            __mul_64x64_to_128(&Stemp, bid_round_const_table[rmode1][18], bid_power10_table_128[extra_digits-18].w[0])
            __add_128_128 (&P, P, Stemp)
            if rmode == BID_ROUNDING_UP {
                __add_128_64(&P, P, bid_round_const_table[rmode1][extra_digits-18])
            }
        }
        
        // get P*(2^M[extra_digits])/10^extra_digits
        var Q_high = UInt128(), Q_low = UInt128(), C128 = UInt128()
        __mul_128x128_full (&Q_high, &Q_low, P, bid_reciprocals10_128[extra_digits])
        // now get P/10^extra_digits: shift Q_high right by M[extra_digits]-128
        var amount = bid_recip_scale[extra_digits]
        __shr_128_long (&C128, Q_high, amount)
        
        var C64 = C128.w[0]
        var remainder_h, rem_l:UInt64
        if (C64 & 1) != 0 {
            // check whether fractional part of initial_P/10^extra_digits
            // is exactly .5
            // this is the same as fractional part of
            // (initial_P + 0.5*10^extra_digits)/10^extra_digits is exactly zero
            
            // get remainder
            rem_l = Q_high.w[0]
            if amount < 64 {
                remainder_h = Q_high.w[0] << (64 - amount); rem_l = 0
            } else {
                remainder_h = Q_high.w[1] << (128 - amount)
            }
            
            // test whether fractional part is 0
            if ((remainder_h | rem_l) == 0
                && (Q_low.w[1] < bid_reciprocals10_128[extra_digits].w[1]
                    || (Q_low.w[1] == bid_reciprocals10_128[extra_digits].w[1]
                        && Q_low.w[0] < bid_reciprocals10_128[extra_digits].w[0]))) {
                C64 -= 1
            }
        }
        
        var status = Status.inexact
        var carry = UInt64(), CY = UInt64()
        
        // get remainder
        rem_l = Q_high.w[0]
        if amount < 64 { remainder_h = Q_high.w[0] << (64 - amount); rem_l = 0 }
        else { remainder_h = Q_high.w[1] << (128 - amount) }
        
        switch rmode {
            case BID_ROUNDING_TO_NEAREST, BID_ROUNDING_TIES_AWAY:
                // test whether fractional part is 0
                if ((remainder_h == 0x8000000000000000 && rem_l == 0)
                    && (Q_low.w[1] < bid_reciprocals10_128[extra_digits].w[1]
                        || (Q_low.w[1] == bid_reciprocals10_128[extra_digits].w[1]
                            && Q_low.w[0] < bid_reciprocals10_128[extra_digits].w[0]))) {
                    status = []
                }
            case BID_ROUNDING_DOWN, BID_ROUNDING_TO_ZERO:
                if ((remainder_h | rem_l) == 0
                    && (Q_low.w[1] < bid_reciprocals10_128[extra_digits].w[1]
                        || (Q_low.w[1] == bid_reciprocals10_128[extra_digits].w[1]
                            && Q_low.w[0] < bid_reciprocals10_128[extra_digits].w[0]))) {
                    status = []
                }
            default:
                // round up
                __add_carry_out(&Stemp.w[0], &CY, Q_low.w[0], bid_reciprocals10_128[extra_digits].w[0])
                __add_carry_in_out(&Stemp.w[1], &carry, Q_low.w[1], bid_reciprocals10_128[extra_digits].w[1], CY)
                if amount < 64 {
                    if ((remainder_h >> (64 - amount)) + carry >= (UInt64(1) << amount)) {
                        if !inexact {
                            status = []
                        }
                    }
                } else {
                    rem_l += carry
                    remainder_h >>= (128 - amount)
                    if carry != 0 && rem_l == 0 { remainder_h += 1 }
                    if remainder_h >= (UInt64(1) << (amount-64)) && !inexact {
                        status = []
                    }
                }
        }
        
        pfpsf.formUnion(status)
        
        let R = !status.isEmpty ? 1 : 0
        
        if (UInt32(C64) == MAX_NUMBER) && (exponent_b+extra_digits == -1) && (rmode != BID_ROUNDING_TO_ZERO) {
            rmode1 = roundboundIndex(rmode, sign_a != 0, 0)
            //                if (sign_a && (unsigned) (rmode - 1) < 2) {
            //                    rmode = 3 - rmode;
            //                }
            if extra_digits <= 18 {
                __add_128_64 (&P, P, bid_round_const_table[rmode1][extra_digits]);
            } else {
                __mul_64x64_to_128(&Stemp, bid_round_const_table[rmode1][18], bid_power10_table_128[extra_digits-18].w[0]);
                __add_128_128(&P, P, Stemp)
                if rmode == BID_ROUNDING_UP {
                    __add_128_64(&P, P, bid_round_const_table[rmode1][extra_digits-18]);
                }
            }
            
            // get P*(2^M[extra_digits])/10^extra_digits
            __mul_128x128_full(&Q_high, &Q_low, P, bid_reciprocals10_128[extra_digits])
            // now get P/10^extra_digits: shift Q_high right by M[extra_digits]-128
            amount = bid_recip_scale[extra_digits]
            __shr_128_long(&C128, Q_high, amount);
            
            C64 = C128.w[0]
            if C64 == 10000000 {
                return sign_a | 1000000
            }
        }
        return get_BID32_UF(sign_a, exponent_b+extra_digits, C64, R, rmode, &pfpsf)
    }
    
    static func bid32_rem(_ x:UInt32, _ y:UInt32, _ pfpsf: inout Status) -> UInt32 {
        var sign_x = UInt32(), sign_y = UInt32(), exponent_y = 0, exponent_x = 0
        var coefficient_y = UInt32(), coefficient_x = UInt32()
        let valid_y = unpack_BID32 (&sign_y, &exponent_y, &coefficient_y, y)
        let valid_x = unpack_BID32 (&sign_x, &exponent_x, &coefficient_x, x)
        
        // unpack arguments, check for NaN or Infinity
        if !valid_x {
            // x is Inf. or NaN or 0
            if ((y & SNAN_MASK32) == SNAN_MASK32) {   // y is sNaN
                pfpsf.insert(.invalidOperation)
            }
            
            // test if x is NaN
            if (x & 0x7c000000) == 0x7c000000 {
                if (x & SNAN_MASK32) == SNAN_MASK32 {
                    pfpsf.insert(.invalidOperation)
                }
                return coefficient_x & QUIET_MASK32
            }
            // x is Infinity?
            if (x & 0x78000000) == 0x78000000 {
                if (((y & NAN_MASK32) != NAN_MASK32)) {
                    pfpsf.insert(.invalidOperation)
                    // return NaN
                    return 0x7c000000
                }
            }
            // x is 0
            // return x if y != 0
            if (((y & 0x78000000) < 0x78000000) && coefficient_y != 0) {
                if (y & 0x60000000) == 0x60000000 {
                    exponent_y = Int(y >> 21) & 0xff;
                } else {
                    exponent_y = Int(y >> 23) & 0xff;
                }
                
                if exponent_y < exponent_x {
                    exponent_x = exponent_y
                }
                
                var x = UInt32(exponent_x)
                x <<= 23
                return x | sign_x
            }
            
        }
        if !valid_y {
            // y is Inf. or NaN
            
            // test if y is NaN
            if ((y & 0x7c000000) == 0x7c000000) {
                if (((y & SNAN_MASK32) == SNAN_MASK32)) {
                    pfpsf.insert(.invalidOperation)
                }
                return coefficient_y & QUIET_MASK32
            }
            // y is Infinity?
            if ((y & 0x78000000) == 0x78000000) {
                return very_fast_get_BID32 (sign_x, exponent_x, coefficient_x)
            }
            // y is 0, return NaN
            pfpsf.insert(.invalidOperation)
            return 0x7c000000
        }
        
        
        var diff_expon = exponent_x - exponent_y
        if diff_expon <= 0 {
            diff_expon = -diff_expon
            
            if (diff_expon > 7) {
                // |x|<|y| in this case
                return x
            }
            // set exponent of y to exponent_x, scale coefficient_y
            let T = bid_power10_table_128[diff_expon].w[0];
            let CYL = UInt64(coefficient_y) * T;
            if CYL > (UInt64(coefficient_x) << 1) {
                return x
            }
            
            let CY = UInt32(CYL)
            let Q = coefficient_x / CY
            var R = coefficient_x - Q * CY
            
            let R2 = R + R;
            if R2 > CY || (R2 == CY && (Q & 1) != 0) {
                R = CY - R;
                sign_x ^= 0x80000000
            }
            
            return very_fast_get_BID32 (sign_x, exponent_x, R)
        }
        
        var CX = UInt64(coefficient_x)
        var Q64 = UInt64()
        while diff_expon > 0 {
            // get number of digits in coeff_x
            let tempx = Float(CX)
            let bin_expon = Int((tempx.bitPattern >> 23) & 0xff) - 0x7f
            let digits_x = Int(bid_estimate_decimal_digits[bin_expon])
            // will not use this test, dividend will have 18 or 19 digits
            //if(CX >= bid_power10_table_128[digits_x].w[0])
            //      digits_x++;
            
            var e_scale = Int(18 - digits_x)
            if (diff_expon >= e_scale) {
                diff_expon -= e_scale;
            } else {
                e_scale = diff_expon;
                diff_expon = 0;
            }
            
            // scale dividend to 18 or 19 digits
            CX *= bid_power10_table_128[e_scale].w[0]
            
            // quotient
            Q64 = CX / UInt64(coefficient_y)
            // remainder
            CX -= Q64 * UInt64(coefficient_y)
            
            // check for remainder == 0
            if CX == 0 {
                return very_fast_get_BID32 (sign_x, exponent_y, 0)
            }
        }
        
        coefficient_x = UInt32(CX)
        let R2 = coefficient_x + coefficient_x
        if R2 > coefficient_y || (R2 == coefficient_y && (Q64 & 1) != 0) {
            coefficient_x = coefficient_y - coefficient_x
            sign_x ^= 0x80000000
        }
        
        return very_fast_get_BID32 (sign_x, exponent_y, coefficient_x)
    }

    
    
}

