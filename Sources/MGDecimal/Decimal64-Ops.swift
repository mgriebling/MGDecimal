//
//  File.swift
//  
//
//  Created by Mike Griebling on 2022-03-19.
//

import Foundation

extension Decimal64 {
    
    /*****************************************************************************
     *  BID64_round_integral_exact
     ****************************************************************************/
    
    static func bid64_round_integral_exact(_ x: UInt64, _ rmode: Rounding, _ pfpsf: inout Status) -> UInt64 {
        var res = UInt64(0xbaddbaddbaddbadd)
        var x = x
        let x_sign = x & MASK_SIGN;    // 0 for positive, MASK_SIGN for negative
        var exp = 0
        
        // check for NaNs and infinities
        if (x & MASK_NAN) == MASK_NAN {    // check for NaN
            if (x & 0x0003ffffffffffff) > 999999999999999 {
                x = x & 0xfe00000000000000    // clear G6-G12 and the payload bits
            } else {
                x = x & 0xfe03ffffffffffff    // clear G6-G12
            }
            if (x & MASK_SNAN) == MASK_SNAN {    // SNaN
                // set invalid flag
                pfpsf.insert(.invalidOperation)
                // return quiet (SNaN)
                res = x & QUIET_MASK64
            } else {    // QNaN
                res = x
            }
            return res
        } else if (x & MASK_INF) == MASK_INF {    // check for Infinity
            return x_sign | MASK_INF
        }
        // unpack x
        var C1: UInt64
        if ((x & MASK_STEERING_BITS) == MASK_STEERING_BITS) {
            // if the steering bits are 11 (condition will be 0), then
            // the exponent is G[0:w+1]
            exp = Int((x & MASK_BINARY_EXPONENT2) >> EXPONENT_SHIFT_LARGE64) - EXPONENT_BIAS
            C1 = (x & MASK_BINARY_SIG2) | MASK_BINARY_OR2
            if C1 > MAX_NUMBER {    // non-canonical
                C1 = 0;
            }
        } else {    // if ((x & MASK_STEERING_BITS) != MASK_STEERING_BITS)
            exp = Int((x & MASK_BINARY_EXPONENT1) >> EXPONENT_SHIFT_SMALL64) - EXPONENT_BIAS
            C1 = (x & MASK_BINARY_SIG1)
        }
        
        // if x is 0 or non-canonical return 0 preserving the sign bit and
        // the preferred exponent of MAX(Q(x), 0)
        if C1 == 0 {
            if exp < 0 {
                exp = 0
            }
            return x_sign | ((UInt64(exp) + UInt64(EXPONENT_BIAS)) << EXPONENT_SHIFT_SMALL64)
        }
        // x is a finite non-zero number (not 0, non-canonical, or special)
        let zero = UInt64(0x31c0_0000_0000_0000)
        switch rmode {
            case BID_ROUNDING_TO_NEAREST, BID_ROUNDING_TIES_AWAY:
                // return 0 if (exp <= -(p+1))
                if exp <= -17 {
                    res = x_sign | zero
                    pfpsf.insert(.inexact)
                    return res
                }
            case BID_ROUNDING_DOWN:
                // return 0 if (exp <= -p)
                if exp <= -16 {
                    if x_sign != 0 {
                        res = (zero+1) | SIGN_MASK64  // 0xb1c0000000000001
                    } else {
                        res = zero
                    }
                    pfpsf.insert(.inexact)
                    return res
                }
            case BID_ROUNDING_UP:
                // return 0 if (exp <= -p)
                if exp <= -16 {
                    if x_sign != 0 {
                        res = zero | SIGN_MASK64  // 0xb1c0000000000000
                    } else {
                        res = zero+1
                    }
                    pfpsf.insert(.inexact)
                    return res
                }
            case BID_ROUNDING_TO_ZERO:
                // return 0 if (exp <= -p)
                if exp <= -16 {
                    res = x_sign | zero
                    pfpsf.insert(.inexact)
                    return res
                }
            default: break
        }    // end switch ()
        
        // q = nr. of decimal digits in x (1 <= q <= 54)
        //  determine first the nr. of bits in x
        let q = digitsIn(C1)
//        if C1 >= MASK_BINARY_OR2 {    // x >= 2^EXPONENT_SHIFT_SMALL64
//            q = 16
//        } else {    // if x < 2^EXPONENT_SHIFT_SMALL64
//            let tmp1 = Double(C1)    // exact conversion
//            let x_nr_bits = 1 + Int((((tmp1.bitPattern >> 52)) & 0x7ff) - UInt64(BINARY_EXPONENT_BIAS))
//            q = Int(bid_nr_digits[x_nr_bits - 1].digits)
//            if q == 0 {
//                q = Int(bid_nr_digits[x_nr_bits - 1].digits1)
//                if (C1 >= bid_nr_digits[x_nr_bits - 1].threshold_lo) {
//                    q+=1
//                }
//            }
//        }
        
        if exp >= 0 {    // -exp <= 0
            // the argument is an integer already
            return x
        }
        
        var ind: Int
        var P128 = UInt128(), fstar = UInt128()
        switch rmode {
            case BID_ROUNDING_TO_NEAREST:
                if ((q + exp) >= 0) {    // exp < 0 and 1 <= -exp <= q
                    // need to shift right -exp digits from the coefficient; exp will be 0
                    ind = -exp;    // 1 <= ind <= 16; ind is a synonym for 'x'
                    // chop off ind digits from the lower part of C1
                    // C1 = C1 + 1/2 * 10^x where the result C1 fits in 64 bits
                    // FOR ROUND_TO_NEAREST, WE ADD 1/2 ULP(y) then truncate
                    C1 = C1 + bid_midpoint64[ind - 1]
                    // calculate C* and f*
                    // C* is actually floor(C*) in this case
                    // C* and f* need shifting and masking, as shown by
                    // bid_shiftright128[] and bid_maskhigh128[]
                    // 1 <= x <= 16
                    // kx = 10^(-x) = bid_ten2mk64[ind - 1]
                    // C* = (C1 + 1/2 * 10^x) * 10^(-x)
                    // the approximation of 10^(-x) was rounded up to 64 bits
                    __mul_64x64_to_128(&P128, C1, bid_ten2mk64[ind - 1])
                    
                    // if (0 < f* < 10^(-x)) then the result is a midpoint
                    //   if floor(C*) is even then C* = floor(C*) - logical right
                    //       shift; C* has p decimal digits, correct by Prop. 1)
                    //   else if floor(C*) is odd C* = floor(C*)-1 (logical right
                    //       shift; C* has p decimal digits, correct by Pr. 1)
                    // else
                    //   C* = floor(C*) (logical right shift; C has p decimal digits,
                    //       correct by Property 1)
                    // n = C* * 10^(e+x)
                    
                    if (ind - 1 <= 2) {    // 0 <= ind - 1 <= 2 => shift = 0
                        res = P128.hi
                        fstar.hi = 0
                        fstar.lo = P128.lo
                    } else if (ind - 1 <= 21) {    // 3 <= ind - 1 <= 21 => 3 <= shift <= 63
                        let shift = bid_shiftright128[ind - 1]    // 3 <= shift <= 63
                        res = (P128.hi >> shift)
                        fstar.hi = P128.hi & bid_maskhigh128[ind - 1]
                        fstar.lo = P128.lo
                    }
                    // if (0 < f* < 10^(-x)) then the result is a midpoint
                    // since round_to_even, subtract 1 if current result is odd
                    if (res & 0x1 != 0) && (fstar.hi == 0) && (fstar.lo < bid_ten2mk64[ind - 1]) {
                        res -= 1
                    }
                    // determine inexactness of the rounding of C*
                    // if (0 < f* - 1/2 < 10^(-x)) then
                    //   the result is exact
                    // else // if (f* - 1/2 > T*) then
                    //   the result is inexact
                    if (ind - 1 <= 2) {
                        if (fstar.lo > MASK_SIGN) {
                            // f* > 1/2 and the result may be exact
                            // fstar.lo - MASK_SIGN is f* - 1/2
                            if ((fstar.lo - MASK_SIGN) > bid_ten2mk64[ind - 1]) {
                                // set the inexact flag
                                pfpsf.insert(.inexact)
                            }    // else the result is exact
                        } else {    // the result is inexact; f2* <= 1/2
                            // set the inexact flag
                            pfpsf.insert(.inexact)
                        }
                    } else {    // if 3 <= ind - 1 <= 21
                        if fstar.hi > bid_onehalf128[ind - 1] || (fstar.hi == bid_onehalf128[ind - 1] && fstar.lo != 0) {
                            // f2* > 1/2 and the result may be exact
                            // Calculate f2* - 1/2
                            if fstar.hi > bid_onehalf128[ind - 1] || fstar.lo > bid_ten2mk64[ind - 1] {
                                // set the inexact flag
                                pfpsf.insert(.inexact)
                            }    // else the result is exact
                        } else {    // the result is inexact; f2* <= 1/2
                            // set the inexact flag
                            pfpsf.insert(.inexact)
                        }
                    }
                    // set exponent to zero as it was negative before.
                    res = x_sign | zero | res;
                    return res
                } else {    // if exp < 0 and q + exp < 0
                    // the result is +0 or -0
                    res = x_sign | zero;
                    pfpsf.insert(.inexact)
                    return res
                }
            case BID_ROUNDING_TIES_AWAY:
                if (q + exp) >= 0 {    // exp < 0 and 1 <= -exp <= q
                    // need to shift right -exp digits from the coefficient; exp will be 0
                    ind = -exp   // 1 <= ind <= 16; ind is a synonym for 'x'
                    // chop off ind digits from the lower part of C1
                    // C1 = C1 + 1/2 * 10^x where the result C1 fits in 64 bits
                    // FOR ROUND_TO_NEAREST, WE ADD 1/2 ULP(y) then truncate
                    C1 = C1 + bid_midpoint64[ind - 1]
                    // calculate C* and f*
                    // C* is actually floor(C*) in this case
                    // C* and f* need shifting and masking, as shown by
                    // bid_shiftright128[] and bid_maskhigh128[]
                    // 1 <= x <= 16
                    // kx = 10^(-x) = bid_ten2mk64[ind - 1]
                    // C* = (C1 + 1/2 * 10^x) * 10^(-x)
                    // the approximation of 10^(-x) was rounded up to 64 bits
                    __mul_64x64_to_128(&P128, C1, bid_ten2mk64[ind - 1])
                    
                    // if (0 < f* < 10^(-x)) then the result is a midpoint
                    //   C* = floor(C*) - logical right shift; C* has p decimal digits,
                    //       correct by Prop. 1)
                    // else
                    //   C* = floor(C*) (logical right shift; C has p decimal digits,
                    //       correct by Property 1)
                    // n = C* * 10^(e+x)
                    
                    if ind - 1 <= 2 {    // 0 <= ind - 1 <= 2 => shift = 0
                        res = P128.hi
                        fstar.hi = 0
                        fstar.lo = P128.lo
                    } else if ind - 1 <= 21 {    // 3 <= ind - 1 <= 21 => 3 <= shift <= 63
                        let shift = bid_shiftright128[ind - 1]    // 3 <= shift <= 63
                        res = (P128.hi >> shift)
                        fstar.hi = P128.hi & bid_maskhigh128[ind - 1]
                        fstar.lo = P128.lo
                    }
                    // midpoints are already rounded correctly
                    // determine inexactness of the rounding of C*
                    // if (0 < f* - 1/2 < 10^(-x)) then
                    //   the result is exact
                    // else // if (f* - 1/2 > T*) then
                    //   the result is inexact
                    if ind - 1 <= 2 {
                        if fstar.lo > MASK_SIGN {
                            // f* > 1/2 and the result may be exact
                            // fstar.lo - MASK_SIGN is f* - 1/2
                            if (fstar.lo - MASK_SIGN) > bid_ten2mk64[ind - 1] {
                                // set the inexact flag
                                pfpsf.insert(.inexact)
                            }    // else the result is exact
                        } else {    // the result is inexact; f2* <= 1/2
                            // set the inexact flag
                            pfpsf.insert(.inexact)
                        }
                    } else {    // if 3 <= ind - 1 <= 21
                        if fstar.hi > bid_onehalf128[ind - 1] || (fstar.hi == bid_onehalf128[ind - 1] && fstar.lo != 0) {
                            // f2* > 1/2 and the result may be exact
                            // Calculate f2* - 1/2
                            if fstar.hi > bid_onehalf128[ind - 1] || fstar.lo > bid_ten2mk64[ind - 1] {
                                // set the inexact flag
                                pfpsf.insert(.inexact)
                            }    // else the result is exact
                        } else {    // the result is inexact; f2* <= 1/2
                            // set the inexact flag
                            pfpsf.insert(.inexact)
                        }
                    }
                    // set exponent to zero as it was negative before.
                    return x_sign | zero | res
                } else {    // if exp < 0 and q + exp < 0
                    // the result is +0 or -0
                    res = x_sign | zero
                    pfpsf.insert(.inexact)
                    return res
                }
            case BID_ROUNDING_DOWN:
                if (q + exp) > 0 {    // exp < 0 and 1 <= -exp < q
                    // need to shift right -exp digits from the coefficient; exp will be 0
                    ind = -exp    // 1 <= ind <= 16; ind is a synonym for 'x'
                    // chop off ind digits from the lower part of C1
                    // C1 fits in 64 bits
                    // calculate C* and f*
                    // C* is actually floor(C*) in this case
                    // C* and f* need shifting and masking, as shown by
                    // bid_shiftright128[] and bid_maskhigh128[]
                    // 1 <= x <= 16
                    // kx = 10^(-x) = bid_ten2mk64[ind - 1]
                    // C* = C1 * 10^(-x)
                    // the approximation of 10^(-x) was rounded up to 64 bits
                    __mul_64x64_to_128(&P128, C1, bid_ten2mk64[ind - 1])
                    
                    // C* = floor(C*) (logical right shift; C has p decimal digits,
                    //       correct by Property 1)
                    // if (0 < f* < 10^(-x)) then the result is exact
                    // n = C* * 10^(e+x)
                    
                    if ind - 1 <= 2 {    // 0 <= ind - 1 <= 2 => shift = 0
                        res = P128.hi
                        fstar.hi = 0
                        fstar.lo = P128.lo
                    } else if ind - 1 <= 21 {    // 3 <= ind - 1 <= 21 => 3 <= shift <= 63
                        let shift = bid_shiftright128[ind - 1]    // 3 <= shift <= 63
                        res = (P128.hi >> shift)
                        fstar.hi = P128.hi & bid_maskhigh128[ind - 1]
                        fstar.lo = P128.lo
                    }
                    // if (f* > 10^(-x)) then the result is inexact
                    if (fstar.hi != 0) || (fstar.lo >= bid_ten2mk64[ind - 1]) {
                        if x_sign != 0 {
                            // if negative and not exact, increment magnitude
                            res+=1
                        }
                        pfpsf.insert(.inexact)
                    }
                    // set exponent to zero as it was negative before.
                    return x_sign | zero | res
                } else {    // if exp < 0 and q + exp <= 0
                    // the result is +0 or -1
                    if x_sign != 0 {
                        res = 0xb1c0000000000001
                    } else {
                        res = zero
                    }
                    pfpsf.insert(.inexact)
                    return res
                }
            case BID_ROUNDING_UP:
                if (q + exp) > 0 {    // exp < 0 and 1 <= -exp < q
                    // need to shift right -exp digits from the coefficient; exp will be 0
                    ind = -exp    // 1 <= ind <= 16; ind is a synonym for 'x'
                    // chop off ind digits from the lower part of C1
                    // C1 fits in 64 bits
                    // calculate C* and f*
                    // C* is actually floor(C*) in this case
                    // C* and f* need shifting and masking, as shown by
                    // bid_shiftright128[] and bid_maskhigh128[]
                    // 1 <= x <= 16
                    // kx = 10^(-x) = bid_ten2mk64[ind - 1]
                    // C* = C1 * 10^(-x)
                    // the approximation of 10^(-x) was rounded up to 64 bits
                    __mul_64x64_to_128(&P128, C1, bid_ten2mk64[ind - 1])
                    
                    // C* = floor(C*) (logical right shift; C has p decimal digits,
                    //       correct by Property 1)
                    // if (0 < f* < 10^(-x)) then the result is exact
                    // n = C* * 10^(e+x)
                    
                    if ind - 1 <= 2 {    // 0 <= ind - 1 <= 2 => shift = 0
                        res = P128.hi
                        fstar.hi = 0
                        fstar.lo = P128.lo
                    } else if ind - 1 <= 21 {    // 3 <= ind - 1 <= 21 => 3 <= shift <= 63
                        let shift = bid_shiftright128[ind - 1]    // 3 <= shift <= 63
                        res = (P128.hi >> shift)
                        fstar.hi = P128.hi & bid_maskhigh128[ind - 1]
                        fstar.lo = P128.lo
                    }
                    // if (f* > 10^(-x)) then the result is inexact
                    if (fstar.hi != 0) || (fstar.lo >= bid_ten2mk64[ind - 1]) {
                        if x_sign == 0 {
                            // if positive and not exact, increment magnitude
                            res+=1
                        }
                        pfpsf.insert(.inexact)
                    }
                    // set exponent to zero as it was negative before.
                    return x_sign | zero | res
                } else {    // if exp < 0 and q + exp <= 0
                    // the result is -0 or +1
                    if x_sign != 0 {
                        res = zero | SIGN_MASK64
                    } else {
                        res = zero+1
                    }
                    pfpsf.insert(.inexact)
                    return res
                }
            case BID_ROUNDING_TO_ZERO:
                if (q + exp) >= 0 {    // exp < 0 and 1 <= -exp <= q
                    // need to shift right -exp digits from the coefficient; exp will be 0
                    ind = -exp    // 1 <= ind <= 16; ind is a synonym for 'x'
                    // chop off ind digits from the lower part of C1
                    // C1 fits in 127 bits
                    // calculate C* and f*
                    // C* is actually floor(C*) in this case
                    // C* and f* need shifting and masking, as shown by
                    // bid_shiftright128[] and bid_maskhigh128[]
                    // 1 <= x <= 16
                    // kx = 10^(-x) = bid_ten2mk64[ind - 1]
                    // C* = C1 * 10^(-x)
                    // the approximation of 10^(-x) was rounded up to 64 bits
                    __mul_64x64_to_128(&P128, C1, bid_ten2mk64[ind - 1])
                    
                    // C* = floor(C*) (logical right shift; C has p decimal digits,
                    //       correct by Property 1)
                    // if (0 < f* < 10^(-x)) then the result is exact
                    // n = C* * 10^(e+x)
                    
                    if ind - 1 <= 2 {    // 0 <= ind - 1 <= 2 => shift = 0
                        res = P128.hi
                        fstar.hi = 0
                        fstar.lo = P128.lo
                    } else if ind - 1 <= 21 {    // 3 <= ind - 1 <= 21 => 3 <= shift <= 63
                        let shift = bid_shiftright128[ind - 1]    // 3 <= shift <= 63
                        res = (P128.hi >> shift)
                        fstar.hi = P128.hi & bid_maskhigh128[ind - 1]
                        fstar.lo = P128.lo
                    }
                    // if (f* > 10^(-x)) then the result is inexact
                    if (fstar.hi != 0) || (fstar.lo >= bid_ten2mk64[ind - 1]) {
                        pfpsf.insert(.inexact)
                    }
                    // set exponent to zero as it was negative before.
                    return x_sign | zero | res
                } else {    // if exp < 0 and q + exp < 0
                    // the result is +0 or -0
                    res = x_sign | zero
                    pfpsf.insert(.inexact)
                    return res
                }
            default: break
        }    // end switch ()
        return res
    }
    
    static func add(_ x:UInt64, _ y:UInt64, _ rnd_mode: Rounding, _ pfpsf:inout Status) -> UInt64 {
        var sign_x = UInt64(), sign_y = UInt64(), coefficient_x = UInt64(), coefficient_y = UInt64()
        var exponent_x = 0, exponent_y = 0, res = UInt64(), C64 = UInt64(), CT = UInt128(), CA = UInt128()
        var amount = 0, sign_s = UInt64()
        let valid_x = unpack_BID64 (&sign_x, &exponent_x, &coefficient_x, x);
        let valid_y = unpack_BID64 (&sign_y, &exponent_y, &coefficient_y, y);
        
        // unpack arguments, check for NaN or Infinity
        if !valid_x {
            // x is Inf. or NaN
            
            // test if x is NaN
            if ((x & NAN_MASK64) == NAN_MASK64) {
                if (((x & SNAN_MASK64) == SNAN_MASK64)    // sNaN
                    || ((y & SNAN_MASK64) == SNAN_MASK64)) {
                    pfpsf.insert(.invalidOperation)
                }
                return coefficient_x & QUIET_MASK64
            }
            // x is Infinity?
            if ((x & INFINITY_MASK64) == INFINITY_MASK64) {
                // check if y is Inf
                if (((y & NAN_MASK64) == INFINITY_MASK64)) {
                    if (sign_x == (y & MASK_SIGN)) {
                        return coefficient_x
                    }
                    // return NaN
                    pfpsf.insert(.invalidOperation)
                    return NAN_MASK64
                }
                // check if y is NaN
                if (((y & NAN_MASK64) == NAN_MASK64)) {
                    res = coefficient_y & QUIET_MASK64;
                    if (((y & SNAN_MASK64) == SNAN_MASK64)) {
                        pfpsf.insert(.invalidOperation)
                    }
                    return (res);
                }
                // otherwise return +/-Inf
                return coefficient_x
            }
            // x is 0
            if (((y & INFINITY_MASK64) != INFINITY_MASK64) && coefficient_y != 0) {
                if (exponent_y <= exponent_x) {
                    return y
                }
            }
        }
        if !valid_y {
            // y is Inf. or NaN?
            if (((y & INFINITY_MASK64) == INFINITY_MASK64)) {
                if ((y & SNAN_MASK64) == SNAN_MASK64)  { // sNaN
                    pfpsf.insert(.invalidOperation)
                }
                return coefficient_y & QUIET_MASK64
            }
            // y is 0
            if coefficient_x == 0 {    // x==0
                if (exponent_x <= exponent_y) {
                    res = UInt64(Int64(exponent_x) << EXPONENT_SHIFT_SMALL64)
                } else {
                    res = UInt64(Int64( exponent_y) << EXPONENT_SHIFT_SMALL64)
                }
                if (sign_x == sign_y) {
                    res |= sign_x;
                }
                if (rnd_mode == BID_ROUNDING_DOWN && sign_x != sign_y) {
                    res |= MASK_SIGN;
                }
                return res
            } else if (exponent_y >= exponent_x) {
                return x;
            }
        }
        
        // sort arguments by exponent
        var sign_a = UInt64(), sign_b = UInt64(), coefficient_a = UInt64(), coefficient_b = UInt64()
        var exponent_a = 0, exponent_b = 0
        if (exponent_x < exponent_y) {
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
        var diff_dec_expon = exponent_a - exponent_b;
        
        /* get binary coefficients of x and y */
        
        //--- get number of bits in the coefficients of x and y ---
        
        // version 2 (original)
        let tempx = Double(coefficient_a)
        var bin_expon_ca = Int((tempx.bitPattern & MASK_BINARY_EXPONENT) >> 52) - BINARY_EXPONENT_BIAS
        
        if diff_dec_expon > MAX_DIGITS {
            // normalize a to a 16-digit coefficient
            var scale_ca = Int(bid_estimate_decimal_digits[bin_expon_ca])
            if coefficient_a >= bid_power10_table_128[scale_ca].lo {
                scale_ca+=1
            }
            
            let scale_k = 16 - scale_ca
            
            coefficient_a *= bid_power10_table_128[scale_k].lo
            
            diff_dec_expon -= scale_k;
            exponent_a -= scale_k;
            
            /* get binary coefficients of x and y */
            
            //--- get number of bits in the coefficients of x and y ---
            let tempx = Double(coefficient_a)
            bin_expon_ca = Int((tempx.bitPattern & MASK_BINARY_EXPONENT) >> 52) - BINARY_EXPONENT_BIAS
            
            if diff_dec_expon > MAX_DIGITS {
                if coefficient_b != 0 {
                    pfpsf.insert(.inexact)
                }
                
                let irnd_mode = roundboundIndex(rnd_mode) >> 2
                let Ten15 = 1_000_000_000_000_000
                if ((irnd_mode & 3 != 0) && coefficient_b != 0) {   // not BID_ROUNDING_TO_NEAREST
                    switch rnd_mode {
                        case BID_ROUNDING_DOWN:
                            if sign_b != 0 {
                                coefficient_a -= UInt64((Int64(sign_a) >> 63) | 1)
                                if coefficient_a < Ten15 {
                                    exponent_a-=1
                                    coefficient_a = MAX_NUMBER
                                } else if coefficient_a >= MAX_NUMBERP1 {
                                    exponent_a+=1
                                    coefficient_a = UInt64(Ten15)
                                }
                            }
                        case BID_ROUNDING_UP:
                            if sign_b == 0 {
                                coefficient_a += UInt64((Int64(sign_a) >> 63) | 1)
                                if coefficient_a < Ten15 {
                                    exponent_a-=1
                                } else if coefficient_a >= MAX_NUMBERP1 {
                                    exponent_a+=1
                                    coefficient_a = UInt64(Ten15)
                                }
                            }
                        default:    // RZ
                            if sign_a != sign_b {
                                coefficient_a-=1
                                if coefficient_a < Ten15 {
                                    exponent_a-=1
                                    coefficient_a = MAX_NUMBER
                                }
                            }
                    }
                } else {
                    // check special case here
                    if ((coefficient_a == Ten15) && (diff_dec_expon == MAX_DIGITS + 1)
                        && (sign_a ^ sign_b != 0) && (coefficient_b > 5_000_000_000_000_000)) {
                        coefficient_a = MAX_NUMBER
                        exponent_a-=1
                    }
                }
                
                return fast_get_BID64_check_OF (sign_a, exponent_a, coefficient_a, rnd_mode, &pfpsf);
            }
        }
        
        // test whether coefficient_a*10^(exponent_a-exponent_b)  may exceed 2^62
        var extra_digits = 0
        var rmode:Int
        if bin_expon_ca + Int(bid_estimate_bin_expon[diff_dec_expon]) < 60 {
            // coefficient_a*10^(exponent_a-exponent_b)<2^63
            
            // multiply by 10^(exponent_a-exponent_b)
            coefficient_a *= bid_power10_table_128[diff_dec_expon].lo;
            
            // sign mask
            sign_b = UInt64(Int64(sign_b) >> 63)
            // apply sign to coeff. of b
            coefficient_b = (coefficient_b + sign_b) ^ sign_b;
            
            // apply sign to coefficient a
            sign_a = UInt64(Int64(sign_a) >> 63)
            coefficient_a = (coefficient_a + sign_a) ^ sign_a;
            
            coefficient_a += coefficient_b;
            // get sign
            var sign_s = UInt64(Int64(coefficient_a) >> 63)
            coefficient_a = (coefficient_a + sign_s) ^ sign_s;
            sign_s &= MASK_SIGN;
            
            // coefficient_a < 10^16 ?
            if coefficient_a < bid_power10_table_128[MAX_DIGITS].lo {
                if (rnd_mode == BID_ROUNDING_DOWN && (coefficient_a == 0) && sign_a != sign_b) {
                    sign_s = MASK_SIGN;
                }
                return very_fast_get_BID64 (sign_s, exponent_b, coefficient_a)
            }
            // otherwise rounding is necessary
            
            // already know coefficient_a<10^19
            // coefficient_a < 10^17 ?
            let extra_digits:Int
            if (coefficient_a < bid_power10_table_128[17].lo) {
                extra_digits = 1;
            } else if (coefficient_a < bid_power10_table_128[18].lo) {
                extra_digits = 2;
            } else {
                extra_digits = 3;
            }
            
            rmode = roundboundIndex(rnd_mode) >> 2
            if (sign_s != 0 && UInt(rmode &- 1) < 2) {
                rmode = 3 - rmode;
            }
            
            coefficient_a += bid_round_const_table[rmode][extra_digits];
            
            // get P*(2^M[extra_digits])/10^extra_digits
            __mul_64x64_to_128(&CT, coefficient_a, bid_reciprocals10_64[extra_digits]);
            
            // now get P/10^extra_digits: shift C64 right by M[extra_digits]-128
            let amount = bid_short_recip_scale[extra_digits];
            C64 = CT.hi >> amount;
            
        } else {
            // coefficient_a*10^(exponent_a-exponent_b) is large
            sign_s = sign_a
            
            rmode = roundboundIndex(rnd_mode) >> 2
            if (sign_s != 0 && UInt(rmode - 1) < 2) {
                rmode = 3 - rmode;
            }
            
            // check whether we can take faster path
            var scale_ca = Int(bid_estimate_decimal_digits[bin_expon_ca])
            
            var sign_ab = sign_a ^ sign_b;
            sign_ab = UInt64(Int64(sign_ab) >> 63)
            
            // T1 = 10^(16-diff_dec_expon)
            let T1 = bid_power10_table_128[16 - diff_dec_expon].lo;
            
            // get number of digits in coefficient_a
            if (coefficient_a >= bid_power10_table_128[scale_ca].lo) {
                scale_ca+=1
            }
            
            let scale_k = 16 - scale_ca
            
            // addition
            var saved_ca = coefficient_a - T1;
            coefficient_a = UInt64(Int64(saved_ca) * Int64(bid_power10_table_128[scale_k].lo))
            extra_digits = diff_dec_expon - scale_k;
            
            // apply sign
            var saved_cb = (coefficient_b + sign_ab) ^ sign_ab;
            // add 10^16 and rounding constant
            coefficient_b = saved_cb + MAX_NUMBERP1 + bid_round_const_table[rmode][extra_digits];
            
            // get P*(2^M[extra_digits])/10^extra_digits
            __mul_64x64_to_128 (&CT, coefficient_b, bid_reciprocals10_64[extra_digits]);
            
            // now get P/10^extra_digits: shift C64 right by M[extra_digits]-128
            amount = Int(bid_short_recip_scale[extra_digits])
            var C0_64 = CT.hi >> amount
            
            // result coefficient
            C64 = C0_64 + coefficient_a
            
            // filter out difficult (corner) cases
            // this test ensures the number of digits in coefficient_a does not change
            // after adding (the appropriately scaled and rounded) coefficient_b
            if (UInt64(C64 - 1000000000000000 - 1) > 9000000000000000 - 2) {
                if (C64 >= MAX_NUMBERP1) {
                    // result has more than 16 digits
                    if scale_k == 0 {
                        // must divide coeff_a by 10
                        saved_ca = saved_ca + T1
                        __mul_64x64_to_128(&CA, saved_ca, 0x3333333333333334);
                        //reciprocals10_64[1]);
                        coefficient_a = CA.hi >> 1;
                        let rem_a = saved_ca - (coefficient_a << 3) - (coefficient_a << 1);
                        coefficient_a = coefficient_a - T1;
                        
                        saved_cb += rem_a * bid_power10_table_128[diff_dec_expon].lo;
                    } else {
                        coefficient_a = UInt64(Int64(saved_ca - T1 - (T1 << 3)) * Int64(bid_power10_table_128[scale_k - 1].lo))
                    }
                    
                    extra_digits+=1
                    coefficient_b = saved_cb + MAX_NUMBERP1 + bid_round_const_table[rmode][extra_digits];
                    
                    // get P*(2^M[extra_digits])/10^extra_digits
                    __mul_64x64_to_128(&CT, coefficient_b, bid_reciprocals10_64[extra_digits]);
                    
                    // now get P/10^extra_digits: shift C64 right by M[extra_digits]-128
                    amount = Int(bid_short_recip_scale[extra_digits])
                    C0_64 = CT.hi >> amount;
                    
                    // result coefficient
                    C64 = C0_64 + coefficient_a;
                } else if (C64 <= 1000000000000000) {
                    // less than 16 digits in result
                    coefficient_a = UInt64(Int64(saved_ca) * Int64(bid_power10_table_128[scale_k + 1].lo))
                    //extra_digits -=1
                    exponent_b-=1
                    coefficient_b = (saved_cb << 3) + (saved_cb << 1) + MAX_NUMBERP1 +
                    bid_round_const_table[rmode][extra_digits];
                    
                    // get P*(2^M[extra_digits])/10^extra_digits
                    var CT_new = UInt128()
                    __mul_64x64_to_128(&CT_new, coefficient_b, bid_reciprocals10_64[extra_digits])
                    
                    // now get P/10^extra_digits: shift C64 right by M[extra_digits]-128
                    amount = Int(bid_short_recip_scale[extra_digits])
                    C0_64 = CT_new.hi >> amount;
                    
                    // result coefficient
                    let C64_new = C0_64 + coefficient_a;
                    if (C64_new < MAX_NUMBERP1) {
                        C64 = C64_new;
                        CT = CT_new;
                    } else {
                        exponent_b+=1
                    }
                }
            }
        }
        
        if rmode == 0 {   //BID_ROUNDING_TO_NEAREST
            if (C64 & 1 != 0) {
                // check whether fractional part of initial_P/10^extra_digits is
                // exactly .5
                // this is the same as fractional part of
                //      (initial_P + 0.5*10^extra_digits)/10^extra_digits is exactly zero
                
                // get remainder
                let remainder_h = CT.hi << (64 - amount);
                
                // test whether fractional part is 0
                if (remainder_h == 0 && (CT.lo < bid_reciprocals10_64[extra_digits])) {
                    C64-=1
                }
            }
        }
        
        
        var status = Status.inexact // BID_INEXACT_EXCEPTION;
        
        // get remainder
        let remainder_h = CT.hi << (64 - amount);
        
        switch rnd_mode {
            case BID_ROUNDING_TO_NEAREST, BID_ROUNDING_TIES_AWAY:
                // test whether fractional part is 0
                if ((remainder_h == MASK_SIGN) && (CT.lo < bid_reciprocals10_64[extra_digits])) {
                    status = []
                }
            case BID_ROUNDING_DOWN, BID_ROUNDING_TO_ZERO:
                if (remainder_h == 0 && (CT.lo < bid_reciprocals10_64[extra_digits])) {
                    status = []
                }
                //if(!C64 && rmode==BID_ROUNDING_DOWN) sign_s=sign_y;
            default:
                // round up
                var tmp = UInt64(), carry = UInt64()
                __add_carry_out(&tmp, &carry, CT.lo, bid_reciprocals10_64[extra_digits])
                if ((remainder_h >> (64 - amount)) + carry >= (UInt64(1) << amount)) {
                    status = []
                }
        }
        pfpsf.formUnion(status)
        return fast_get_BID64_check_OF (sign_s, exponent_b + extra_digits, C64, rnd_mode, &pfpsf)
    }
    
    /*****************************************************************************
     *    BID64 divide
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
    
    static func div(_ x:UInt64, _ y:UInt64, _ rnd_mode: Rounding, _ pfpsf: inout Status) -> UInt64 {
        var sign_x = UInt64(), sign_y = UInt64(), coefficient_x = UInt64()
        var coefficient_y = UInt64(), exponent_x = 0, exponent_y = 0
        let valid_x = unpack_BID64 (&sign_x, &exponent_x, &coefficient_x, x)
        let valid_y = unpack_BID64 (&sign_y, &exponent_y, &coefficient_y, y)
        var tdigit = [UInt32](repeating: 0, count: 3), CT = UInt128()
        
        // unpack arguments, check for NaN or Infinity
        if (!valid_x) {
            // x is Inf. or NaN
            if ((y & SNAN_MASK64) == SNAN_MASK64) {   // y is sNaN
                pfpsf.insert(.invalidOperation)
            }
            
            // test if x is NaN
            if ((x & NAN_MASK64) == NAN_MASK64) {
                if ((x & SNAN_MASK64) == SNAN_MASK64) {   // sNaN
                    pfpsf.insert(.invalidOperation)
                }
                return (coefficient_x & QUIET_MASK64);
            }
            // x is Infinity?
            if ((x & INFINITY_MASK64) == INFINITY_MASK64) {
                // check if y is Inf or NaN
                if ((y & INFINITY_MASK64) == INFINITY_MASK64) {
                    // y==Inf, return NaN
                    if ((y & NAN_MASK64) == INFINITY_MASK64) {    // Inf/Inf
                        pfpsf.insert(.invalidOperation)
                        return (NAN_MASK64);
                    }
                } else {
                    // otherwise return +/-Inf
                    return (((x ^ y) & MASK_SIGN) | INFINITY_MASK64)
                }
            }
            // x==0
            if (((y & INFINITY_MASK64) != INFINITY_MASK64) && (coefficient_y == 0)) {
                // y==0 , return NaN
                pfpsf.insert(.invalidOperation)
                return (NAN_MASK64);
            }
            if (((y & INFINITY_MASK64) != INFINITY_MASK64)) {
                if ((y & SPECIAL_ENCODING_MASK64) == SPECIAL_ENCODING_MASK64) {
                    exponent_y = Int(UInt32(y >> EXPONENT_SHIFT_LARGE64)) & BINARY_EXPONENT_BIAS
                } else {
                    exponent_y = Int(UInt32(y >> EXPONENT_SHIFT_SMALL64)) & BINARY_EXPONENT_BIAS
                }
                sign_y = y & MASK_SIGN;
                
                exponent_x = exponent_x - exponent_y + EXPONENT_BIAS;
                if (exponent_x > MAX_EXPON) {
                    exponent_x = MAX_EXPON
                } else if (exponent_x < 0) {
                    exponent_x = 0;
                }
                return (sign_x ^ sign_y) | UInt64(exponent_x << EXPONENT_SHIFT_SMALL64)
            }
            
        }
        if (!valid_y) {
            // y is Inf. or NaN
            
            // test if y is NaN
            if ((y & NAN_MASK64) == NAN_MASK64) {
                if ((y & SNAN_MASK64) == SNAN_MASK64) {    // sNaN
                    pfpsf.insert(.invalidOperation)
                }
                return (coefficient_y & QUIET_MASK64);
            }
            // y is Infinity?
            if ((y & INFINITY_MASK64) == INFINITY_MASK64) {
                // return +/-0
                return (((x ^ y) & MASK_SIGN));
            }
            // y is 0
            pfpsf.insert(.divisionByZero)
            return ((sign_x ^ sign_y) | INFINITY_MASK64);
        }
        
        var diff_expon = exponent_x - exponent_y + EXPONENT_BIAS
        var db = 0.0, Q = UInt64(0), CA = UInt128(), B = UInt64(), ed1 = 0, ed2 = 0
        
        if (coefficient_x < coefficient_y) {
            // get number of decimal digits for c_x, c_y
            
            //--- get number of bits in the coefficients of x and y ---
            let tempx = Float(coefficient_x)
            let tempy = Float(coefficient_y)
            let bin_index = Int(tempy.bitPattern - tempx.bitPattern) >> 23
            
            let A = coefficient_x * bid_power10_index_binexp[bin_index];
            B = coefficient_y;
            
            var temp_b = Double(B)
            
            // compare A, B
            let DU = (A - B) >> 63;
            ed1 = 15 + Int(DU)
            ed2 = Int(bid_estimate_decimal_digits[bin_index]) + ed1;
            let T = bid_power10_table_128[ed1].lo
            __mul_64x64_to_128(&CA, A, T);
            
            Q = 0
            diff_expon = diff_expon - ed2;
            
            // adjust double precision db, to ensure that later A/B - (int)(da/db) > -1
            if (coefficient_y < MASK_BINARY_OR2) {
                temp_b = Double(bitPattern: temp_b.bitPattern + 1)
                db = temp_b
            } else {
                db = Double(B + 2 + (B & 1))
            }
            
        } else {
            // get c_x/c_y
            
            //  set last bit before conversion to DP
            let A2 = coefficient_x | 1;
            let da = Double(A2)
            let db = Double(coefficient_y)
            
            let tempq = da / db;
            Q = UInt64(tempq.bitPattern)
            
            var R = coefficient_x - coefficient_y * Q;
            
            // will use to get number of dec. digits of Q
            let bin_expon_cx = Int(tempq.bitPattern >> 52) - BINARY_EXPONENT_BIAS
            
            // R<0 ?
            let D = Int64(R) >> 63
            Q += UInt64(D)
            R += coefficient_y & UInt64(D)
            
            // exact result ?
            if Int64(R) <= 0 {
                // can have R==-1 for coeff_y==1
                return get_BID64 (sign_x ^ sign_y, diff_expon, (Q + R), rnd_mode, &pfpsf)
            }
            // get decimal digits of Q
            var DU = bid_power10_index_binexp[bin_expon_cx] - Q - 1;
            DU >>= 63;
            
            ed2 = 16 - Int(bid_estimate_decimal_digits[bin_expon_cx]) - Int(DU)
            
            let T = bid_power10_table_128[ed2].lo;
            __mul_64x64_to_128(&CA, R, T);
            B = coefficient_y;
            
            Q *= bid_power10_table_128[ed2].lo
            diff_expon -= ed2;
        }
        
        var R = UInt64(), Q2 = UInt64(), B4 = UInt64()
        if CA.hi == 0 {
            Q2 = CA.lo / B;
            let B2 = B + B;
            B4 = B2 + B2;
            R = CA.lo - Q2 * B;
            Q += Q2;
        } else {
            // 2^64
            let t_scale = Double(bitPattern: 0x43f0000000000000)
            // convert CA to DP
            let da_h = Double(CA.hi)
            let da_l = Double(CA.lo)
            let da = da_h * t_scale + da_l
            
            // quotient
            let dq = da / db
            Q2 = UInt64(dq)
            
            // get w[0] remainder
            R = CA.lo - Q2 * B;
            
            // R<0 ?
            var D = Int64(R) >> 63;
            Q2 += UInt64(D)
            R += B & UInt64(D)
            
            // now R<6*B
            
            // quick divide
            
            // 4*B
            let B2 = B + B
            B4 = B2 + B2
            
            R = R - B4
            // R<0 ?
            D = Int64(R) >> 63
            // restore R if negative
            R += B4 & UInt64(D)
            Q2 += ~UInt64(D) & 4
            
            R = R - B2;
            // R<0 ?
            D = Int64(R) >> 63;
            // restore R if negative
            R += B2 & UInt64(D)
            Q2 += ~UInt64(D) & 2
            
            R = R - B;
            // R<0 ?
            D = Int64(R) >> 63
            // restore R if negative
            R += B & UInt64(D)
            Q2 += ~UInt64(D) & 1
            Q += Q2
        }
        
        if R != 0 {
            // set status flags
            pfpsf.insert(.inexact)
        } else {
            // eliminate trailing zeros
            
            // check whether CX, CY are short
            var nzeros = 0
            if (coefficient_x <= 1024) && (coefficient_y <= 1024) {
                let i = Int(coefficient_y) - 1;
                let j = Int(coefficient_x) - 1;
                // difference in powers of 2 bid_factors for Y and X
                nzeros = ed2 - Int(bid_factors[i][0]) + Int(bid_factors[j][0])
                // difference in powers of 5 bid_factors
                let d5 = ed2 - Int(bid_factors[i][1]) + Int(bid_factors[j][1])
                if d5 < nzeros {
                    nzeros = d5
                }
                
                __mul_64x64_to_128(&CT, Q, bid_reciprocals10_64[nzeros]);
                
                // now get P/10^extra_digits: shift C64 right by M[extra_digits]-128
                let amount = bid_short_recip_scale[nzeros];
                Q = CT.hi >> amount;
                
                diff_expon += nzeros;
            } else {
                tdigit[0] = UInt32(Q & 0x3ffffff)
                tdigit[1] = 0
                let QX = Q >> 26
                var QX32 = QX
                nzeros = 0
                
                for j in 0..<bid_convert_table.count where QX32 != 0 {  // ; QX32; j++, QX32 >>= 7) {
                    let k = Int(QX32 & 127)
                    tdigit[0] += bid_convert_table[j][k][0]
                    tdigit[1] += bid_convert_table[j][k][1]
                    if tdigit[0] >= 100_000_000 {
                        tdigit[0] -= 100_000_000
                        tdigit[1] += 1
                    }
                    QX32 >>= 7
                }
                
                var digit = tdigit[0];
                if digit == 0 && tdigit[1] == 0 {
                    nzeros += 16
                } else {
                    if digit == 0 {
                        nzeros += 8
                        digit = tdigit[1]
                    }
                    // decompose digit
                    let PD = UInt64(digit) * 0x068DB8BB
                    var digit_h = UInt32(PD >> 40)
                    let digit_low = digit - digit_h * 10000
                    
                    if (digit_low != 0) {
                        nzeros += 4
                    } else {
                        digit_h = digit_low
                    }
                    
                    if ((digit_h & 1) == 0) {
                        nzeros += 3 & Int(UInt32(bid_packed_10000_zeros[Int(digit_h) >> 3] >> (digit_h & 7)))
                    }
                }
                
                if nzeros != 0 {
                    __mul_64x64_to_128(&CT, Q, bid_reciprocals10_64[nzeros]);
                    
                    // now get P/10^extra_digits: shift C64 right by M[extra_digits]-128
                    let amount = bid_short_recip_scale[nzeros];
                    Q = CT.hi >> amount;
                }
                diff_expon += nzeros;
                
            }
            if (diff_expon >= 0) {
                return fast_get_BID64_check_OF(sign_x ^ sign_y, diff_expon, Q, rnd_mode, &pfpsf)
            }
        }
        
        if (diff_expon >= 0) {
            var rmode = roundboundIndex(rnd_mode) >> 2
            if ((sign_x ^ sign_y) != 0 && UInt(rmode - 1) < 2) {
                rmode = 3 - rmode;
            }
            switch rnd_mode {
                case BID_ROUNDING_TO_NEAREST, BID_ROUNDING_TIES_AWAY:
                    // R*10
                    R += R
                    R = (R << 2) + R
                    let B5 = B4 + B
                    // compare 10*R to 5*B
                    R = B5 - R
                    // correction for (R==0 && (Q&1))
                    R -= ((Q | UInt64(rmode >> 2)) & 1)
                    // R<0 ?
                    let D = UInt64(R) >> 63
                    Q += D
                case BID_ROUNDING_DOWN, BID_ROUNDING_TO_ZERO:
                    break
                default:    // rounding up
                    Q+=1
            }
            return fast_get_BID64_check_OF (sign_x ^ sign_y, diff_expon, Q, rnd_mode, &pfpsf)
        } else {
            // UF occurs
            if ((diff_expon + 16 < 0)) {
                // set status flags
                pfpsf.insert(.inexact)
            }
            return get_BID64_UF (sign_x ^ sign_y, diff_expon, Q, R, rnd_mode, &pfpsf)
        }
    }
    
    static func bid64_rem(_ x:UInt64, _ y:UInt64, _ pfpsf: inout Status) -> UInt64 {
        var sign_x = UInt64(), sign_y = UInt64(), coefficient_x = UInt64()
        var coefficient_y = UInt64(), exponent_x = 0, exponent_y = 0
        let valid_y = unpack_BID64 (&sign_y, &exponent_y, &coefficient_y, y);
        let valid_x = unpack_BID64 (&sign_x, &exponent_x, &coefficient_x, x);
        
        // unpack arguments, check for NaN or Infinity
        if !valid_x {
            // x is Inf. or NaN or 0
            if ((y & SNAN_MASK64) == SNAN_MASK64) {    // y is sNaN
                pfpsf.insert(.invalidOperation)
            }
            
            // test if x is NaN
            if ((x & MASK_ANY_INF) == MASK_ANY_INF) {
                if (((x & SNAN_MASK64) == SNAN_MASK64)) {
                    pfpsf.insert(.invalidOperation)
                }
                return coefficient_x & QUIET_MASK64;
            }
            // x is Infinity?
            if ((x & MASK_INF) == MASK_INF) {
                if (((y & NAN_MASK64) != NAN_MASK64)) {
                    pfpsf.insert(.invalidOperation)
                    // return NaN
                    return MASK_ANY_INF
                }
            }
            // x is 0
            // return x if y != 0
            if ((y & MASK_INF) < MASK_INF) && (coefficient_y != 0) {
                if (y & SPECIAL_ENCODING_MASK64) == SPECIAL_ENCODING_MASK64 {
                    exponent_y = Int(y >> UPPER_EXPON_LIMIT) & BINARY_EXPONENT_BIAS
                } else {
                    exponent_y = Int(y >> EXPONENT_SHIFT_SMALL64) & BINARY_EXPONENT_BIAS
                }
                
                if exponent_y < exponent_x {
                    exponent_x = exponent_y
                }
                
                var x = UInt64(exponent_x)
                x <<= EXPONENT_SHIFT_SMALL64
                
                return x | sign_x
            }
            
        }
        if !valid_y {
            // y is Inf. or NaN
            // test if y is NaN
            if (y & MASK_ANY_INF) == MASK_ANY_INF {
                if (((y & SNAN_MASK64) == SNAN_MASK64)) {
                    pfpsf.insert(.invalidOperation)
                }
                return coefficient_y & QUIET_MASK64
            }
            // y is Infinity?
            if (y & MASK_INF) == MASK_INF {
                return very_fast_get_BID64 (sign_x, exponent_x, coefficient_x)
            }
            // y is 0, return NaN
            pfpsf.insert(.invalidOperation)
            return MASK_ANY_INF
        }
        
        
        var diff_expon = exponent_x - exponent_y
        var Q = UInt64()
        if (diff_expon <= 0) {
            diff_expon = -diff_expon;
            
            if (diff_expon > 16) {
                // |x|<|y| in this case
                return x
            }
            // set exponent of y to exponent_x, scale coefficient_y
            let T = bid_power10_table_128[diff_expon].lo
            var CY = UInt128()
            __mul_64x64_to_128(&CY, coefficient_y, T);
            
            if (CY.hi != 0 || CY.lo > (coefficient_x << 1)) {
                return x
            }
            
            Q = coefficient_x / CY.lo;
            var R = coefficient_x - Q * CY.lo;
            
            let R2 = R + R;
            if (R2 > CY.lo || (R2 == CY.lo && (Q & 1 != 0))) {
                R = CY.lo - R;
                sign_x ^= MASK_SIGN;
            }
            
            return very_fast_get_BID64 (sign_x, exponent_x, R)
        }
        
        
        while (diff_expon > 0) {
            // get number of digits in coeff_x
            let tempx = Float(coefficient_x)
            let bin_expon = Int((tempx.bitPattern >> 23) & 0xff) - 0x7f;
            let digits_x = bid_estimate_decimal_digits[bin_expon];
            // will not use this test, dividend will have 18 or 19 digits
            //if(coefficient_x >= bid_power10_table_128[digits_x].lo)
            //      digits_x+=1
            
            var e_scale = Int(18 - digits_x)
            if (diff_expon >= e_scale) {
                diff_expon -= e_scale;
            } else {
                e_scale = diff_expon;
                diff_expon = 0;
            }
            
            // scale dividend to 18 or 19 digits
            coefficient_x *= bid_power10_table_128[e_scale].lo;
            
            // quotient
            Q = coefficient_x / coefficient_y;
            // remainder
            coefficient_x -= Q * coefficient_y;
            
            // check for remainder == 0
            if coefficient_x == 0 {
                return very_fast_get_BID64_small_mantissa (sign_x, exponent_y, 0)
            }
        }
        
        let R2 = coefficient_x + coefficient_x;
        if (R2 > coefficient_y || (R2 == coefficient_y && (Q & 1 != 0))) {
            coefficient_x = coefficient_y - coefficient_x;
            sign_x ^= MASK_SIGN;
        }
        
        return very_fast_get_BID64 (sign_x, exponent_y, coefficient_x)
    }
    
    /*
     If x is not a floating-point number, the results are unspecified (this
     implementation returns x and exp = 0). Otherwise, the frexp function
     returns the value res, such that res has a magnitude in the interval
     [1/10, 1) or zero, and x = res*2^*exp. If x is zero, both parts of the
     result are zero
     frexp does not raise any exceptions
     */
    static func frexp(_ x: UInt64, _ res: inout UInt64, _ exp: inout Int) {
        var sig_x = UInt64(), exp_x = UInt64()
        if ((x & MASK_NAN) == MASK_NAN || (x & MASK_INF) == MASK_INF) {
            // if NaN or infinity
            exp = 0
            res = x
            // the binary frexp quitetizes SNaNs, so do the same
            if ((x & MASK_SNAN) == MASK_SNAN) { // x is SNAN
                //   // set invalid flag
                //   pfpsf.insert(.invalidOperation)
                // return quiet (x)
                res = x & QUIET_MASK64
            }
            return
        } else {
            // x is 0, non-canonical, normal, or subnormal
            // unpack x
            // if steering bits are 11 (condition will be 0), then exponent is G[0:w+1]
            if ((x & MASK_STEERING_BITS) == MASK_STEERING_BITS) {
                sig_x = (x & MASK_BINARY_SIG2) | MASK_BINARY_OR2;
                exp_x = (x & MASK_BINARY_EXPONENT2) >> EXPONENT_SHIFT_LARGE64;  // biased
                if (sig_x > MAX_NUMBER || sig_x == 0) { // non-canonical or zero
                    exp = 0
                    res = (x & MASK_SIGN) | UInt64(exp_x << EXPONENT_SHIFT_SMALL64); // zero of same sign
                    return
                }
            } else {
                sig_x = x & MASK_BINARY_SIG1;
                exp_x = (x & MASK_BINARY_EXPONENT1) >> EXPONENT_SHIFT_SMALL64;  // biased
                if (sig_x == 0x0) {
                    exp = 0
                    res = x // same zero
                    return
                }
            }
            // x is normal or subnormal, with exp_x=biased exponent & sig_x=coefficient
            // determine the number of decimal digits in sig_x, which fits in 54 bits
            // q = nr. of decimal digits in sig_x (1 <= q <= 16)
            //  determine first the nr. of bits in sig_x
            //  determine first the nr. of bits in x
            let q = digitsIn(sig_x)
//            if (sig_x >= MASK_BINARY_OR2) { // x >= 2^EXPONENT_SHIFT_SMALL64
//                q = 16;
//            } else { // if x < 2^EXPONENT_SHIFT_SMALL64
//                let tmp = Double(sig_x) // exact conversion
//                let x_nr_bits = 1 + Int((((tmp.bitPattern >> 52)) & 0x7ff) - BINARY_EXPONENT_BIAS)
//                q = Int(bid_nr_digits[x_nr_bits - 1].digits)
//                if q == 0 {
//                    q = Int(bid_nr_digits[x_nr_bits - 1].digits1)
//                    if (sig_x >= bid_nr_digits[x_nr_bits - 1].threshold_lo) {
//                        q+=1
//                    }
//                }
//            }
            // Do not add trailing zeros if q < 16; leave sig_x with q digits
            exp = Int(exp_x) - EXPONENT_BIAS + q
            // assemble the result
            if (sig_x < MASK_BINARY_OR2) { // sig_x < 2^EXPONENT_SHIFT_SMALL64 (fits in EXPONENT_SHIFT_SMALL64 bits)
                res = (x & 0x801fffffffffffff) | UInt64((-q + EXPONENT_BIAS) << EXPONENT_SHIFT_SMALL64); // replace exp.
            } else { // sig_x fits in 54 bits, but not in 53
                res = (x & 0xe007ffffffffffff) | UInt64((-q + EXPONENT_BIAS) << EXPONENT_SHIFT_LARGE64) // replace exp.
            }
        }
    }
    
    static func digitsIn(_ C1: UInt64) -> Int {
        var tmp1 = 0.0, x_nr_bits = 0
        if C1 >= MASK_BINARY_OR2 {    // x >= 2^EXPONENT_SHIFT_SMALL64
            // split the 64-bit value in two 32-bit halves to avoid rounding errors
            if C1 >= 0x0000000100000000 {    // x >= 2^32
                tmp1 = Double(C1 >> 32)    // exact conversion
                x_nr_bits = 33 + Int((((tmp1.bitPattern >> 52)) & 0x7ff) - UInt64(BINARY_EXPONENT_BIAS))
            } else {    // x < 2^32
                tmp1 = Double(C1)    // exact conversion
                x_nr_bits = 1 + Int((((tmp1.bitPattern >> 52)) & 0x7ff) - UInt64(BINARY_EXPONENT_BIAS))
            }
        } else {    // if x < 2^EXPONENT_SHIFT_SMALL64
            tmp1 = Double(C1)    // exact conversion
            x_nr_bits = 1 + Int((((tmp1.bitPattern >> 52)) & 0x7ff) - UInt64(BINARY_EXPONENT_BIAS))
        }
        var q1 = Int(bid_nr_digits[x_nr_bits - 1].digits)
        if q1 == 0 {
            q1 = Int(bid_nr_digits[x_nr_bits - 1].digits1)
            if C1 >= bid_nr_digits[x_nr_bits - 1].threshold_lo {
                q1 += 1
            }
        }
        return q1
    }
    
    static func bid64_nextup (_ x: UInt64, _ pfpsf: inout Status) -> UInt64 {
        // check for NaNs and infinities
        var x = x, res = UInt64()
        if ((x & MASK_NAN) == MASK_NAN) {    // check for NaN
            if ((x & 0x0003ffffffffffff) > 999_999_999_999_999) {
                x = x & 0xfe00000000000000;    // clear G6-G12 and the payload bits
            } else {
                x = x & 0xfe03ffffffffffff;    // clear G6-G12
            }
            if ((x & MASK_SNAN) == MASK_SNAN) {    // SNaN
                // set invalid flag
                pfpsf.insert(.invalidOperation)
                
                // return quiet (SNaN)
                res = x & QUIET_MASK64;
            } else {    // QNaN
                res = x;
            }
            return res
        } else if ((x & MASK_INF) == MASK_INF) {    // check for Infinity
            if (x & MASK_SIGN) == 0 {    // x is +inf
                res = MASK_INF;
            } else {    // x is -inf
                res = 0xf7fb86f26fc0ffff;    // -MAXFP = -999...99 * 10^emax
            }
            return res
        }
        // unpack the argument
        let x_sign = x & MASK_SIGN;    // 0 for positive, MASK_SIGN for negative
        var x_exp, C1:UInt64
        // if steering bits are 11 (condition will be 0), then exponent is G[0:w+1] =>
        if ((x & MASK_STEERING_BITS) == MASK_STEERING_BITS) {
            x_exp = (x & MASK_BINARY_EXPONENT2) >> EXPONENT_SHIFT_LARGE64;    // biased
            C1 = (x & MASK_BINARY_SIG2) | MASK_BINARY_OR2;
            if (C1 > MAX_NUMBER) {    // non-canonical
                x_exp = 0;
                C1 = 0;
            }
        } else {
            x_exp = (x & MASK_BINARY_EXPONENT1) >> EXPONENT_SHIFT_SMALL64;    // biased
            C1 = x & MASK_BINARY_SIG1;
        }
        
        // check for zeros (possibly from non-canonical values)
        if (C1 == 0x0) {
            // x is 0
            res = 0x0000000000000001;    // MINFP = 1 * 10^emin
        } else {    // x is not special and is not zero
            if (x == 0x77fb86f26fc0ffff) {
                // x = +MAXFP = 999...99 * 10^emax
                res = MASK_INF;    // +inf
            } else if (x == 0x8000000000000001) {
                // x = -MINFP = 1...99 * 10^emin
                res = MASK_SIGN;    // -0
            } else {    // -MAXFP <= x <= -MINFP - 1 ulp OR MINFP <= x <= MAXFP - 1 ulp
                // can add/subtract 1 ulp to the significand
                
                // Note: we could check here if x >= 10^16 to speed up the case q1 =16
                // q1 = nr. of decimal digits in x (1 <= q1 <= 54)
                //  determine first the nr. of bits in x
                let q1 = digitsIn(C1)
                //                var tmp1 = 0.0, x_nr_bits = 0
                //                if (C1 >= MASK_BINARY_OR2) {    // x >= 2^EXPONENT_SHIFT_SMALL64
                //                    // split the 64-bit value in two 32-bit halves to avoid rounding errors
                //                    if (C1 >= 0x0000000100000000) {    // x >= 2^32
                //                        tmp1 = Double(C1 >> 32)    // exact conversion
                //                        x_nr_bits = 33 + Int((((tmp1.bitPattern >> 52)) & 0x7ff) - BINARY_EXPONENT_BIAS);
                //                    } else {    // x < 2^32
                //                        tmp1 = Double(C1)    // exact conversion
                //                        x_nr_bits = 1 + (((Int(tmp1.bitPattern >> 52)) & 0x7ff) - BINARY_EXPONENT_BIAS);
                //                    }
                //                } else {    // if x < 2^EXPONENT_SHIFT_SMALL64
                //                    tmp1 = Double(C1)    // exact conversion
                //                    x_nr_bits = 1 + Int((((tmp1.bitPattern >> 52)) & 0x7ff) - BINARY_EXPONENT_BIAS);
                //                }
                //                var q1 = Int(bid_nr_digits[x_nr_bits - 1].digits)
                //                if q1 == 0 {
                //                    q1 = Int(bid_nr_digits[x_nr_bits - 1].digits1)
                //                    if (C1 >= bid_nr_digits[x_nr_bits - 1].threshold_lo) {
                //                        q1+=1
                //                    }
                //                }
                
                // if q1 < P16 then pad the significand with zeros
                if q1 < P16 {
                    if (x_exp > UInt64(P16 - q1)) {
                        let ind = Int(P16) - q1    // 1 <= ind <= P16 - 1
                        // pad with P16 - q1 zeros, until exponent = emin
                        // C1 = C1 * 10^ind
                        C1 = C1 * bid_ten2k64[ind];
                        x_exp = x_exp - UInt64(ind)
                    } else {    // pad with zeros until the exponent reaches emin
                        let ind = Int(x_exp)
                        C1 = C1 * bid_ten2k64[ind]
                        x_exp = EXP_MIN
                    }
                }
                if x_sign == 0 {    // x > 0
                    // add 1 ulp (add 1 to the significand)
                    C1+=1
                    if (C1 == 0x002386f26fc10000) {    // if  C1 = 10^16
                        C1 = 0x00038d7ea4c68000;    // C1 = 10^15
                        x_exp+=1
                    }
                    // Ok, because MAXFP = 999...99 * 10^emax was caught already
                } else {    // x < 0
                    // subtract 1 ulp (subtract 1 from the significand)
                    C1-=1
                    if (C1 == 0x00038d7ea4c67fff && x_exp != 0) {    // if  C1 = 10^15 - 1
                        C1 = 0x002386f26fc0ffff;    // C1 = 10^16 - 1
                        x_exp-=1
                    }
                }
                // assemble the result
                // if significand has 54 bits
                if (C1 & MASK_BINARY_OR2) != 0 {
                    res = x_sign | (x_exp << EXPONENT_SHIFT_LARGE64) | MASK_STEERING_BITS | (C1 & MASK_BINARY_SIG2)
                } else {    // significand fits in EXPONENT_SHIFT_SMALL64 bits
                    res = x_sign | (x_exp << EXPONENT_SHIFT_SMALL64) | C1
                }
            }    // end -MAXFP <= x <= -MINFP - 1 ulp OR MINFP <= x <= MAXFP - 1 ulp
        }    // end x is not special and is not zero
        return res
    }
    
    static func sqrt(_ x: UInt64, _ rnd_mode: Rounding, _ pfpsf: inout Status) -> UInt64 {
        // unpack arguments, check for NaN or Infinity
        var sign_x = UInt64(), coefficient_x = UInt64(), exponent_x = 0
        var res = UInt64(), CA = UInt128()
        if (!unpack_BID64 (&sign_x, &exponent_x, &coefficient_x, x)) {
            // x is Inf. or NaN or 0
            if ((x & INFINITY_MASK64) == INFINITY_MASK64) {
                res = coefficient_x;
                if ((coefficient_x & SSNAN_MASK64) == SINFINITY_MASK64)    // -Infinity
                {
                    res = NAN_MASK64;
                    pfpsf.insert(.invalidOperation)
                }
                if ((x & SNAN_MASK64) == SNAN_MASK64) {   // sNaN
                    pfpsf.insert(.invalidOperation)
                }
                return (res & QUIET_MASK64);
            }
            // x is 0
            exponent_x = (exponent_x + EXPONENT_BIAS) >> 1;
            res = sign_x | (UInt64(exponent_x) << EXPONENT_SHIFT_SMALL64);
            return res
        }
        // x<0?
        if sign_x != 0 && coefficient_x != 0 {
            res = NAN_MASK64;
            pfpsf.insert(.invalidOperation)
            return res
        }
        
        //--- get number of bits in the coefficient of x ---
        let tempx = Float(coefficient_x)
        let bin_expon_cx = Int((tempx.bitPattern >> 23) & 0xff) - 0x7f
        var digits_x = Int(bid_estimate_decimal_digits[bin_expon_cx])
        
        // add test for range
        if (coefficient_x >= bid_power10_index_binexp[bin_expon_cx]) {
            digits_x+=1
        }
        
        var A10 = coefficient_x;
        if (exponent_x & 1) != 0 {
            A10 = (A10 << 2) + A10;
            A10 += A10;
        }
        
        let dqe = Foundation.sqrt(Double(A10))
        //dq=(double)A10;  dqe=sqrt(dq);
        let QE = UInt64(dqe)
        //printf("QE=%I64d, A10=%I64d, P=%I64d, dq=%016I64x,dqe=%016I64x\n",QE,A10,QE*QE,*(BID_UINT64*)&dq,*(BID_UINT64*)&dqe);
        if (QE * QE == A10) {
            return very_fast_get_BID64 (0, (exponent_x + EXPONENT_BIAS) >> 1, QE)
        }
        // if exponent is odd, scale coefficient by 10
        var scale = 31 - digits_x;
        var exponent_q = exponent_x - scale;
        scale += (exponent_q & 1);    // exp. bias is even
        
        let CT = bid_power10_table_128[scale]
        __mul_64x128_short(&CA, coefficient_x, CT);
        
        // 2^64
        let t_scale = Double(bitPattern: 0x43f0000000000000)
        // convert CA to DP
        let da_h = Double(CA.hi)
        let da_l = Double(CA.lo)
        let da = da_h * t_scale + da_l;
        
        let dq = Foundation.sqrt(da)
        
        var Q = UInt64(dq)
        
        // get sign(sqrt(CA)-Q)
        var R = CA.lo - Q * Q;
        R = UInt64(Int64(R) >> 63)
        let D = R + R + 1;
        
        exponent_q = (exponent_q + EXPONENT_BIAS) >> 1;
        
        pfpsf.insert(.inexact)
        
        let rmode = roundboundIndex(rnd_mode) >> 2
        if (rmode & 3) == 0 {
            // midpoint to check
            let Q2 = Q + Q + D;
            let C4 = CA.lo << 2;
            
            // get sign(-sqrt(CA)+Midpoint)
            var R2 = Q2 * Q2 - C4;
            R2 = UInt64(Int64(R2) >> 63)
            
            // adjust Q if R!=R2
            Q += (D & (R ^ R2));
        } else {
            let C4 = CA.lo;
            Q += D;
            if Int64(Q * Q - C4) > 0 {
                Q-=1
            }
            if (rnd_mode == BID_ROUNDING_UP) {
                Q+=1
            }
        }
        return fast_get_BID64(0, exponent_q, Q)
    }
    
    static func equal(_ x: UInt64, _ y: UInt64, _ pfpsf: inout Status) -> Bool {
        var non_canon_x = false, non_canon_y = false, x_is_zero = false, y_is_zero = false
        var exp_x = 0, exp_y = 0, sig_x = UInt64(), sig_y = UInt64()
        
        // NaN (CASE1)
        // if either number is NAN, the comparison is unordered,
        // rather than equal : return 0
        if (((x & MASK_NAN) == MASK_NAN) || ((y & MASK_NAN) == MASK_NAN)) {
            if ((x & MASK_SNAN) == MASK_SNAN || (y & MASK_SNAN) == MASK_SNAN) {
                pfpsf.insert(.invalidOperation)
                pfpsf.insert(.invalidOperation)    // set exception if sNaN
            }
            return false
        }
        // SIMPLE (CASE2)
        // if all the bits are the same, these numbers are equivalent.
        if (x == y) {
            return true
        }
        // INFINITY (CASE3)
        if (((x & MASK_INF) == MASK_INF) && ((y & MASK_INF) == MASK_INF)) {
            return (((x ^ y) & MASK_SIGN) != MASK_SIGN)
        }
        // ONE INFINITY (CASE3')
        if (((x & MASK_INF) == MASK_INF) || ((y & MASK_INF) == MASK_INF)) {
            return false
        }
        // if steering bits are 11 (condition will be 0), then exponent is G[0:w+1] =>
        if ((x & MASK_STEERING_BITS) == MASK_STEERING_BITS) {
            exp_x = Int(x & MASK_BINARY_EXPONENT2) >> EXPONENT_SHIFT_LARGE64;
            sig_x = (x & MASK_BINARY_SIG2) | MASK_BINARY_OR2;
            if (sig_x > MAX_NUMBER) {
                non_canon_x = true
            } else {
                non_canon_x = false
            }
        } else {
            exp_x = Int(x & MASK_BINARY_EXPONENT1) >> EXPONENT_SHIFT_SMALL64;
            sig_x = (x & MASK_BINARY_SIG1);
            non_canon_x = false
        }
        // if steering bits are 11 (condition will be 0), then exponent is G[0:w+1] =>
        if ((y & MASK_STEERING_BITS) == MASK_STEERING_BITS) {
            exp_y = Int(y & MASK_BINARY_EXPONENT2) >> EXPONENT_SHIFT_LARGE64;
            sig_y = (y & MASK_BINARY_SIG2) | MASK_BINARY_OR2
            if (sig_y > MAX_NUMBER) {
                non_canon_y = true
            } else {
                non_canon_y = false
            }
        } else {
            exp_y = Int(y & MASK_BINARY_EXPONENT1) >> EXPONENT_SHIFT_SMALL64;
            sig_y = y & MASK_BINARY_SIG1
            non_canon_y = false
        }
        // ZERO (CASE4)
        // some properties:
        // (+ZERO==-ZERO) => therefore ignore the sign
        //    (ZERO x 10^A == ZERO x 10^B) for any valid A, B =>
        //    therefore ignore the exponent field
        //    (Any non-canonical # is considered 0)
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
        if ((x ^ y) & MASK_SIGN != 0) {
            return false
        }
        // REDUNDANT REPRESENTATIONS (CASE6)
        if (exp_x > exp_y) {    // to simplify the loop below,
            swap(&exp_x, &exp_y);    // put the larger exp in y,
            swap(&sig_x, &sig_y);    // and the smaller exp in x
        }
        if (exp_y - exp_x > 15) {
            return false
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
    
    static func lessThan(_ x: UInt64, _ y: UInt64, _ pfpsf: inout Status) -> Bool {
        // NaN (CASE1)
        // if either number is NAN, the comparison is unordered : return 0
        var non_canon_x = false, non_canon_y = false, x_is_zero = false, y_is_zero = false
        var exp_x = 0, exp_y = 0, sig_x = UInt64(), sig_y = UInt64(), sig_n_prime = UInt128()
        if ((x & MASK_NAN) == MASK_NAN) || ((y & MASK_NAN) == MASK_NAN) {
            if ((x & MASK_SNAN) == MASK_SNAN || (y & MASK_SNAN) == MASK_SNAN) {
                pfpsf.insert(.invalidOperation)    // set exception if sNaN
            }
            return false
        }
        // SIMPLE (CASE2)
        // if all the bits are the same, these numbers are equal.
        if x == y {
            return false
        }
        // INFINITY (CASE3)
        if (x & MASK_INF) == MASK_INF {
            // if x==neg_inf, { res = (y == neg_inf)?0:1; return (res) }
            if (x & MASK_SIGN) == MASK_SIGN {
                // x is -inf, so it is less than y unless y is -inf
                return (((y & MASK_INF) != MASK_INF) || (y & MASK_SIGN) != MASK_SIGN);
            } else {
                // x is pos_inf, no way for it to be less than y
                return false
            }
        } else if (y & MASK_INF) == MASK_INF {
            // x is finite, so:
            //    if y is +inf, x<y
            //    if y is -inf, x>y
            return (y & MASK_SIGN) != MASK_SIGN
        }
        // if steering bits are 11 (condition will be 0), then exponent is G[0:w+1] =>
        if (x & MASK_STEERING_BITS) == MASK_STEERING_BITS {
            exp_x = Int(x & MASK_BINARY_EXPONENT2) >> EXPONENT_SHIFT_LARGE64
            sig_x = (x & MASK_BINARY_SIG2) | MASK_BINARY_OR2
            if sig_x > MAX_NUMBER {
                non_canon_x = true
            } else {
                non_canon_x = false
            }
        } else {
            exp_x = Int(x & MASK_BINARY_EXPONENT1) >> EXPONENT_SHIFT_SMALL64
            sig_x = (x & MASK_BINARY_SIG1);
            non_canon_x = false
        }
        // if steering bits are 11 (condition will be 0), then exponent is G[0:w+1] =>
        if ((y & MASK_STEERING_BITS) == MASK_STEERING_BITS) {
            exp_y = Int(y & MASK_BINARY_EXPONENT2) >> EXPONENT_SHIFT_LARGE64;
            sig_y = (y & MASK_BINARY_SIG2) | MASK_BINARY_OR2;
            if (sig_y > MAX_NUMBER) {
                non_canon_y = true
            } else {
                non_canon_y = false
            }
        } else {
            exp_y = Int(y & MASK_BINARY_EXPONENT1) >> EXPONENT_SHIFT_SMALL64;
            sig_y = (y & MASK_BINARY_SIG1);
            non_canon_y = false
        }
        // ZERO (CASE4)
        // some properties:
        // (+ZERO==-ZERO) => therefore ignore the sign, and neither number is greater
        // (ZERO x 10^A == ZERO x 10^B) for any valid A, B =>
        //  therefore ignore the exponent field
        //    (Any non-canonical # is considered 0)
        if (non_canon_x || sig_x == 0) {
            x_is_zero = true
        }
        if (non_canon_y || sig_y == 0) {
            y_is_zero = true
        }
        if (x_is_zero && y_is_zero) {
            // if both numbers are zero, they are equal
            return false
        } else if (x_is_zero) {
            // if x is zero, it is lessthan if Y is positive
            return ((y & MASK_SIGN) != MASK_SIGN);
        } else if (y_is_zero) {
            // if y is zero, X is less if it is negative
            return  ((x & MASK_SIGN) == MASK_SIGN);
        }
        // OPPOSITE SIGN (CASE5)
        // now, if the sign bits differ, x is less than if y is positive
        if (((x ^ y) & MASK_SIGN) == MASK_SIGN) {
            return  ((y & MASK_SIGN) != MASK_SIGN);
        }
        // REDUNDANT REPRESENTATIONS (CASE6)
        // if both components are either bigger or smaller,
        // it is clear what needs to be done
        if (sig_x > sig_y && exp_x >= exp_y) {
            return  ((x & MASK_SIGN) == MASK_SIGN);
        }
        if (sig_x < sig_y && exp_x <= exp_y) {
            return ((x & MASK_SIGN) != MASK_SIGN);
        }
        // if exp_x is 15 greater than exp_y, no need for compensation
        if (exp_x - exp_y > 15) {
            return  ((x & MASK_SIGN) == MASK_SIGN);
            // difference cannot be greater than 10^15
        }
        // if exp_x is 15 less than exp_y, no need for compensation
        if (exp_y - exp_x > 15) {
            return ((x & MASK_SIGN) != MASK_SIGN);
        }
        // if |exp_x - exp_y| < 15, it comes down to the compensated significand
        if (exp_x > exp_y) {    // to simplify the loop below,
            // otherwise adjust the x significand upwards
            __mul_64x64_to_128MACH(&sig_n_prime, sig_x, bid_mult_factor[exp_x - exp_y]);
            // return 0 if values are equal
            if (sig_n_prime.hi == 0 && (sig_n_prime.lo == sig_y)) {
                return false
            }
            // if postitive, return whichever significand abs is smaller
            // (converse if negative)
            return (((sig_n_prime.hi == 0) && sig_n_prime.lo < sig_y) != ((x & MASK_SIGN) == MASK_SIGN));
        }
        // adjust the y significand upwards
        __mul_64x64_to_128MACH(&sig_n_prime, sig_y, bid_mult_factor[exp_y - exp_x]);
        // return 0 if values are equal
        if (sig_n_prime.hi == 0 && (sig_n_prime.lo == sig_x)) {
            return false
        }
        // if positive, return whichever significand abs is smaller
        // (converse if negative)
        return (((sig_n_prime.hi > 0) || (sig_x < sig_n_prime.lo)) != ((x & MASK_SIGN) == MASK_SIGN));
    }
    
    //////////////////////////////////////////////////////////////////////////
    //
    //    0*10^ey + cz*10^ez,   ey<ez
    //
    //////////////////////////////////////////////////////////////////////////
    
    static func add_zero64 (_ exponent_y:Int, _ sign_z:UInt64, _ exponent_z:Int, _ coefficient_z:UInt64,
                            _ prounding_mode: Rounding, _ fpsc: inout Status) -> UInt64 {
        let diff_expon = exponent_z - exponent_y
        var coefficient_z = coefficient_z
        
        let tempx = Double(coefficient_z)
        let bin_expon = Int((tempx.bitPattern & MASK_BINARY_EXPONENT) >> 52) - BINARY_EXPONENT_BIAS
        var scale_cz = Int(bid_estimate_decimal_digits[bin_expon])
        if (coefficient_z >= bid_power10_table_128[scale_cz].lo) {
            scale_cz+=1
        }
        
        var scale_k = 16 - scale_cz;
        if (diff_expon < scale_k) {
            scale_k = diff_expon
        }
        coefficient_z *= bid_power10_table_128[scale_k].lo;
        return get_BID64 (sign_z, exponent_z - scale_k, coefficient_z, prounding_mode, &fpsc)
    }
    
    //////////////////////////////////////////////////////////////////////////
    //
    //  If coefficient_z is less than 16 digits long, normalize to 16 digits
    //
    /////////////////////////////////////////////////////////////////////////
    static func BID_normalize(_ sign_z:UInt64, _ exponent_z:Int, _ coefficient_z:UInt64, _ round_dir:UInt64, _ round_flag:UInt64,
                              _ rounding_mode: Rounding, _ fpsc: inout Status) -> UInt64 {
        let exp20 = 1_000_000_000_000_000
        var exponent_z = exponent_z, coefficient_z = coefficient_z
        var rmode = roundboundIndex(rounding_mode) >> 2 // rounding_mode;
        if (sign_z != 0 && UInt(rmode - 1) < 2) {
            rmode = 3 - rmode;
        }
        
        //--- get number of bits in the coefficients of x and y ---
        let tempx = Double(coefficient_z)
        let bin_expon = Int((tempx.bitPattern & MASK_BINARY_EXPONENT) >> 52) - BINARY_EXPONENT_BIAS
        // get number of decimal digits in the coeff_x
        var digits_z = Int(bid_estimate_decimal_digits[bin_expon])
        if coefficient_z >= bid_power10_table_128[digits_z].lo {
            digits_z+=1
        }
        
        var scale = 16 - digits_z;
        exponent_z -= scale;
        if (exponent_z < 0) {
            scale += exponent_z
            exponent_z = 0
        }
        coefficient_z *= bid_power10_table_128[scale].lo
        
        if round_flag != 0 {
            fpsc.insert(.inexact)
            if (coefficient_z < exp20) {
                fpsc.insert(.underflow)
            } else if ((coefficient_z == exp20) && exponent_z == 0
                     && (Int64(round_dir ^ sign_z) < 0) && round_flag != 0
                     && (rounding_mode == BID_ROUNDING_DOWN || rounding_mode == BID_ROUNDING_TO_ZERO)) {
                fpsc.insert(.underflow)
            }
        }
        
        if (round_flag != 0 && (rmode & 3 != 0)) {
            let D = round_dir ^ sign_z
            
            if rounding_mode == BID_ROUNDING_UP {
                if (D >= 0) {
                    coefficient_z+=1
                }
            } else {
                if D < 0 {
                    coefficient_z-=1
                }
                if coefficient_z < exp20 && exponent_z != 0 {
                    coefficient_z = MAX_NUMBER
                    exponent_z-=1
                }
            }
        }
        return get_BID64(sign_z, exponent_z, coefficient_z, rounding_mode, &fpsc)
    }
    
    static func bid64_fma(_ x: UInt64, _ y: UInt64, _ z: UInt64, _ rnd_mode: Rounding, _ pfpsf: inout Status) -> UInt64 {
        var sign_x = UInt64(), sign_y = UInt64(), coefficient_x = UInt64(), coefficient_y = UInt64()
        var sign_z = UInt64(), coefficient_z = UInt64(), exponent_x = 0, exponent_y = 0, exponent_z = 0
        var res = UInt64()
        let valid_x = unpack_BID64 (&sign_x, &exponent_x, &coefficient_x, x);
        let valid_y = unpack_BID64 (&sign_y, &exponent_y, &coefficient_y, y);
        let valid_z = unpack_BID64 (&sign_z, &exponent_z, &coefficient_z, z);
        
        // unpack arguments, check for NaN, Infinity, or 0
        if !valid_x || !valid_y || !valid_z {
            if (y & MASK_NAN) == MASK_NAN {    // y is NAN
                // if x = {0, f, inf, NaN}, y = NaN, z = {0, f, inf, NaN} then res = Q (y)
                // check first for non-canonical NaN payload
                var y = y & 0xfe03ffffffffffff    // clear G6-G12
                if (y & 0x0003ffffffffffff) > 999_999_999_999_999 {
                    y = y & 0xfe00000000000000    // clear G6-G12 and the payload bits
                }
                if ((y & MASK_SNAN) == MASK_SNAN) {    // y is SNAN
                    // set invalid flag
                    pfpsf.insert(.invalidOperation)
                    // return quiet (y)
                    res = y & QUIET_MASK64
                } else {    // y is QNaN
                    // return y
                    res = y
                    // if z = SNaN or x = SNaN signal invalid exception
                    if ((z & MASK_SNAN) == MASK_SNAN || (x & MASK_SNAN) == MASK_SNAN) {
                        // set invalid flag
                        pfpsf.insert(.invalidOperation)
                    }
                }
                return res
            } else if (z & MASK_NAN) == MASK_NAN {    // z is NAN
                // if x = {0, f, inf, NaN}, y = {0, f, inf}, z = NaN then res = Q (z)
                // check first for non-canonical NaN payload
                var z = z & 0xfe03ffffffffffff;    // clear G6-G12
                if (z & 0x0003ffffffffffff) > 999_999_999_999_999 {
                    z = z & 0xfe00000000000000    // clear G6-G12 and the payload bits
                }
                if ((z & MASK_SNAN) == MASK_SNAN) {    // z is SNAN
                    // set invalid flag
                    pfpsf.insert(.invalidOperation)
                    // return quiet (z)
                    res = z & QUIET_MASK64
                } else {    // z is QNaN
                    // return z
                    res = z
                    // if x = SNaN signal invalid exception
                    if (x & MASK_SNAN) == MASK_SNAN {
                        // set invalid flag
                        pfpsf.insert(.invalidOperation)
                    }
                }
                return res
            } else if (x & MASK_NAN) == MASK_NAN {    // x is NAN
                // if x = NaN, y = {0, f, inf}, z = {0, f, inf} then res = Q (x)
                // check first for non-canonical NaN payload
                var x = x & 0xfe03ffffffffffff    // clear G6-G12
                if (x & 0x0003ffffffffffff) > 999_999_999_999_999 {
                    x = x & 0xfe00000000000000    // clear G6-G12 and the payload bits
                }
                if (x & MASK_SNAN) == MASK_SNAN {    // x is SNAN
                    // set invalid flag
                    pfpsf.insert(.invalidOperation)
                    // return quiet (x)
                    res = x & QUIET_MASK64
                } else {    // x is QNaN
                    // return x
                    res = x    // clear out G[6]-G[16]
                }
                return res
            }
            
            if !valid_x {
                // x is Inf. or 0
                // x is Infinity?
                if (x & MASK_INF) == MASK_INF {
                    // check if y is 0
                    if coefficient_y == 0 {
                        // y==0, return NaN
                        if (z & SNAN_MASK64) != MASK_ANY_INF {
                            pfpsf.insert(.invalidOperation)
                        }
                        return MASK_ANY_INF
                    }
                    // test if z is Inf of oposite sign
                    if ((z & MASK_ANY_INF) == MASK_INF) && (((x ^ y) ^ z) & MASK_SIGN) != 0 {
                        // return NaN
                        pfpsf.insert(.invalidOperation)
                        return MASK_ANY_INF
                    }
                    // otherwise return +/-Inf
                    return ((x ^ y) & MASK_SIGN) | MASK_INF
                }
                // x is 0
                if ((y & MASK_INF) != MASK_INF) && ((z & MASK_INF) != MASK_INF) {
                    
                    if coefficient_z != 0 {
                        exponent_y = exponent_x - EXPONENT_BIAS + exponent_y
                        
                        sign_z = z & MASK_SIGN
                        
                        if (exponent_y >= exponent_z) {
                            return (z);
                        }
                        return add_zero64 (exponent_y, sign_z, exponent_z, coefficient_z, rnd_mode, &pfpsf)
                    }
                }
            }
            if !valid_y {
                // y is Inf. or 0
                
                // y is Infinity?
                if ((y & MASK_INF) == MASK_INF) {
                    // check if x is 0
                    if coefficient_x == 0 {
                        // y==0, return NaN
                        pfpsf.insert(.invalidOperation)
                        return (MASK_ANY_INF);
                    }
                    // test if z is Inf of oposite sign
                    if (((z & MASK_ANY_INF) == MASK_INF)
                        && (((x ^ y) ^ z) & MASK_SIGN) != 0) {
                        pfpsf.insert(.invalidOperation)
                        // return NaN
                        return (MASK_ANY_INF);
                    }
                    // otherwise return +/-Inf
                    return (((x ^ y) & MASK_SIGN) | MASK_INF);
                }
                // y is 0
                if (((z & MASK_INF) != MASK_INF)) {
                    
                    if (coefficient_z != 0) {
                        exponent_y += exponent_x - EXPONENT_BIAS;
                        
                        sign_z = z & MASK_SIGN;
                        
                        if exponent_y >= exponent_z {
                            return z
                        }
                        return add_zero64 (exponent_y, sign_z, exponent_z, coefficient_z, rnd_mode, &pfpsf)
                    }
                }
            }
            
            if !valid_z {
                // y is Inf. or 0
                
                // test if y is NaN/Inf
                if (z & MASK_INF) == MASK_INF {
                    return (coefficient_z & QUIET_MASK64)
                }
                // z is 0, return x*y
                if (coefficient_x == 0) || (coefficient_y == 0) {
                    //0+/-0
                    exponent_x += exponent_y - EXPONENT_BIAS
                    if (exponent_x > MAX_EXPON) {
                        exponent_x = MAX_EXPON
                    } else if (exponent_x < 0) {
                        exponent_x = 0;
                    }
                    if (exponent_x <= exponent_z) {
                        res = UInt64(exponent_x) << EXPONENT_SHIFT_SMALL64;
                    } else {
                        res = UInt64(exponent_z) << EXPONENT_SHIFT_SMALL64;
                    }
                    if ((sign_x ^ sign_y) == sign_z) {
                        res |= sign_z;
                    } else if (rnd_mode == BID_ROUNDING_DOWN) {
                        res |= MASK_SIGN;
                    }
                    return (res);
                }
            }
        }
        
        /* get binary coefficients of x and y */
        
        //--- get number of bits in the coefficients of x and y ---
        // version 2 (original)
        let tempx = Double(coefficient_x)
        let bin_expon_cx = Int((tempx.bitPattern & MASK_BINARY_EXPONENT) >> 52);
        
        let tempy = Double(coefficient_y)
        let bin_expon_cy = Int((tempy.bitPattern & MASK_BINARY_EXPONENT) >> 52);
        
        // magnitude estimate for coefficient_x*coefficient_y is
        //        2^(unbiased_bin_expon_cx + unbiased_bin_expon_cx)
        var bin_expon_product = bin_expon_cx + bin_expon_cy
        
        // check if coefficient_x*coefficient_y<2^(10*k+3)
        // equivalent to unbiased_bin_expon_cx + unbiased_bin_expon_cx < 10*k+1
        var P = UInt128(), extra_digits = 0, final_exponent = 0, bp = 0
        if (bin_expon_product < UPPER_EXPON_LIMIT + 2 * BINARY_EXPONENT_BIAS) {
            //  easy multiply
            let C64 = coefficient_x * coefficient_y
            let final_exponent = exponent_x + exponent_y - EXPONENT_BIAS
            if (final_exponent > 0) || (coefficient_z == 0) {
                return bid_get_add64(sign_x ^ sign_y, final_exponent, C64, sign_z, exponent_z,
                                     coefficient_z, rnd_mode, &pfpsf);
            } else {
                P.lo = C64;
                P.hi = 0;
                extra_digits = 0;
            }
        } else {
            if coefficient_z == 0 {
                return mul(x, y, rnd_mode, &pfpsf)
            }
            // get 128-bit product: coefficient_x*coefficient_y
            __mul_64x64_to_128(&P, coefficient_x, coefficient_y);
            
            // tighten binary range of P:  leading bit is 2^bp
            // unbiased_bin_expon_product <= bp <= unbiased_bin_expon_product+1
            bin_expon_product -= 2 * BINARY_EXPONENT_BIAS
            __tight_bin_range_128(&bp, &P, bin_expon_product)
            
            // get number of decimal digits in the product
            var digits_p = Int(bid_estimate_decimal_digits[bp])
            if !__unsigned_compare_gt_128 (bid_power10_table_128[digits_p], P) {
                digits_p+=1    // if bid_power10_table_128[digits_p] <= P
            }
            
            // determine number of decimal digits to be rounded out
            extra_digits = digits_p - MAX_DIGITS
            final_exponent = exponent_x + exponent_y + extra_digits - EXPONENT_BIAS
        }
        
        if UInt(final_exponent) >= 3 * 256 {
            if (final_exponent < 0) {
                //--- get number of bits in the coefficients of z  ---
                let tempx = Double(coefficient_z)
                let bin_expon_cx = Int((tempx.bitPattern & MASK_BINARY_EXPONENT) >> 52) - BINARY_EXPONENT_BIAS
                // get number of decimal digits in the coeff_x
                var digits_z = Int(bid_estimate_decimal_digits[bin_expon_cx])
                if (coefficient_z >= bid_power10_table_128[digits_z].lo) {
                    digits_z+=1
                }
                // underflow
                if (final_exponent + 16 < 0) || (exponent_z + digits_z > 33 + final_exponent) {
                    return BID_normalize(sign_z, exponent_z, coefficient_z, sign_x ^ sign_y, 1, rnd_mode, &pfpsf)
                }
                
                var ez = exponent_z + digits_z - 16;
                if (ez < 0) {
                    ez = 0
                }
                var scale_z = exponent_z - ez, remainder_y = UInt64()
                coefficient_z *= bid_power10_table_128[scale_z].lo
                let ey = final_exponent - extra_digits
                extra_digits = ez - ey
                
                if extra_digits > 17 {
                    let CYh = __truncate(P, 16)
                    // get remainder
                    var T = bid_power10_table_128[16].lo, CY0L = UInt64()
                    __mul_64x64_to_64(&CY0L, CYh, T)
                    remainder_y = P.lo - CY0L
                    
                    extra_digits -= 16
                    P.lo = CYh
                    P.hi = 0
                } else {
                    remainder_y = 0
                }
                
                // align coeff_x, CYh
                var CZ = UInt128(), CT = UInt128()
                __mul_64x64_to_128(&CZ, coefficient_z, bid_power10_table_128[extra_digits].lo)
                
                if (sign_z == (sign_y ^ sign_x)) {
                    __add_128_128(&CT, CZ, P);
                    if (__unsigned_compare_ge_128(CT, bid_power10_table_128[16 + extra_digits])) {
                        extra_digits+=1
                        ez+=1
                    }
                } else {
                    if (remainder_y != 0 && (__unsigned_compare_ge_128 (CZ, P))) {
                        P.lo+=1
                        if P.lo == 0 {
                            P.hi+=1
                        }
                    }
                    __sub_128_128(&CT, CZ, P)
                    if Int64(CT.hi) < 0 {
                        sign_z = sign_y ^ sign_x
                        CT.lo = 0 &- CT.lo
                        CT.hi = 0 &- CT.hi
                        if CT.lo != 0 {
                            CT.hi-=1
                        }
                    } else if (CT.hi|CT.lo) == 0 {
                        sign_z = (rnd_mode != BID_ROUNDING_DOWN) ? 0 : MASK_SIGN
                    }
                    if ez != 0 && __unsigned_compare_gt_128(bid_power10_table_128[15 + extra_digits], CT) {
                        extra_digits-=1
                        ez-=1
                    }
                }
                
                var uf_status = Status.clearFlags
                if ez == 0 && __unsigned_compare_gt_128(bid_power10_table_128[extra_digits + 15], CT) {
                    var rmode = roundboundIndex(rnd_mode) >> 2
                    if (sign_z != 0 && UInt(rmode - 1) < 2) {
                        rmode = 3 - rmode;
                    }
                    var PU = bid_power10_table_128[extra_digits + 15]
                    PU.lo-=1
                    if __unsigned_compare_gt_128 (PU, CT) || (rnd_mode == BID_ROUNDING_DOWN) || (rnd_mode == BID_ROUNDING_TO_ZERO) {
                        uf_status.insert(.underflow)
                    } else if (extra_digits < 2) {
                        if rnd_mode == BID_ROUNDING_UP {
                            if extra_digits == 0 {
                                uf_status.insert(.underflow)
                            } else {
                                if (remainder_y != 0 && (sign_z != (sign_y ^ sign_x))) {
                                    remainder_y = bid_power10_table_128[16].lo - remainder_y;
                                }
                                
                                if (bid_power10_table_128[15].lo > remainder_y) {
                                    uf_status.insert(.underflow)
                                }
                            }
                        } else {  // RN or RN_away
                            if remainder_y != 0 && (sign_z != (sign_y ^ sign_x)) {
                                remainder_y = bid_power10_table_128[16].lo - remainder_y
                            }
                            
                            if extra_digits == 0 {
                                remainder_y += bid_round_const_table[rmode][15]
                                if remainder_y < bid_power10_table_128[16].lo {
                                    uf_status.insert(.underflow)
                                }
                            } else {
                                if remainder_y < bid_round_const_table[rmode][16] {
                                    uf_status.insert(.underflow)
                                }
                            }
                        }
                    }
                }
                return __bid_full_round64_remainder(sign_z, ez - extra_digits, CT,
                                                    extra_digits, remainder_y, rnd_mode, &pfpsf, uf_status)
            } else {
                if (sign_z == (sign_x ^ sign_y)) || (final_exponent > 3 * 256 + 15) {
                    return fast_get_BID64_check_OF (sign_x ^ sign_y, final_exponent, 1_000_000_000_000_000, rnd_mode, &pfpsf)
                }
            }
        }
        
        
        if (extra_digits > 0) {
            return bid_get_add128 (sign_z, exponent_z, coefficient_z, sign_x ^ sign_y,
                                   final_exponent, P, extra_digits, rnd_mode, &pfpsf);
        } else {
            // go to convert_format and exit
            let C64 = P.lo
            return bid_get_add64 (sign_x ^ sign_y, exponent_x + exponent_y - EXPONENT_BIAS, C64,
                                  sign_z, exponent_z, coefficient_z, rnd_mode, &pfpsf)
        }
    }
    
    ////////////////////////////////////////////////////////////////////////////////
    //
    // add 64-bit coefficient to 128-bit coefficient, return result in BID64 format
    //
    ////////////////////////////////////////////////////////////////////////////////
    static func bid_get_add128 (_ sign_x:UInt64, _ exponent_x:Int, _ coefficient_x:UInt64,
                                _ sign_y:UInt64, _ final_exponent_y:Int, _ CY:UInt128, _ extra_digits:Int,
                                _ rounding_mode:Rounding, _ fpsc: inout Status) -> UInt64 {
        var CY_L=UInt128(), CX=UInt128(), FS=UInt128(), F=UInt128(), CT=UInt128(), ST=UInt128(), T2=UInt128()
        var CYh, CY0L, T, S, coefficient_y, remainder_y:UInt64
        var D = 0, coefficient_x = coefficient_x, exponent_x = exponent_x, extra_digits = extra_digits
        var sign_y = sign_y, CY = CY, final_exponent_y = final_exponent_y, sign_x = sign_x
        
        // CY has more than 16 decimal digits
        let exponent_y = final_exponent_y - extra_digits;
        
        if (exponent_x > exponent_y) {
            // normalize x
            //--- get number of bits in the coefficients of x and y ---
            let tempx = Double(coefficient_x)
            let bin_expon_cx = Int((tempx.bitPattern & MASK_BINARY_EXPONENT) >> 52) - BINARY_EXPONENT_BIAS
            // get number of decimal digits in the coeff_x
            var digits_x = Int(bid_estimate_decimal_digits[bin_expon_cx])
            if (coefficient_x >= bid_power10_table_128[digits_x].lo) {
                digits_x+=1
            }
            
            var extra_dx = 16 - digits_x;
            coefficient_x *= bid_power10_table_128[extra_dx].lo;
            if ((sign_x ^ sign_y != 0) && (coefficient_x == 1_000_000_000_000_000)) {
                extra_dx+=1
                coefficient_x = MAX_NUMBERP1
            }
            exponent_x -= extra_dx;
            
            if (exponent_x > exponent_y) {
                
                // exponent_x > exponent_y
                let diff_dec_expon = exponent_x - exponent_y
                
                if (exponent_x <= final_exponent_y + 1) {
                    __mul_64x64_to_128 (&CX, coefficient_x, bid_power10_table_128[diff_dec_expon].lo);
                    
                    if (sign_x == sign_y) {
                        __add_128_128 (&CT, CY, CX);
                        if ((exponent_x > final_exponent_y) /*&& (final_exponent_y>0) */ ) {
                            extra_digits+=1
                        }
                        if (__unsigned_compare_ge_128(CT, bid_power10_table_128[16 + extra_digits])) {
                            extra_digits+=1
                        }
                    } else {
                        __sub_128_128(&CT, CY, CX);
                        if (Int64(CT.hi) < 0) {
                            CT.lo = 0 &- CT.lo;
                            CT.hi = 0 &- CT.hi;
                            if CT.lo != 0 {
                                CT.hi-=1
                            }
                            sign_y = sign_x;
                        } else if ((CT.hi | CT.lo) == 0) {
                            sign_y = (rounding_mode != BID_ROUNDING_DOWN) ? 0 : MASK_SIGN
                        }
                        if ((exponent_x + 1 >= final_exponent_y) /*&& (final_exponent_y>=0) */ ) {
                            extra_digits = Decimal128.__get_dec_digits64(CT) - 16;
                            if (extra_digits <= 0) {
                                if (CT.lo == 0 && rounding_mode == BID_ROUNDING_DOWN) {
                                    sign_y = MASK_SIGN;
                                }
                                return get_BID64 (sign_y, exponent_y, CT.lo, rounding_mode, &fpsc);
                            }
                        } else {
                            if (__unsigned_compare_gt_128(bid_power10_table_128[15 + extra_digits], CT)) {
                                extra_digits-=1
                            }
                        }
                    }
                    
                    return __bid_full_round64(sign_y, exponent_y, CT, extra_digits, rounding_mode, &fpsc);
                }
                // diff_dec2+extra_digits is the number of digits to eliminate from
                //                           argument CY
                var diff_dec2 = exponent_x - final_exponent_y
                
                if (diff_dec2 >= 17) {
                    let rmode = roundboundIndex(rounding_mode) >> 2
                    if (rmode & 3) != 0 {
                        switch rounding_mode {
                            case BID_ROUNDING_UP:
                                if sign_y == 0 {
                                    D = Int((sign_x ^ sign_y)) >> 63
                                    D = D + D + 1;
                                    coefficient_x += UInt64(D)
                                }
                            case BID_ROUNDING_DOWN:
                                if sign_y != 0 {
                                    D = Int((sign_x ^ sign_y)) >> 63
                                    D = D + D + 1;
                                    coefficient_x += UInt64(D)
                                }
                            case BID_ROUNDING_TO_ZERO:
                                if (sign_y != sign_x) {
                                    D = 0 - 1;
                                    coefficient_x += UInt64(D)
                                }
                            default: break
                        }
                        if (coefficient_x < 1_000_000_000_000_000) {
                            coefficient_x -= UInt64(D)
                            coefficient_x = UInt64(D) + (coefficient_x << 1) + (coefficient_x << 3)
                            exponent_x-=1
                        }
                    }
                    if (CY.hi | CY.lo) != 0 {
                        fpsc.insert(.inexact)
                    }
                    return get_BID64 (sign_x, exponent_x, coefficient_x, rounding_mode, &fpsc)
                }
                // here exponent_x <= 16+final_exponent_y
                
                // truncate CY to 16 dec. digits
                CYh = __truncate (CY, extra_digits);
                
                // get remainder
                T = bid_power10_table_128[extra_digits].lo
                CY0L = 0
                __mul_64x64_to_64(&CY0L, CYh, T);
                
                remainder_y = CY.lo - CY0L;
                
                // align coeff_x, CYh
                __mul_64x64_to_128(&CX, coefficient_x, bid_power10_table_128[diff_dec2].lo);
                
                if (sign_x == sign_y) {
                    __add_128_64(&CT, CX, CYh);
                    if (__unsigned_compare_ge_128(CT, bid_power10_table_128[16 + diff_dec2])) {
                        diff_dec2+=1
                    }
                } else {
                    if remainder_y != 0 {
                        CYh+=1
                    }
                    __sub_128_64(&CT, CX, CYh)
                    if __unsigned_compare_gt_128(bid_power10_table_128[15 + diff_dec2], CT) {
                        diff_dec2-=1
                    }
                }
                
                return __bid_full_round64_remainder (sign_x, final_exponent_y, CT, diff_dec2, remainder_y,
                                                     rounding_mode, &fpsc, Status.clearFlags);
            }
        }
        // Here (exponent_x <= exponent_y)
        let diff_dec_expon = exponent_y - exponent_x;
        
        if (diff_dec_expon > MAX_DIGITS) {
            let rmode = roundboundIndex(rounding_mode) >> 2 // rounding_mode;
            
            if ((sign_x ^ sign_y) != 0) {
                if CY.lo == 0 {
                    CY.hi-=1
                }
                    CY.lo-=1
                    if (__unsigned_compare_gt_128(bid_power10_table_128[15 + extra_digits], CY)) {
                    if (rmode & 3) != 0 {
                        extra_digits-=1
                        final_exponent_y-=1
                    } else {
                        CY.lo = 1_000_000_000_000_000
                        CY.hi = 0
                        extra_digits = 0
                    }
                }
            }
            CY = __scale128_x10(CY)
            extra_digits+=1
            CY.lo |= 1
            return __bid_simple_round64_sticky(sign_y, final_exponent_y, CY, extra_digits, rounding_mode, &fpsc)
        }
        // apply sign to coeff_x
        sign_x ^= sign_y
        sign_x = UInt64(Int64(sign_x) >> 63)
        CX.lo = (coefficient_x + sign_x) ^ sign_x
        CX.hi = sign_x
        
        // check whether CY (rounded to 16 digits) and CX have
        //                     any digits in the same position
        let diff_dec2 = final_exponent_y - exponent_x
        
        if (diff_dec2 <= 17) {
            // align CY to 10^ex
            S = bid_power10_table_128[diff_dec_expon].lo
            __mul_64x128_short(&CY_L, S, CY)
            
            __add_128_128(&ST, CY_L, CX);
            let extra_digits2 = Decimal128.__get_dec_digits64(ST) - 16
            return __bid_full_round64(sign_y, exponent_x, ST, extra_digits2, rounding_mode, &fpsc)
        }
        // truncate CY to 16 dec. digits
        CYh = __truncate (CY, extra_digits);
        
        // get remainder
        T = bid_power10_table_128[extra_digits].lo
        CY0L = 0
        __mul_64x64_to_64(&CY0L, CYh, T)
        
        coefficient_y = CY.lo - CY0L;
        // add rounding constant
        var rmode = roundboundIndex(rounding_mode) >> 2  //rounding_mode;
        if (sign_y != 0 && UInt(rmode - 1) < 2) {
            rmode = 3 - rmode;
        }
        if ((rmode & 3) == 0) {   //BID_ROUNDING_TO_NEAREST
            coefficient_y += bid_round_const_table[rmode][extra_digits]
        }
        // align coefficient_y,  coefficient_x
        S = bid_power10_table_128[diff_dec_expon].lo;
        __mul_64x64_to_128(&F, coefficient_y, S);
        
        // fraction
        __add_128_128(&FS, F, CX)
        
        if (rmode == 0) {   //BID_ROUNDING_TO_NEAREST
            // rounding code, here RN_EVEN
            // 10^(extra_digits+diff_dec_expon)
            T2 = bid_power10_table_128[diff_dec_expon + extra_digits];
            if (__unsigned_compare_gt_128(FS, T2) || ((CYh & 1) != 0 && __test_equal_128(FS, T2))) {
                CYh+=1
                __sub_128_128(&FS, FS, T2)
            }
        }
        if (rmode == 4) {    //BID_ROUNDING_TO_NEAREST
            // rounding code, here RN_AWAY
            // 10^(extra_digits+diff_dec_expon)
            T2 = bid_power10_table_128[diff_dec_expon + extra_digits];
            if (__unsigned_compare_ge_128 (FS, T2)) {
                CYh+=1
                __sub_128_128(&FS, FS, T2);
            }
        }
        switch (rounding_mode) {
            case BID_ROUNDING_DOWN, BID_ROUNDING_TO_ZERO:
                if Int64(FS.hi) < 0 {
                    CYh-=1
                    if CYh < 1_000_000_000_000_000 {
                        CYh = MAX_NUMBER
                        final_exponent_y-=1
                    }
                } else {
                    T2 = bid_power10_table_128[diff_dec_expon + extra_digits];
                    if (__unsigned_compare_ge_128(FS, T2)) {
                        CYh+=1
                        __sub_128_128(&FS, FS, T2);
                    }
                }
            case BID_ROUNDING_UP:
                if Int64(FS.hi) < 0 {
                    break;
                }
                T2 = bid_power10_table_128[diff_dec_expon + extra_digits];
                if (__unsigned_compare_gt_128(FS, T2)) {
                    CYh += 2;
                    __sub_128_128(&FS, FS, T2);
                } else if ((FS.hi == T2.hi) && (FS.lo == T2.lo)) {
                    CYh+=1
                    FS.hi = 0; FS.lo = 0
                } else if (FS.hi | FS.lo) != 0 {
                    CYh+=1
                }
            default: break
        }
        
        var status = Status.inexact // BID_INEXACT_EXCEPTION;
        if (rmode & 3) == 0 {
            // RN modes
            if ((FS.hi == bid_round_const_table_128[0][diff_dec_expon + extra_digits].hi)
                && (FS.lo == bid_round_const_table_128[0][diff_dec_expon + extra_digits].lo)) {
                status = []
            }
        } else if (FS.hi == 0 && FS.lo == 0) {
            status = []
        }
        
        fpsc.formUnion(status)
        return get_BID64 (sign_y, final_exponent_y, CYh, rounding_mode, &fpsc);
    }
    
    ///////////////////////////////////////////////////////////////////////
    //
    // bid_get_add64() is essentially the same as bid_add(), except that
    //             the arguments are unpacked
    //
    //////////////////////////////////////////////////////////////////////
    static func bid_get_add64 (_ sign_x:UInt64, _ exponent_x:Int, _ coefficient_x:UInt64,
                               _ sign_y:UInt64, _ exponent_y:Int, _ coefficient_y:UInt64,
                               _ rounding_mode:Rounding, _ fpsc: inout Status) -> UInt64 {
        // sort arguments by exponent
        let Ten15 = 1_000_000_000_000_000
        var sign_a, sign_b, coefficient_a, coefficient_b:UInt64
        var C64_new = UInt64(), C64 = UInt64(), carry = UInt64(), sign_s = UInt64()
        var exponent_a, exponent_b:Int
        var rmode = 0, amount = 0, extra_digits = 0
        var CA = UInt128(), CT = UInt128(), CT_new = UInt128()
        if (exponent_x <= exponent_y) {
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
        
        /* get binary coefficients of x and y */
        
        //--- get number of bits in the coefficients of x and y ---
        var tempx = Double(coefficient_a)
        var bin_expon_ca = Int((tempx.bitPattern & MASK_BINARY_EXPONENT) >> 52) - BINARY_EXPONENT_BIAS
        
        if coefficient_a == 0 {
            return get_BID64 (sign_b, exponent_b, coefficient_b, rounding_mode, &fpsc)
        }
        
        if diff_dec_expon > MAX_DIGITS {
            // normalize a to a 16-digit coefficient
            
            var scale_ca = Int(bid_estimate_decimal_digits[bin_expon_ca])
            if coefficient_a >= bid_power10_table_128[scale_ca].lo {
                scale_ca+=1
            }
            
            let scale_k = 16 - scale_ca
            
            coefficient_a *= bid_power10_table_128[scale_k].lo
            
            diff_dec_expon -= scale_k
            exponent_a -= scale_k
            
            /* get binary coefficients of x and y */
            
            //--- get number of bits in the coefficients of x and y ---
            tempx = Double(coefficient_a)
            bin_expon_ca = Int((tempx.bitPattern & MASK_BINARY_EXPONENT) >> 52) - BINARY_EXPONENT_BIAS;
            
            if (diff_dec_expon > MAX_DIGITS) {
                if coefficient_b != 0 {
                    fpsc.insert(.inexact)
                }
                
                let rmode = roundboundIndex(rounding_mode) >> 2
                if ((rmode & 3 != 0) && coefficient_b != 0) {   // not BID_ROUNDING_TO_NEAREST
                    switch (rounding_mode) {
                        case BID_ROUNDING_DOWN:
                            if sign_b != 0 {
                                coefficient_a -= UInt64((Int64(sign_a) >> 63) | 1)
                                if (coefficient_a < Ten15) {
                                    exponent_a-=1
                                    coefficient_a = MAX_NUMBER
                                } else if coefficient_a >= MAX_NUMBERP1 {
                                    exponent_a+=1
                                    coefficient_a = UInt64(Ten15)
                                }
                            }
                        case BID_ROUNDING_UP:
                            if sign_b == 0 {
                                coefficient_a += UInt64((Int64(sign_a) >> 63) | 1)
                                if coefficient_a < Ten15 {
                                    exponent_a-=1
                                    coefficient_a = MAX_NUMBER
                                } else if coefficient_a >= MAX_NUMBERP1 {
                                    exponent_a+=1
                                    coefficient_a = UInt64(Ten15)
                                }
                            }
                        default:    // RZ
                            if sign_a != sign_b {
                                coefficient_a-=1
                                if coefficient_a < Ten15 {
                                    exponent_a-=1
                                    coefficient_a = MAX_NUMBER
                                }
                            }
                    }
                } else if ((coefficient_a == Ten15)
                           && (diff_dec_expon == MAX_DIGITS + 1) && ((sign_a ^ sign_b) != 0)
                           && (coefficient_b > 5_000_000_000_000_000)) {
                    coefficient_a = MAX_NUMBER
                    exponent_a-=1
                }
                return get_BID64 (sign_a, exponent_a, coefficient_a, rounding_mode, &fpsc)
            }
        }
        
        // test whether coefficient_a*10^(exponent_a-exponent_b)  may exceed 2^62
        if (bin_expon_ca + Int(bid_estimate_bin_expon[diff_dec_expon]) < 60) {
            // coefficient_a*10^(exponent_a-exponent_b)<2^63
            
            // multiply by 10^(exponent_a-exponent_b)
            coefficient_a *= bid_power10_table_128[diff_dec_expon].lo;
            
            // sign mask
            sign_b = UInt64(Int64(sign_b) >> 63)
            // apply sign to coeff. of b
            coefficient_b = (coefficient_b + sign_b) ^ sign_b;
            
            // apply sign to coefficient a
            sign_a = UInt64(Int64(sign_a) >> 63)
            coefficient_a = (coefficient_a + sign_a) ^ sign_a;
            
            coefficient_a += coefficient_b;
            // get sign
            var sign_s = UInt64(Int64(coefficient_a) >> 63)
            coefficient_a = (coefficient_a + sign_s) ^ sign_s;
            sign_s &= MASK_SIGN
            
            // coefficient_a < 10^16 ?
            if (coefficient_a < bid_power10_table_128[MAX_DIGITS].lo) {
                if (rounding_mode == BID_ROUNDING_DOWN && (coefficient_a == 0) && sign_a != sign_b) {
                    sign_s = MASK_SIGN;
                }
                return get_BID64 (sign_s, exponent_b, coefficient_a, rounding_mode, &fpsc);
            }
            // otherwise rounding is necessary
            
            // already know coefficient_a<10^19
            // coefficient_a < 10^17 ?
            if coefficient_a < bid_power10_table_128[17].lo {
                extra_digits = 1
            } else if coefficient_a < bid_power10_table_128[18].lo {
                extra_digits = 2
            } else {
                extra_digits = 3
            }
            
            var rmode = roundboundIndex(rounding_mode) >> 2
            if sign_s != 0 && UInt(rmode - 1) < 2 {
                rmode = 3 - rmode
            }
            
            coefficient_a += bid_round_const_table[rmode][extra_digits]
            
            // get P*(2^M[extra_digits])/10^extra_digits
            __mul_64x64_to_128(&CT, coefficient_a, bid_reciprocals10_64[extra_digits])
            
            // now get P/10^extra_digits: shift C64 right by M[extra_digits]-128
            let amount = bid_short_recip_scale[extra_digits]
            C64 = CT.hi >> amount;
            
        } else {
            // coefficient_a*10^(exponent_a-exponent_b) is large
            let sign_s = sign_a
            
            rmode = roundboundIndex(rounding_mode) >> 2
            if ((sign_s != 0) && UInt(rmode - 1) < 2) {
                rmode = 3 - rmode
            }
            
            // check whether we can take faster path
            var scale_ca = Int(bid_estimate_decimal_digits[bin_expon_ca])
            
            var sign_ab = sign_a ^ sign_b;
            sign_ab = UInt64(Int64(sign_ab) >> 63)
            
            // T1 = 10^(16-diff_dec_expon)
            let T1 = bid_power10_table_128[16 - diff_dec_expon].lo
            
            // get number of digits in coefficient_a
            //P_ca = bid_power10_table_128[scale_ca].lo;
            //P_ca_m1 = bid_power10_table_128[scale_ca-1].lo;
            if (coefficient_a >= bid_power10_table_128[scale_ca].lo) {
                scale_ca+=1
                //P_ca_m1 = P_ca;
                //P_ca = bid_power10_table_128[scale_ca].lo;
            }
            
            let scale_k = 16 - scale_ca;
            
            // apply sign
            //Ts = (T1 + sign_ab) ^ sign_ab;
            
            // test range of ca
            //X = coefficient_a + Ts - P_ca_m1;
            
            // addition
            var saved_ca = coefficient_a - T1;
            coefficient_a = UInt64(Int64(saved_ca) * Int64(bid_power10_table_128[scale_k].lo))
            extra_digits = diff_dec_expon - scale_k
            
            // apply sign
            var saved_cb = (coefficient_b + sign_ab) ^ sign_ab
            // add 10^16 and rounding constant
            coefficient_b = saved_cb + MAX_NUMBERP1 + bid_round_const_table[rmode][extra_digits];
            
            // get P*(2^M[extra_digits])/10^extra_digits
            __mul_64x64_to_128(&CT, coefficient_b, bid_reciprocals10_64[extra_digits]);
            
            // now get P/10^extra_digits: shift C64 right by M[extra_digits]-128
            amount = Int(bid_short_recip_scale[extra_digits])
            var C0_64 = CT.hi >> amount
            
            // result coefficient
            C64 = C0_64 + coefficient_a
            // filter out difficult (corner) cases
            // the following test is equivalent to
            // ( (initial_coefficient_a + Ts) < P_ca &&
            //     (initial_coefficient_a + Ts) > P_ca_m1 ),
            // which ensures the number of digits in coefficient_a does not change
            // after adding (the appropriately scaled and rounded) coefficient_b
            if C64 - UInt64(Ten15) - 1 > 9_000_000_000_000_000 - 2 {
                if (C64 >= MAX_NUMBERP1) {
                    // result has more than 16 digits
                    if scale_k == 0 {
                        // must divide coeff_a by 10
                        saved_ca = saved_ca + T1;
                        __mul_64x64_to_128(&CA, saved_ca, 0x3333333333333334)
                        //reciprocals10_64[1]);
                        coefficient_a = CA.hi >> 1
                        let rem_a = saved_ca - (coefficient_a << 3) - (coefficient_a << 1)
                        coefficient_a = coefficient_a - T1
                        
                        saved_cb += /*90000000000000000 */ +rem_a * bid_power10_table_128[diff_dec_expon].lo
                    } else {
                        coefficient_a = UInt64(Int64(saved_ca - T1 - (T1 << 3)) * Int64(bid_power10_table_128[scale_k - 1].lo))
                    }
                    
                    extra_digits+=1
                    coefficient_b = saved_cb + 100_000_000_000_000_000 + bid_round_const_table[rmode][extra_digits]
                    
                    // get P*(2^M[extra_digits])/10^extra_digits
                    __mul_64x64_to_128(&CT, coefficient_b, bid_reciprocals10_64[extra_digits])
                    
                    // now get P/10^extra_digits: shift C64 right by M[extra_digits]-128
                    amount = Int(bid_short_recip_scale[extra_digits])
                    C0_64 = CT.hi >> amount
                    
                    // result coefficient
                    C64 = C0_64 + coefficient_a;
                } else if C64 <= Ten15 {
                    // less than 16 digits in result
                    coefficient_a = UInt64(Int64(saved_ca) * Int64(bid_power10_table_128[scale_k + 1].lo))
                    //extra_digits -=1
                    exponent_b-=1
                    coefficient_b = (saved_cb << 3) + (saved_cb << 1) + 100_000_000_000_000_000 +
                                    bid_round_const_table[rmode][extra_digits]
                    
                    // get P*(2^M[extra_digits])/10^extra_digits
                    __mul_64x64_to_128(&CT_new, coefficient_b, bid_reciprocals10_64[extra_digits]);
                    
                    // now get P/10^extra_digits: shift C64 right by M[extra_digits]-128
                    amount = Int(bid_short_recip_scale[extra_digits])
                    C0_64 = CT_new.hi >> amount;
                    
                    // result coefficient
                    C64_new = C0_64 + coefficient_a
                    if C64_new < MAX_NUMBERP1 {
                        C64 = C64_new
                        CT = CT_new
                    } else {
                        exponent_b+=1
                    }
                }
            }
        }
        
        if (rmode == 0) {
            if (C64 & 1) != 0 {
                // check whether fractional part of initial_P/10^extra_digits
                // is exactly .5
                // this is the same as fractional part of
                //      (initial_P + 0.5*10^extra_digits)/10^extra_digits is exactly zero
                
                // get remainder
                let remainder_h = CT.hi << (64 - amount);
                
                // test whether fractional part is 0
                if (remainder_h == 0 && (CT.lo < bid_reciprocals10_64[extra_digits])) {
                    C64-=1
                }
            }
        }
        
        var status = Status.inexact // BID_INEXACT_EXCEPTION;
        
        // get remainder
        let remainder_h = CT.hi << (64 - amount);
        
        switch rounding_mode {
            case BID_ROUNDING_TO_NEAREST, BID_ROUNDING_TIES_AWAY:
                // test whether fractional part is 0
                if ((remainder_h == MASK_SIGN) && (CT.lo < bid_reciprocals10_64[extra_digits])) {
                    status = []
                }
            case BID_ROUNDING_DOWN, BID_ROUNDING_TO_ZERO:
                if (remainder_h == 0 && (CT.lo < bid_reciprocals10_64[extra_digits])) {
                    status = []
                }
            default:
                // round up
                var tmp = UInt64()
                __add_carry_out (&tmp, &carry, CT.lo, bid_reciprocals10_64[extra_digits])
                if (remainder_h >> (64 - amount)) + carry >= (UInt64(1) << amount) {
                    status = []
                }
        }
        fpsc.formUnion(status)
        return get_BID64(sign_s, exponent_b + extra_digits, C64, rounding_mode, &fpsc)
    }
    
    /////////////////////////////////////////////////////////////////////////////////
    // round 192-bit coefficient (P, remainder_P) and return result in BID64 format
    // the lowest 64 bits (remainder_P) are used for midpoint checking only
    ////////////////////////////////////////////////////////////////////////////////
    static func __bid_full_round64_remainder (_ sign:UInt64, _ exponent:Int, _ P:UInt128,
                                              _ extra_digits:Int, _ remainder_P:UInt64,
                                              _ rounding_mode:Rounding, _ fpsc: inout Status,
                                              _ status:Status)  -> UInt64 {
        var Q_high = UInt128(), Q_low = UInt128(), C128 = UInt128(), Stemp = UInt128()
        var remainder_h = UInt64(), C64 = UInt64(), carry = UInt64(), CY = UInt64(), P = P
        var status = status
        // int amount, amount2, rmode, status = uf_status;
        
        var rmode = roundboundIndex(rounding_mode) >> 2 //rounding_mode;
        if (sign != 0 && UInt(rmode - 1) < 2) {
            rmode = 3 - rmode
        }
        if rounding_mode == BID_ROUNDING_UP && remainder_P != 0 {
            P.lo+=1
            if P.lo == 0 {
                P.hi+=1
            }
        }
        
        if extra_digits != 0 {
            __add_128_64(&P, P, bid_round_const_table[rmode][extra_digits])
            
            // get P*(2^M[extra_digits])/10^extra_digits
            __mul_128x128_full(&Q_high, &Q_low, P, bid_reciprocals10_128[extra_digits])
            
            // now get P/10^extra_digits: shift Q_high right by M[extra_digits]-128
            let amount = bid_recip_scale[extra_digits]
            __shr_128(&C128, Q_high, amount)
            
            var C64 = C128.lo
            if rmode == 0 {   //BID_ROUNDING_TO_NEAREST
                if (remainder_P == 0 && (C64 & 1 != 0)) {
                    // check whether fractional part of initial_P/10^extra_digits
                    // is exactly .5
                    
                    // get remainder
                    let amount2 = 64 - amount
                    remainder_h = 0
                    remainder_h &-= 1
                    remainder_h >>= amount2
                    remainder_h = remainder_h & Q_high.lo
                    
                    if (remainder_h == 0
                        && (Q_low.hi < bid_reciprocals10_128[extra_digits].hi
                            || (Q_low.hi == bid_reciprocals10_128[extra_digits].hi
                                && Q_low.lo < bid_reciprocals10_128[extra_digits].lo))) {
                        C64-=1
                    }
                }
            }
            
            status.insert(.inexact)
            
            if remainder_P == 0 {
                // get remainder
                remainder_h = Q_high.lo << (64 - amount)
                
                switch rounding_mode {
                    case BID_ROUNDING_TO_NEAREST, BID_ROUNDING_TIES_AWAY:
                        // test whether fractional part is 0
                        if (remainder_h == MASK_SIGN && (Q_low.hi < bid_reciprocals10_128[extra_digits].hi
                                || (Q_low.hi == bid_reciprocals10_128[extra_digits].hi
                                    && Q_low.lo < bid_reciprocals10_128[extra_digits].lo))) {
                            status = []
                        }
                    case BID_ROUNDING_DOWN, BID_ROUNDING_TO_ZERO:
                        if (remainder_h == 0 && (Q_low.hi < bid_reciprocals10_128[extra_digits].hi
                                || (Q_low.hi == bid_reciprocals10_128[extra_digits].hi
                                    && Q_low.lo < bid_reciprocals10_128[extra_digits].lo))) {
                            status = []
                        }
                    default:
                        // round up
                        __add_carry_out(&Stemp.lo, &CY, Q_low.lo, bid_reciprocals10_128[extra_digits].lo)
                        __add_carry_in_out(&Stemp.hi, &carry, Q_low.hi, bid_reciprocals10_128[extra_digits].hi, CY)
                        if (remainder_h >> (64 - amount)) + carry >= (UInt64(1) << amount) {
                            status = []
                        }
                }
            }
            fpsc.formUnion(status)
            
        } else {
            C64 = P.lo
            if remainder_P != 0 {
                fpsc.insert(.inexact)
                fpsc.formUnion(status)
            }
        }
        return get_BID64(sign, exponent + extra_digits, C64, rounding_mode, &fpsc);
    }
    
    static func mul(_ x:UInt64, _ y:UInt64, _ rnd_mode: Rounding, _ pfpsf: inout Status) -> UInt64 {
        var P = UInt128(), C128 = UInt128(), Q_high = UInt128(), Q_low = UInt128(), Stemp = UInt128()
        var PU = UInt128()
        var sign_x = UInt64(), sign_y = UInt64(), coefficient_x = UInt64(), coefficient_y = UInt64()
        var C64, remainder_h, carry, CY, res:UInt64
        var exponent_x = 0, exponent_y = 0, bin_expon_cx, bin_expon_cy, bp, bin_expon_product:Int
        let valid_x = unpack_BID64 (&sign_x, &exponent_x, &coefficient_x, x);
        let valid_y = unpack_BID64 (&sign_y, &exponent_y, &coefficient_y, y);
        
        // unpack arguments, check for NaN or Infinity
        if !valid_x {
            if (y & SNAN_MASK64) == SNAN_MASK64 {   // y is sNaN
                pfpsf.insert(.invalidOperation)
            }
            // x is Inf. or NaN
            
            // test if x is NaN
            if (x & NAN_MASK64) == NAN_MASK64 {
                if (x & SNAN_MASK64) == SNAN_MASK64 {   // sNaN
                    pfpsf.insert(.invalidOperation)
                }
                return coefficient_x & QUIET_MASK64
            }
            // x is Infinity?
            if ((x & INFINITY_MASK64) == INFINITY_MASK64) {
                // check if y is 0
                if (((y & INFINITY_MASK64) != INFINITY_MASK64) && coefficient_y == 0) {
                    pfpsf.insert(.invalidOperation)
                    // y==0 , return NaN
                    return (NAN_MASK64);
                }
                // check if y is NaN
                if ((y & NAN_MASK64) == NAN_MASK64) {
                    // y==NaN , return NaN
                    return (coefficient_y & QUIET_MASK64);
                }
                // otherwise return +/-Inf
                return (((x ^ y) & MASK_SIGN) | INFINITY_MASK64);
            }
            // x is 0
            if (y & INFINITY_MASK64) != INFINITY_MASK64 {
                if (y & SPECIAL_ENCODING_MASK64) == SPECIAL_ENCODING_MASK64 {
                    exponent_y = Int(UInt32(y >> EXPONENT_SHIFT_LARGE64)) & BINARY_EXPONENT_BIAS
                } else {
                    exponent_y = Int(UInt32(y >> EXPONENT_SHIFT_SMALL64)) & BINARY_EXPONENT_BIAS
                }
                sign_y = y & MASK_SIGN
                
                exponent_x += exponent_y - EXPONENT_BIAS
                if exponent_x > MAX_EXPON {
                    exponent_x = MAX_EXPON
                } else if exponent_x < 0 {
                    exponent_x = 0
                }
                return (sign_x ^ sign_y) | (UInt64(exponent_x) << EXPONENT_SHIFT_SMALL64)
            }
        }
        if !valid_y {
            // y is Inf. or NaN
            
            // test if y is NaN
            if ((y & NAN_MASK64) == NAN_MASK64) {
                if ((y & SNAN_MASK64) == SNAN_MASK64) {   // sNaN
                    pfpsf.insert(.invalidOperation)
                }
                return (coefficient_y & QUIET_MASK64)
            }
            // y is Infinity?
            if ((y & INFINITY_MASK64) == INFINITY_MASK64) {
                // check if x is 0
                if coefficient_x == 0 {
                    pfpsf.insert(.invalidOperation)
                    // x==0, return NaN
                    return (NAN_MASK64)
                }
                // otherwise return +/-Inf
                return ((x ^ y) & MASK_SIGN) | INFINITY_MASK64
            }
            // y is 0
            exponent_x += exponent_y - EXPONENT_BIAS;
            if exponent_x > MAX_EXPON {
                exponent_x = MAX_EXPON
            } else if exponent_x < 0 {
                exponent_x = 0
            }
            return ((sign_x ^ sign_y) | (UInt64(exponent_x) << EXPONENT_SHIFT_SMALL64))
        }
        //--- get number of bits in the coefficients of x and y ---
        // version 2 (original)
        let tempx = Double(coefficient_x)
        bin_expon_cx = Int((tempx.bitPattern & MASK_BINARY_EXPONENT) >> 52);
        let tempy = Double(coefficient_y)
        bin_expon_cy = Int((tempy.bitPattern & MASK_BINARY_EXPONENT) >> 52);
        
        // magnitude estimate for coefficient_x*coefficient_y is
        //        2^(unbiased_bin_expon_cx + unbiased_bin_expon_cx)
        bin_expon_product = bin_expon_cx + bin_expon_cy;
        
        // check if coefficient_x*coefficient_y<2^(10*k+3)
        // equivalent to unbiased_bin_expon_cx + unbiased_bin_expon_cx < 10*k+1
        if (bin_expon_product < UPPER_EXPON_LIMIT + 2 * BINARY_EXPONENT_BIAS) {
            //  easy multiply
            C64 = coefficient_x * coefficient_y
            return get_BID64_small_mantissa(sign_x ^ sign_y, exponent_x + exponent_y - EXPONENT_BIAS, C64, rnd_mode, &pfpsf)
        } else {
            var uf_status = Status.clearFlags
            // get 128-bit product: coefficient_x*coefficient_y
            __mul_64x64_to_128(&P, coefficient_x, coefficient_y)
            
            // tighten binary range of P:  leading bit is 2^bp
            // unbiased_bin_expon_product <= bp <= unbiased_bin_expon_product+1
            bin_expon_product -= 2 * BINARY_EXPONENT_BIAS
            
            bp = 0
            __tight_bin_range_128(&bp, &P, bin_expon_product)
            
            // get number of decimal digits in the product
            var digits_p = Int(bid_estimate_decimal_digits[bp])
            if !__unsigned_compare_gt_128 (bid_power10_table_128[digits_p], P) {
                digits_p+=1    // if bid_power10_table_128[digits_p] <= P
            }
            
            // determine number of decimal digits to be rounded out
            var extra_digits = digits_p - MAX_DIGITS
            var final_exponent = exponent_x + exponent_y + extra_digits - EXPONENT_BIAS
            
            var rmode = roundboundIndex(rnd_mode) >> 2 //rnd_mode;
            if (sign_x ^ sign_y) != 0 && UInt(rmode - 1) < 2 {
                rmode = 3 - rmode
            }
            
            var round_up = false
            let Ten15 = 1_000_000_000_000_000
            if UInt(final_exponent) >= 3 * 256 {
                if final_exponent < 0 {
                    // underflow
                    if final_exponent + 16 < 0 {
                        res = sign_x ^ sign_y
                        pfpsf.formUnion([.underflow, .inexact])
                        if rnd_mode == BID_ROUNDING_UP {
                            res |= 1
                        }
                        return res
                    }
                    
                    uf_status = Status.underflow // BID_UNDERFLOW_EXCEPTION
                    if final_exponent == -1 {
                        __add_128_64(&PU, P, bid_round_const_table[rmode][extra_digits]);
                        if __unsigned_compare_ge_128(PU, bid_power10_table_128[extra_digits + 16]) {
                            uf_status = []
                        }
                    }
                    extra_digits -= final_exponent
                    final_exponent = 0
                    
                    if extra_digits > 17 {
                        __mul_128x128_full(&Q_high, &Q_low, P, bid_reciprocals10_128[16])
                        
                        let amount = bid_recip_scale[16]
                        __shr_128(&P, Q_high, amount)
                        
                        // get sticky bits
                        let amount2 = 64 - amount
                        remainder_h = 0
                        remainder_h &-= 1
                        remainder_h >>= amount2
                        remainder_h = remainder_h & Q_high.lo
                        
                        extra_digits -= 16
                        if (remainder_h != 0 || (Q_low.hi > bid_reciprocals10_128[16].hi
                                            || (Q_low.hi == bid_reciprocals10_128[16].hi
                                                && Q_low.lo >= bid_reciprocals10_128[16].lo))) {
                            round_up = true
                            pfpsf.formUnion([.underflow, .inexact])
                            P.lo = (P.lo << 3) + (P.lo << 1)
                            P.lo |= 1
                            extra_digits+=1
                        }
                    }
                } else {
                    return fast_get_BID64_check_OF(sign_x ^ sign_y, final_exponent,
                                                   UInt64(Ten15), rnd_mode, &pfpsf)
                }
            }
            
            
            if extra_digits > 0 {
                // will divide by 10^(digits_p - 16)
                
                // add a constant to P, depending on rounding mode
                // 0.5*10^(digits_p - 16) for round-to-nearest
                __add_128_64(&P, P, bid_round_const_table[rmode][extra_digits])
                
                // get P*(2^M[extra_digits])/10^extra_digits
                __mul_128x128_full(&Q_high, &Q_low, P, bid_reciprocals10_128[extra_digits])
                
                // now get P/10^extra_digits: shift Q_high right by M[extra_digits]-128
                let amount = Int(bid_recip_scale[extra_digits])
                __shr_128(&C128, Q_high, amount)
                
                C64 = C128.lo
                
                if (rmode == 0) {   //BID_ROUNDING_TO_NEAREST
                    if ((C64 & 1) != 0 && !round_up) {
                        // check whether fractional part of initial_P/10^extra_digits
                        // is exactly .5
                        // this is the same as fractional part of
                        // (initial_P + 0.5*10^extra_digits)/10^extra_digits is exactly zero
                        
                        // get remainder
                        let remainder_h = Q_high.lo << (64 - amount);
                        
                        // test whether fractional part is 0
                        if (remainder_h == 0
                            && (Q_low.hi < bid_reciprocals10_128[extra_digits].hi
                                || (Q_low.hi == bid_reciprocals10_128[extra_digits].hi
                                    && Q_low.lo < bid_reciprocals10_128[extra_digits].lo))) {
                            C64-=1
                        }
                    }
                }
                
                var status = uf_status; status.insert(.inexact) // BID_INEXACT_EXCEPTION | uf_status;
                
                // get remainder
                remainder_h = Q_high.lo << (64 - amount);
                
                switch rnd_mode {
                    case BID_ROUNDING_TO_NEAREST, BID_ROUNDING_TIES_AWAY:
                        // test whether fractional part is 0
                        if (remainder_h == MASK_SIGN
                            && (Q_low.hi < bid_reciprocals10_128[extra_digits].hi
                                || (Q_low.hi == bid_reciprocals10_128[extra_digits].hi
                                    && Q_low.lo < bid_reciprocals10_128[extra_digits].lo))) {
                            status = []
                        }
                    case BID_ROUNDING_DOWN, BID_ROUNDING_TO_ZERO:
                        if (remainder_h == 0
                            && (Q_low.hi < bid_reciprocals10_128[extra_digits].hi
                                || (Q_low.hi == bid_reciprocals10_128[extra_digits].hi
                                    && Q_low.lo < bid_reciprocals10_128[extra_digits].lo))) {
                            status = []
                        }
                    default:
                        // round up
                        CY = 0; carry = 0
                        __add_carry_out(&Stemp.lo, &CY, Q_low.lo, bid_reciprocals10_128[extra_digits].lo)
                        __add_carry_in_out(&Stemp.hi, &carry, Q_low.hi, bid_reciprocals10_128[extra_digits].hi, CY)
                        if (remainder_h >> (64 - amount)) + carry >= (UInt64(1) << amount) {
                            status = []
                        }
                }
                
                pfpsf.formUnion(status)
                
                // convert to BID and return
                return fast_get_BID64_check_OF (sign_x ^ sign_y, final_exponent, C64, rnd_mode, &pfpsf)
            }
            // go to convert_format and exit
            C64 = P.lo
            return get_BID64 (sign_x ^ sign_y, exponent_x + exponent_y - EXPONENT_BIAS, C64, rnd_mode, &pfpsf)
        }
    }
}
