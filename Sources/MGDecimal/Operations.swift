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
                        // __set_status_flags (pfpsf, BID_INVALID_EXCEPTION);
                        status.insert(.invalidOperation)
                        return NAN_MASK32
                    }
                }
                // check if y is NaN
                if (y & NAN_MASK32) == NAN_MASK32 {
                    let res = coefficient_y & QUIET_MASK32
                    if (y & SNAN_MASK32) == SNAN_MASK32 {
                        status.insert(.invalidOperation)
                        // __set_status_flags (pfpsf, BID_INVALID_EXCEPTION);
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
            sign_a = sign_y;
            exponent_a = exponent_y;
            coefficient_a = coefficient_y;
            sign_b = sign_x;
            exponent_b = exponent_x;
            coefficient_b = coefficient_x;
        } else {
            sign_a = sign_x;
            exponent_a = exponent_x;
            coefficient_a = coefficient_x;
            sign_b = sign_y;
            exponent_b = exponent_y;
            coefficient_b = coefficient_y;
        }
        
        // exponent difference
        var diff_dec_expon = exponent_a - exponent_b
        
        if diff_dec_expon > MAX_FORMAT_DIGITS_32 {
            let tempx = Double(coefficient_a)
            let bin_expon = ((tempx.bitPattern & MASK_BINARY_EXPONENT) >> 52) - 0x3ff
            let scale_ca = bid_estimate_decimal_digits[Int(bin_expon)]
            
            let d2 = 16 - scale_ca
            if (diff_dec_expon > d2) {
                diff_dec_expon = Int(d2)
                exponent_b = exponent_a - diff_dec_expon;
            }
        }
        
        var sign_ab = (Int64(sign_a ^ sign_b))<<32;
        sign_ab = Int64(sign_ab) >> 63;
        let CB = (Int64(coefficient_b) + sign_ab) ^ sign_ab;
        
        let SU = UInt64(coefficient_a) * bid_power10_table_128[diff_dec_expon].w[0]
        var S = Int64(SU) + CB;
        
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
            let bin_expon = ((tempx.bitPattern & MASK_BINARY_EXPONENT) >> 52) - 0x3ff;
            n_digits = Int(bid_estimate_decimal_digits[Int(bin_expon)])
            if P >= bid_power10_table_128[n_digits].w[0] {
                n_digits+=1
            }
        }
        
        if n_digits <= MAX_FORMAT_DIGITS_32 {
            return get_BID32(sign_a, exponent_b, UInt32(P), rmode, &status).x
        }
        
        let extra_digits = n_digits - 7;
        
        var irmode = roundboundIndex(rmode) >> 2
        if (sign_a != 0 && (irmode - 1) < 2) {
            irmode = 3 - irmode;
        }
        
        // add a constant to P, depending on rounding mode
        // 0.5*10^(digits_p - 16) for round-to-nearest
        P += bid_round_const_table[irmode][extra_digits]
        var Tmp = UInt128()
        __mul_64x64_to_128(&Tmp, P, bid_reciprocals10_64[extra_digits])
        
        // now get P/10^extra_digits: shift Q_high right by M[extra_digits]-64
        let amount = bid_short_recip_scale[extra_digits];
        var Q = Tmp.w[1] >> amount;
        
        // remainder
        let R = P - Q * bid_power10_table_128[extra_digits].w[0];
        if R==bid_round_const_table[irmode][extra_digits] {
            status = []
        } else {
            status.insert(.inexact)
        }
        
        // __set_status_flags (pfpsf, status);
        if rmode == BID_ROUNDING_TO_NEAREST {
            if R==0 {
                Q &= 0xffff_fffe
            }
        }
        
        return get_BID32(sign_a, exponent_b+extra_digits, UInt32(Q), rmode, &status).x
    }
    
    static let bid_mult_factor : [UInt32] = [
      1, 10, 100, 1000, 10000, 100000, 1000000
    ]
    
    static func equal (_ x: UInt32, _ y: UInt32, _ status: inout Status) -> Bool {
        // NaN (CASE1)
        // if either number is NAN, the comparison is unordered,
        // rather than equal : return 0
        if (((x & MASK_NAN32) == MASK_NAN32) || ((y & MASK_NAN32) == MASK_NAN32)) {
            if ((x & MASK_SNAN32) == Decimal32.MASK_SNAN32 || (y & MASK_SNAN32) == MASK_SNAN32) {
                status.insert(.invalidOperation)
                // *pfpsf |= BID_INVALID_EXCEPTION;    // set exception if sNaN
            }
            return false
        }
        // SIMPLE (CASE2)
        // if all the bits are the same, these numbers are equivalent.
        if x == y {
            return true
        }
        // INFINITY (CASE3)
        if (((x & MASK_INF32) == MASK_INF32) && ((y & MASK_INF32) == MASK_INF32)) {
            return (((x ^ y) & Decimal32.MASK_SIGN32) != Decimal32.MASK_SIGN32)
        }
        // ONE INFINITY (CASE3')
        if (((x & MASK_INF32) == MASK_INF32) || ((y & MASK_INF32) == MASK_INF32)) {
            return false
        }
        // if steering bits are 11 (condition will be 0), then exponent is G[0:w+1] =>
        var exp_x, sig_x:UInt32
        var non_canon_x:Bool
        if ((x & MASK_STEERING_BITS32) == MASK_STEERING_BITS32) {
            exp_x = (x & MASK_BINARY_EXPONENT2_32) >> 21;
            sig_x = (x & MASK_BINARY_SIG2_32) | MASK_BINARY_OR2_32;
            if (sig_x > 9999999) {
                non_canon_x = true
            } else {
                non_canon_x = false
            }
        } else {
            exp_x = (x & MASK_BINARY_EXPONENT1_32) >> 23;
            sig_x = (x & MASK_BINARY_SIG1_32);
            non_canon_x = false
        }
        // if steering bits are 11 (condition will be 0), then exponent is G[0:w+1] =>
        var exp_y, sig_y:UInt32
        var non_canon_y:Bool
        if ((y & MASK_STEERING_BITS32) == MASK_STEERING_BITS32) {
            exp_y = (y & MASK_BINARY_EXPONENT2_32) >> 21;
            sig_y = (y & MASK_BINARY_SIG2_32) | MASK_BINARY_OR2_32;
            if (sig_y > 9999999) {
                non_canon_y = true
            } else {
                non_canon_y = false
            }
        } else {
            exp_y = (y & Decimal32.MASK_BINARY_EXPONENT1_32) >> 23;
            sig_y = (y & Decimal32.MASK_BINARY_SIG1_32);
            non_canon_y = false
        }
        // ZERO (CASE4)
        // some properties:
        // (+ZERO==-ZERO) => therefore ignore the sign
        //    (ZERO x 10^A == ZERO x 10^B) for any valid A, B =>
        //    therefore ignore the exponent field
        //    (Any non-canonical # is considered 0)
        var x_is_zero = false, y_is_zero = false
        if (non_canon_x || sig_x == 0) {
            x_is_zero = true
        }
        if (non_canon_y || sig_y == 0) {
            y_is_zero = true
        }
        if (x_is_zero && y_is_zero) {
            return true
        } else if ((x_is_zero && !y_is_zero) || (!x_is_zero && y_is_zero)) {
            return false
        }
        // OPPOSITE SIGN (CASE5)
        // now, if the sign bits differ => not equal : return 0
        if ((x ^ y) & MASK_SIGN32) != 0 {
            return false
        }
        // REDUNDANT REPRESENTATIONS (CASE6)
        if (exp_x > exp_y) {    // to simplify the loop below,
            swap(&exp_x, &exp_y)
            swap(&sig_x, &sig_y)
//            SWAP (exp_x, exp_y, exp_t);    // put the larger exp in y,
//            SWAP (sig_x, sig_y, sig_t);    // and the smaller exp in x
        }
        if exp_y - exp_x > 6 {
            return false    // difference cannot be greater than 10^6
        }
        for _ in 0..<(exp_y - exp_x) {
            // recalculate y's significand upwards
            sig_y = sig_y * 10;
            if (sig_y > 9999999) {
                return false
            }
        }
        return (sig_y == sig_x)
    }

    
    static func lessThan (_ x: UInt32, _ y: UInt32, _ status: inout Status) -> Bool {
        // NaN (CASE1)
        // if either number is NAN, the comparison is unordered : return 0
        if (((x & NAN_MASK32) == NAN_MASK32) || ((y & NAN_MASK32) == NAN_MASK32)) {
            // *pfpsf |= BID_INVALID_EXCEPTION;    // set invalid exception if NaN
            status.insert(.invalidOperation)
            return false
        }
        // SIMPLE (CASE2)
        // if all the bits are the same, these numbers are equal.
        if x == y {
            return false
        }
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
        var exp_x, exp_y, sig_x, sig_y: UInt32
        var non_canon_x, non_canon_y: Bool
        if (x & SPECIAL_ENCODING_MASK32) == SPECIAL_ENCODING_MASK32 {
            exp_x = (x & MASK_BINARY_EXPONENT2_32) >> 21;
            sig_x = (x & SMALL_COEFF_MASK32) | LARGE_COEFF_HIGH_BIT32
            if (sig_x > 9999999) {
                non_canon_x = true
            } else {
                non_canon_x = false
            }
        } else {
            exp_x = (x & MASK_BINARY_EXPONENT1_32) >> 23;
            sig_x = (x & LARGE_COEFF_MASK32);
            non_canon_x = false
        }
        
        // if steering bits are 11 (condition will be 0), then exponent is G[0:w+1] =>
        if (y & SPECIAL_ENCODING_MASK32) == SPECIAL_ENCODING_MASK32 {
            exp_y = (y & MASK_BINARY_EXPONENT2_32) >> 21;
            sig_y = (y & SMALL_COEFF_MASK32) | LARGE_COEFF_HIGH_BIT32
            if (sig_y > 9999999) {
                non_canon_y = true
            } else {
                non_canon_y = false
            }
        } else {
            exp_y = (y & MASK_BINARY_EXPONENT1_32) >> 23;
            sig_y = (y & LARGE_COEFF_MASK32);
            non_canon_y = false
        }
        
        // ZERO (CASE4)
        // some properties:
        // (+ZERO==-ZERO) => therefore ignore the sign, and neither number is greater
        //    (ZERO x 10^A == ZERO x 10^B) for any valid A, B =>
        //      therefore ignore the exponent field
        //    (Any non-canonical # is considered 0)
        var x_is_zero = false, y_is_zero = false
        if (non_canon_x || sig_x == 0) {
            x_is_zero = true
        }
        if (non_canon_y || sig_y == 0) {
            y_is_zero = true
        }
        // if both numbers are zero, they are equal
        if (x_is_zero && y_is_zero) {
            return false
        }
        // if x is zero, it is lessthan if Y is positive
        else if (x_is_zero) {
            return ((y & SIGN_MASK32) != SIGN_MASK32)
        }
        // if y is zero, X is less if it is negative
        else if (y_is_zero) {
            return ((x & SIGN_MASK32) == SIGN_MASK32);
        }
        // OPPOSITE SIGN (CASE5)
        // now, if the sign bits differ, x is less than if y is positive
        if (((x ^ y) & SIGN_MASK32) == SIGN_MASK32) {
            return ((y & SIGN_MASK32) != SIGN_MASK32);
        }
        // REDUNDANT REPRESENTATIONS (CASE6)
        // if both components are either bigger or smaller
        if (sig_x > sig_y && exp_x >= exp_y) {
            return ((x & SIGN_MASK32) == SIGN_MASK32);
        }
        if (sig_x < sig_y && exp_x <= exp_y) {
            return ((x & SIGN_MASK32) != SIGN_MASK32);
        }
        // if exp_x is 6 greater than exp_y, no need for compensation
        if (exp_x - exp_y > 6) {
            return ((x & SIGN_MASK32) == SIGN_MASK32);
        }
        // difference cannot be greater than 10^6
        
        // if exp_x is 6 less than exp_y, no need for compensation
        if (exp_y - exp_x > 6) {
            return ((x & SIGN_MASK32) != SIGN_MASK32);
        }
        // if |exp_x - exp_y| < 6, it comes down to the compensated significand
        var sig_n_prime: UInt64
        if (exp_x > exp_y) {    // to simplify the loop below,
            
            // otherwise adjust the x significand upwards
            sig_n_prime = UInt64(sig_x) * UInt64(bid_mult_factor[Int(exp_x - exp_y)])
            
            // return 0 if values are equal
            if (sig_n_prime == sig_y) {
                return false
            }
            // if postitive, return whichever significand abs is smaller
            //     (converse if negative)
            return ((sig_n_prime < sig_y) ? 1 : 0) ^ (((x & SIGN_MASK32) == SIGN_MASK32) ? 1 : 0) != 0
        }
        // adjust the y significand upwards
        sig_n_prime = UInt64(sig_y) * UInt64(bid_mult_factor[Int(exp_y - exp_x)])
        
        // return 0 if values are equal
        if (sig_n_prime == sig_x) {
            return false
        }
        // if positive, return whichever significand abs is smaller
        //     (converse if negative)
        return ((sig_n_prime < sig_y) ? 1 : 0) ^ (((x & SIGN_MASK32) == SIGN_MASK32) ? 1 : 0) != 0
    }
    
    static func mul (_ x:UInt32, _ y:UInt32, _ rmode:Rounding, _ status:inout Status) -> UInt32  {
        var sign_x = UInt32(0), sign_y = UInt32(0), exponent_x = 0, exponent_y = 0
        var coefficient_x = UInt32(0), coefficient_y = UInt32(0)
        let valid_x = unpack_BID32 (&sign_x, &exponent_x, &coefficient_x, x);
        let valid_y = unpack_BID32 (&sign_y, &exponent_y, &coefficient_y, y);
        
        // unpack arguments, check for NaN or Infinity
        if (!valid_x) {
            
            if (y & SNAN_MASK32) == SNAN_MASK32 {   // y is sNaN
                status.insert(.invalidOperation)
               //  __set_status_flags (pfpsf, BID_INVALID_EXCEPTION);
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
                if ((y & INFINITY_MASK32) != INFINITY_MASK32 && (coefficient_y == 0)) {
                    status.insert(.invalidOperation)
                    // y==0 , return NaN
                    return (NAN_MASK32);
                }
                // check if y is NaN
                if ((y & NAN_MASK32) == NAN_MASK32) {
                    // y==NaN , return NaN
                   return (coefficient_y & QUIET_MASK32);
                }
                // otherwise return +/-Inf
                return (((x ^ y) & SIGN_MASK32) | INFINITY_MASK32);
            }
            // x is 0
            if (y & INFINITY_MASK32) != INFINITY_MASK32 {
                if (y & SPECIAL_ENCODING_MASK32) == SPECIAL_ENCODING_MASK32 {
                    exponent_y = Int(UInt32(y >> 21)) & 0xff;
                } else {
                    exponent_y = Int(UInt32(y >> 23)) & 0xff;
                }
                sign_y = y & SIGN_MASK32
                
                exponent_x += exponent_y - DECIMAL_EXPONENT_BIAS_32;
                if (exponent_x > DECIMAL_MAX_EXPON_32) {
                    exponent_x = DECIMAL_MAX_EXPON_32;
                } else if (exponent_x < 0) {
                    exponent_x = 0;
                }
               return UInt32(UInt64(sign_x ^ sign_y) | (UInt64(exponent_x) << 23))
            }
        }
        if !valid_y {
            // y is Inf. or NaN
            
            // test if y is NaN
            if ((y & NAN_MASK32) == NAN_MASK32) {
                if ((y & SNAN_MASK32) == SNAN_MASK32) {    // sNaN
                    status.insert(.invalidOperation)
                }
                return (coefficient_y & QUIET_MASK32);
            }
            // y is Infinity?
            if ((y & INFINITY_MASK32) == INFINITY_MASK32) {
                // check if x is 0
                if coefficient_x == 0 {
                    status.insert(.invalidOperation)
                    // x==0, return NaN
                    return (NAN_MASK32);
                }
                // otherwise return +/-Inf
                return (((x ^ y) & 0x80000000) | INFINITY_MASK32);
            }
            // y is 0
            exponent_x += exponent_y - DECIMAL_EXPONENT_BIAS_32;
            if (exponent_x > DECIMAL_MAX_EXPON_32) {
                exponent_x = DECIMAL_MAX_EXPON_32;
            } else if (exponent_x < 0) {
                exponent_x = 0;
            }
            return UInt32(UInt64(sign_x ^ sign_y) | (UInt64(exponent_x) << 23))
        }
        
        var P = UInt64(coefficient_x) * UInt64(coefficient_y)
        
        //--- get number of bits in C64 ---
        // version 2 (original)
        let tempx = Double(P)
        let bin_expon_p = ((tempx.bitPattern & MASK_BINARY_EXPONENT) >> 52)-0x3ff;
        var n_digits = bid_estimate_decimal_digits[Int(bin_expon_p)]
        if P >= bid_power10_table_128[Int(n_digits)].w[0] {
            n_digits+=1
        }
        
        exponent_x += exponent_y - DECIMAL_EXPONENT_BIAS_32
        
        let extra_digits = Int((n_digits<=7) ? 0 : (n_digits - 7))
        
        exponent_x += extra_digits
        
        if extra_digits == 0 {
            return get_BID32 (sign_x ^ sign_y, exponent_x, UInt32(P), rmode, &status).x
        }
        
        var rmode1 = roundboundIndex(rmode) >> 2
        if (sign_x ^ sign_y) != 0 && UInt32(rmode1 - 1) < 2 {
            rmode1 = 3 - rmode1
        }
        
        if exponent_x<0 { rmode1=3 }  // RZ
        
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
                Q &= 0xfffffffe
            }
        }
        
        if (exponent_x == -1) && (Q == 9999999) && (rmode != BID_ROUNDING_TO_ZERO) {
            rmode1 = roundboundIndex(rmode) >> 2
            if ((sign_x^sign_y != 0) && UInt32(rmode1 - 1) < 2) {
                rmode1 = 3 - rmode1
            }
            
            if (((R != 0) && (rmode == BID_ROUNDING_UP)) || ((!(rmode1&3 != 0)) && (R+R>=bid_power10_table_128[extra_digits].w[0]))) {
                return very_fast_get_BID32(sign_x^sign_y, 0, 1000000)
            }
        }
        
        return get_BID32_UF (sign_x^sign_y, Int(exponent_x), Q, Int(R), rmode, &status).x
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
        let valid_x = unpack_BID32 (&sign_x, &exponent_x, &coefficient_x, x);
        let valid_y = unpack_BID32 (&sign_y, &exponent_y, &coefficient_y, y);
        
        // unpack arguments, check for NaN or Infinity
        if !valid_x {
            // x is Inf. or NaN
            if ((y & SNAN_MASK32) == SNAN_MASK32) {   // y is sNaN
                status.insert(.invalidOperation)
                //__set_status_flags (pfpsf, BID_INVALID_EXCEPTION);
            }
            
            // test if x is NaN
            if ((x & NAN_MASK32) == NAN_MASK32) {
                if ((x & SNAN_MASK32) == SNAN_MASK32) {    // sNaN
                    status.insert(.invalidOperation)
                }
                return (coefficient_x & QUIET_MASK32);
            }
            // x is Infinity?
            if ((x & INFINITY_MASK32) == INFINITY_MASK32) {
                // check if y is Inf or NaN
                if ((y & INFINITY_MASK32) == INFINITY_MASK32) {
                    // y==Inf, return NaN
                    if ((y & NAN_MASK32) == INFINITY_MASK32) {    // Inf/Inf
                        status.insert(.invalidOperation)
                        return (NAN_MASK32);
                    }
                } else {
                    // otherwise return +/-Inf
                    return (((x ^ y) & SIGN_MASK32) | INFINITY_MASK32);
                }
            }
            // x==0
            if ((y & INFINITY_MASK32) != INFINITY_MASK32) && coefficient_y == 0 {
                // y==0 , return NaN
                status.insert(.invalidOperation)
                return (NAN_MASK32);
            }
            if (((y & INFINITY_MASK32) != INFINITY_MASK32)) {
                if ((y & SPECIAL_ENCODING_MASK32) == SPECIAL_ENCODING_MASK32) {
                    exponent_y = Int((UInt32(y >> 21)) & 0xff)
                } else {
                    exponent_y = Int((UInt32(y >> 23)) & 0xff)
                    sign_y = y & SIGN_MASK32
                }
                
                exponent_x = exponent_x - exponent_y + DECIMAL_EXPONENT_BIAS_32;
                if (exponent_x > DECIMAL_MAX_EXPON_32) {
                    exponent_x = DECIMAL_MAX_EXPON_32;
                } else if (exponent_x < 0) {
                    exponent_x = 0;
                }
                return UInt32((sign_x ^ sign_y) | (UInt32(exponent_x) << 23))
            }
            
        }
        if !valid_y {
            // y is Inf. or NaN
            
            // test if y is NaN
            if ((y & NAN_MASK32) == NAN_MASK32) {
                if ((y & SNAN_MASK32) == SNAN_MASK32) {   // sNaN
                    status.insert(.invalidOperation)
                }
                return (coefficient_y & QUIET_MASK32)
            }
            // y is Infinity?
            if (y & INFINITY_MASK32) == INFINITY_MASK32 {
                // return +/-0
                return (x ^ y) & SIGN_MASK32
            }
            // y is 0
            status.insert(.divisionByZero)
            //__set_status_flags (pfpsf, BID_ZERO_DIVIDE_EXCEPTION);
            return ((sign_x ^ sign_y) | INFINITY_MASK32);
        }
        var diff_expon = exponent_x - exponent_y + DECIMAL_EXPONENT_BIAS_32;
        
        var A, B, Q, R: UInt32
        var CA: UInt64
        var ed1, ed2: Int
        if (coefficient_x < coefficient_y) {
            
            // get number of decimal digits for c_x, c_y
            
            //--- get number of bits in the coefficients of x and y ---
            let tempx = Float(coefficient_x)
            let tempy = Float(coefficient_y)
            let bin_index = Int((tempy.bitPattern - tempx.bitPattern) >> 23)
            
            A = coefficient_x * UInt32(bid_power10_index_binexp[bin_index])
            B = coefficient_y;
            
            // compare A, B
            let DU = (A - B) >> 31;
            ed1 = 6 + Int(DU)
            ed2 = Int(bid_estimate_decimal_digits[bin_index]) + ed1
            let T = bid_power10_table_128[ed1].w[0]
            CA = UInt64(A) * T
            
            Q = 0
            diff_expon = diff_expon - ed2;
            
        } else {
            // get c_x/c_y
            Q = coefficient_x/coefficient_y;
            
            R = coefficient_x - coefficient_y * Q;
            
            // will use to get number of dec. digits of Q
            let tempq = Float(Q)
            let bin_expon_cx = Int(tempq.bitPattern >> 23) - 0x7f;
            
            // exact result ?
            if R == 0 {
                return get_BID32 (sign_x ^ sign_y, diff_expon, Q, rmode, &status).x
            }
            // get decimal digits of Q
            var DU = UInt32(bid_power10_index_binexp[bin_expon_cx]) - Q - 1;
            DU >>= 31;
            
            ed2 = 7 - Int(bid_estimate_decimal_digits[bin_expon_cx]) - Int(DU)
            
            let T = bid_power10_table_128[ed2].w[0];
            CA = UInt64(R) * T
            B = coefficient_y;
            
            Q *= UInt32(bid_power10_table_128[ed2].w[0])
            diff_expon -= ed2
        }
        
        let Q2 = UInt32(CA / UInt64(B))
        let B2 = B + B;
        let B4 = B2 + B2;
        R = UInt32(CA - UInt64(Q2) * UInt64(B))
        Q += Q2
        
        if R != 0 {
            // set status flags
            status.insert(.inexact)
            //__set_status_flags (pfpsf, BID_INEXACT_EXCEPTION);
            //printf("ZZZ R=%x, %x %x\n",R, (BID_UINT32)pfpsf, *pfpsf);
        } else {
            // eliminate trailing zeros
            
            // check whether CX, CY are short
            if ((coefficient_x <= 1024) && (coefficient_y <= 1024)) {
                let i = Int(coefficient_y) - 1;
                let j = Int(coefficient_x) - 1;
                // difference in powers of 2 bid_factors for Y and X
                var nzeros = ed2 - Int(bid_factors[i][0] + bid_factors[j][0])
                // difference in powers of 5 bid_factors
                let d5 = ed2 - Int(bid_factors[i][1] + bid_factors[j][1])
                if (d5 < nzeros) {
                    nzeros = d5;
                }
                
                if nzeros != 0 {
                    var CT = UInt64(Q) * bid_bid_reciprocals10_32[nzeros]
                    CT >>= 32
                    
                    // now get P/10^extra_digits: shift C64 right by M[extra_digits]-128
                    let amount = bid_bid_bid_recip_scale32[nzeros];
                    Q = UInt32(CT >> amount)
                    
                    diff_expon += nzeros;
                }
            } else {
                var nzeros = 0
                
                // decompose digit
                let PD = UInt64(Q) * 0x068DB8BB
                var digit_h = UInt32(PD >> 40)
                let digit_low = Q - digit_h * 10000;
                
                if digit_low == 0 {
                    nzeros += 4
                } else {
                    digit_h = digit_low;
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
                diff_expon += nzeros;
                
            }
            if (diff_expon >= 0) {
                return get_BID32 (sign_x ^ sign_y, diff_expon, Q, rmode, &status).x
            }
        }
        
        if (diff_expon >= 0) {
            var rmode1 = roundboundIndex(rmode) >> 2
            if (sign_x ^ sign_y) != 0 && UInt32(rmode1 - 1) < 2 {
                rmode1 = 3 - rmode1
            }
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
                    Q += D;
                case 1, 3:
                    break
                default:    // rounding up
                    Q+=1
            }
            return get_BID32 (sign_x ^ sign_y, diff_expon, Q, rmode, &status).x
        } else {
            // UF occurs
            if diff_expon + 7 < 0 {
                // set status flags
                status.insert(.inexact)
            }
            //rmode = rnd_mode;
            return get_BID32_UF (sign_x ^ sign_y, diff_expon, UInt64(Q), Int(R), rmode, &status).x
        }
    }

    
    static func sqrt(_ x: UInt32, _ rmode:Rounding, _ status:inout Status) -> UInt32 {
        // unpack arguments, check for NaN or Infinity
        var sign_x = UInt32(0), exponent_x = 0, coefficient_x = UInt32(0)
        if !unpack_BID32 (&sign_x, &exponent_x, &coefficient_x, x) {
            // x is Inf. or NaN or 0
            if ((x & INFINITY_MASK32) == INFINITY_MASK32) {
                var res = coefficient_x
                if ((coefficient_x & SSNAN_MASK32) == SINFINITY_MASK32) {   // -Infinity
                    res = NAN_MASK32
                    status.insert(.invalidOperation)
                    //__set_status_flags (pfpsf, BID_INVALID_EXCEPTION);
                }
                if ((x & SNAN_MASK32) == SNAN_MASK32) {   // sNaN
                    status.insert(.invalidOperation)
                }
                return (res & QUIET_MASK32);
            }
            // x is 0
            exponent_x = (exponent_x + DECIMAL_EXPONENT_BIAS_32) >> 1;
            return sign_x | (UInt32(exponent_x) << 23);
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
        if (coefficient_x >= bid_power10_index_binexp[bin_expon_cx]) {
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
            return very_fast_get_BID32 (0, (exponent_x + DECIMAL_EXPONENT_BIAS_32) >> 1, QE);
        }
        // if exponent is odd, scale coefficient by 10
        var scale = Int(13 - digits_x)
        var exponent_q = exponent_x + DECIMAL_EXPONENT_BIAS_32 - scale
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


}

