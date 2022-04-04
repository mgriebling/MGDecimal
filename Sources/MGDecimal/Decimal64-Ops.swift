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
                res = x & 0xfdffffffffffffff
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
            exp = Int((x & MASK_BINARY_EXPONENT2) >> 51) - 398
            C1 = (x & MASK_BINARY_SIG2) | MASK_BINARY_OR2
            if C1 > MAX_NUMBER {    // non-canonical
                C1 = 0;
            }
        } else {    // if ((x & MASK_STEERING_BITS) != MASK_STEERING_BITS)
            exp = Int((x & MASK_BINARY_EXPONENT1) >> 53) - 398
            C1 = (x & MASK_BINARY_SIG1)
        }
        
        // if x is 0 or non-canonical return 0 preserving the sign bit and
        // the preferred exponent of MAX(Q(x), 0)
        if (C1 == 0) {
            if (exp < 0) {
                exp = 0
            }
            return x_sign | ((UInt64(exp) + 398) << 53)
        }
        // x is a finite non-zero number (not 0, non-canonical, or special)
        
        switch rmode {
            case BID_ROUNDING_TO_NEAREST, BID_ROUNDING_TIES_AWAY:
                // return 0 if (exp <= -(p+1))
                if (exp <= -17) {
                    res = x_sign | 0x31c0000000000000;
                    pfpsf.insert(.inexact)
                    return res
                }
            case BID_ROUNDING_DOWN:
                // return 0 if (exp <= -p)
                if (exp <= -16) {
                    if x_sign != 0 {
                        res = 0xb1c0000000000001
                    } else {
                        res = 0x31c0000000000000
                    }
                    pfpsf.insert(.inexact)
                    return res
                }
            case BID_ROUNDING_UP:
                // return 0 if (exp <= -p)
                if (exp <= -16) {
                    if ((x_sign) != 0) {
                        res = 0xb1c0000000000000;
                    } else {
                        res = 0x31c0000000000001;
                    }
                    pfpsf.insert(.inexact)
                    return res
                }
            case BID_ROUNDING_TO_ZERO:
                // return 0 if (exp <= -p)
                if (exp <= -16) {
                    res = x_sign | 0x31c0000000000000;
                    pfpsf.insert(.inexact)
                    return res
                }
            default: break
        }    // end switch ()
        
        // q = nr. of decimal digits in x (1 <= q <= 54)
        //  determine first the nr. of bits in x
        var q : Int
        if C1 >= 0x0020000000000000 {    // x >= 2^53
            q = 16
        } else {    // if x < 2^53
            let tmp1 = Double(C1)    // exact conversion
            let x_nr_bits = 1 + Int((((tmp1.bitPattern >> 52)) & 0x7ff) - 0x3ff)
            q = Int(bid_nr_digits[x_nr_bits - 1].digits)
            if q == 0 {
                q = Int(bid_nr_digits[x_nr_bits - 1].digits1)
                if (C1 >= bid_nr_digits[x_nr_bits - 1].threshold_lo) {
                    q+=1
                }
            }
        }
        
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
                    if (res & 0x0000000000000001 != 0) && (fstar.hi == 0) && (fstar.lo < bid_ten2mk64[ind - 1]) {
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
                    res = x_sign | 0x31c0000000000000 | res;
                    return res
                } else {    // if exp < 0 and q + exp < 0
                    // the result is +0 or -0
                    res = x_sign | 0x31c0000000000000;
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
                    return x_sign | 0x31c0000000000000 | res
                } else {    // if exp < 0 and q + exp < 0
                    // the result is +0 or -0
                    res = x_sign | 0x31c0000000000000;
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
                    return x_sign | 0x31c0000000000000 | res
                } else {    // if exp < 0 and q + exp <= 0
                    // the result is +0 or -1
                    if x_sign != 0 {
                        res = 0xb1c0000000000001
                    } else {
                        res = 0x31c0000000000000
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
                    return x_sign | 0x31c0000000000000 | res
                } else {    // if exp < 0 and q + exp <= 0
                    // the result is -0 or +1
                    if x_sign != 0 {
                        res = 0xb1c0000000000000
                    } else {
                        res = 0x31c0000000000001
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
                    return x_sign | 0x31c0000000000000 | res
                } else {    // if exp < 0 and q + exp < 0
                    // the result is +0 or -0
                    res = x_sign | 0x31c0000000000000;
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
                    res = UInt64(Int64(exponent_x) << 53)
                } else {
                    res = UInt64(Int64( exponent_y) << 53)
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
        var bin_expon_ca = Int((tempx.bitPattern & MASK_BINARY_EXPONENT) >> 52) - 0x3ff
        
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
            bin_expon_ca = Int((tempx.bitPattern & MASK_BINARY_EXPONENT) >> 52) - 0x3ff;
            
            if diff_dec_expon > MAX_DIGITS {
                if coefficient_b != 0 {
                    pfpsf.insert(.inexact)
                }
                
                let irnd_mode = roundboundIndex(rnd_mode) >> 2
                if ((irnd_mode & 3 != 0) && coefficient_b != 0) {   // not BID_ROUNDING_TO_NEAREST
                    switch rnd_mode {
                        case BID_ROUNDING_DOWN:
                            if sign_b != 0 {
                                coefficient_a -= UInt64((Int64(sign_a) >> 63) | 1)
                                if coefficient_a < 1000000000000000 {
                                    exponent_a-=1
                                    coefficient_a = MAX_NUMBER
                                } else if coefficient_a >= MAX_NUMBERP1 {
                                    exponent_a+=1
                                    coefficient_a = 1000000000000000
                                }
                            }
                        case BID_ROUNDING_UP:
                            if sign_b == 0 {
                                coefficient_a += UInt64((Int64(sign_a) >> 63) | 1)
                                if coefficient_a < 1000000000000000 {
                                    exponent_a-=1
                                } else if coefficient_a >= MAX_NUMBERP1 {
                                    exponent_a+=1
                                    coefficient_a = 1000000000000000
                                }
                            }
                        default:    // RZ
                            if sign_a != sign_b {
                                coefficient_a-=1
                                if coefficient_a < 1000000000000000 {
                                    exponent_a-=1
                                    coefficient_a = MAX_NUMBER
                                }
                            }
                    }
                } else {
                    // check special case here
                    if ((coefficient_a == 1000000000000000) && (diff_dec_expon == MAX_DIGITS + 1)
                        && (sign_a ^ sign_b != 0) && (coefficient_b > 5000000000000000)) {
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
                    return (((x ^ y) & 0x8000000000000000) |
                                    INFINITY_MASK64);
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
                    exponent_y = Int(UInt32(y >> 51)) & 0x3ff;
            } else {
                    exponent_y = Int(UInt32(y >> 53)) & 0x3ff;
            }
                sign_y = y & 0x8000000000000000;
                
                exponent_x = exponent_x - exponent_y + EXPONENT_BIAS;
                if (exponent_x > MAX_EXPON) {
                    exponent_x = MAX_EXPON
                } else if (exponent_x < 0) {
                            exponent_x = 0;
                }
                return (sign_x ^ sign_y) | UInt64(exponent_x << 53)
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
                return (((x ^ y) & 0x8000000000000000));
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
            let bin_index = Int(tempy.bitPattern - tempx.bitPattern) >> 23;
            
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
            if (coefficient_y < 0x0020000000000000) {
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
            let bin_expon_cx = Int(tempq.bitPattern >> 52) - 0x3ff;
            
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
            if ((coefficient_x <= 1024) && (coefficient_y <= 1024)) {
                let i = Int(coefficient_y) - 1;
                let j = Int(coefficient_x) - 1;
                // difference in powers of 2 bid_factors for Y and X
                nzeros = ed2 - Int(bid_factors[i][0]) + Int(bid_factors[j][0])
                // difference in powers of 5 bid_factors
                let d5 = ed2 - Int(bid_factors[i][1]) + Int(bid_factors[j][1])
                if (d5 < nzeros) {
                    nzeros = d5;
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
                    if (tdigit[0] >= 100000000) {
                        tdigit[0] -= 100000000
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
        if (!valid_x) {
            // x is Inf. or NaN or 0
            if ((y & SNAN_MASK64) == SNAN_MASK64) {    // y is sNaN
                pfpsf.insert(.invalidOperation)
            }
            
            // test if x is NaN
            if ((x & 0x7c00000000000000) == 0x7c00000000000000) {
                if (((x & SNAN_MASK64) == SNAN_MASK64)) {
                    pfpsf.insert(.invalidOperation)
                }
                return coefficient_x & QUIET_MASK64;
            }
            // x is Infinity?
            if ((x & 0x7800000000000000) == 0x7800000000000000) {
                if (((y & NAN_MASK64) != NAN_MASK64)) {
                    pfpsf.insert(.invalidOperation)
                    // return NaN
                    return 0x7c00000000000000
                }
            }
            // x is 0
            // return x if y != 0
            if (((y & 0x7800000000000000) < 0x7800000000000000) && (coefficient_y != 0)) {
                if ((y & 0x6000000000000000) == 0x6000000000000000) {
                    exponent_y = Int(y >> 51) & 0x3ff;
                } else {
                    exponent_y = Int(y >> 53) & 0x3ff;
                }
                
                if (exponent_y < exponent_x) {
                    exponent_x = exponent_y;
                }
                
                var x = UInt64(exponent_x)
                x <<= 53;
                
                return x | sign_x
            }
            
        }
        if (!valid_y) {
            // y is Inf. or NaN
            
            // test if y is NaN
            if ((y & 0x7c00000000000000) == 0x7c00000000000000) {
                if (((y & SNAN_MASK64) == SNAN_MASK64)) {
                    pfpsf.insert(.invalidOperation)
                }
                return coefficient_y & QUIET_MASK64
            }
            // y is Infinity?
            if ((y & 0x7800000000000000) == 0x7800000000000000) {
                return very_fast_get_BID64 (sign_x, exponent_x, coefficient_x)
            }
            // y is 0, return NaN
            pfpsf.insert(.invalidOperation)
            return 0x7c00000000000000
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
                sign_x ^= 0x8000000000000000;
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
            //      digits_x++;
            
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
            sign_x ^= 0x8000000000000000;
        }
        
        return very_fast_get_BID64 (sign_x, exponent_y, coefficient_x)
    }
    
    static func sqrt(_ x: UInt64, _ rnd_mode: Rounding, _ pfpsf: inout Status) -> UInt64 {
        return 0
    }
    
    static func equal(_ x: UInt64, _ y: UInt64, _ pfpsf: inout Status) -> Bool {
        //        BID_TYPE_FUNCTION_ARG2_CUSTOMRESULT_NORND(int, bid64_quiet_equal, BID_UINT64, x, y)
        //
        //          int res;
        //          int exp_x, exp_y, exp_t;
        //          BID_UINT64 sig_x, sig_y, sig_t;
        //          char x_is_zero = 0, y_is_zero = 0, non_canon_x, non_canon_y, lcv;
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
            exp_x = Int(x & MASK_BINARY_EXPONENT2) >> 51;
            sig_x = (x & MASK_BINARY_SIG2) | MASK_BINARY_OR2;
            if (sig_x > 9999999999999999) {
                non_canon_x = true
            } else {
                non_canon_x = false
            }
        } else {
            exp_x = Int(x & MASK_BINARY_EXPONENT1) >> 53;
            sig_x = (x & MASK_BINARY_SIG1);
            non_canon_x = false
        }
        // if steering bits are 11 (condition will be 0), then exponent is G[0:w+1] =>
        if ((y & MASK_STEERING_BITS) == MASK_STEERING_BITS) {
            exp_y = Int(y & MASK_BINARY_EXPONENT2) >> 51;
            sig_y = (y & MASK_BINARY_SIG2) | MASK_BINARY_OR2
            if (sig_y > 9999999999999999) {
                non_canon_y = true
            } else {
                non_canon_y = false
            }
        } else {
            exp_y = Int(y & MASK_BINARY_EXPONENT1) >> 53;
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
            if (sig_y > 9999999999999999) {
                return false
            }
        }
       return (sig_y == sig_x)
    }
    
    static func lessThan(_ x: UInt64, _ y: UInt64, _ pfpsf: inout Status) -> Bool {
        //          int res;
        //          int exp_x, exp_y;
        //          BID_UINT64 sig_x, sig_y;
        //          BID_UINT128 sig_n_prime;
        //          char x_is_zero = 0, y_is_zero = 0, non_canon_x, non_canon_y;
        
        // NaN (CASE1)
        // if either number is NAN, the comparison is unordered : return 0
        var non_canon_x = false, non_canon_y = false, x_is_zero = false, y_is_zero = false
        var exp_x = 0, exp_y = 0, sig_x = UInt64(), sig_y = UInt64(), sig_n_prime = UInt128()
        if (((x & MASK_NAN) == MASK_NAN) || ((y & MASK_NAN) == MASK_NAN)) {
            if ((x & MASK_SNAN) == MASK_SNAN || (y & MASK_SNAN) == MASK_SNAN) {
                pfpsf.insert(.invalidOperation)    // set exception if sNaN
            }
            return false
        }
        // SIMPLE (CASE2)
        // if all the bits are the same, these numbers are equal.
        if (x == y) {
            return false
        }
        // INFINITY (CASE3)
        if ((x & MASK_INF) == MASK_INF) {
            // if x==neg_inf, { res = (y == neg_inf)?0:1; BID_RETURN (res) }
            if ((x & MASK_SIGN) == MASK_SIGN) {
                // x is -inf, so it is less than y unless y is -inf
                return (((y & MASK_INF) != MASK_INF) || (y & MASK_SIGN) != MASK_SIGN);
            } else {
                // x is pos_inf, no way for it to be less than y
                return false
            }
        } else if ((y & MASK_INF) == MASK_INF) {
            // x is finite, so:
            //    if y is +inf, x<y
            //    if y is -inf, x>y
            return ((y & MASK_SIGN) != MASK_SIGN);
        }
        // if steering bits are 11 (condition will be 0), then exponent is G[0:w+1] =>
        if ((x & MASK_STEERING_BITS) == MASK_STEERING_BITS) {
            exp_x = Int(x & MASK_BINARY_EXPONENT2) >> 51;
            sig_x = (x & MASK_BINARY_SIG2) | MASK_BINARY_OR2;
            if (sig_x > 9999999999999999) {
                non_canon_x = true
            } else {
                non_canon_x = false
            }
        } else {
            exp_x = Int(x & MASK_BINARY_EXPONENT1) >> 53;
            sig_x = (x & MASK_BINARY_SIG1);
            non_canon_x = false
        }
        // if steering bits are 11 (condition will be 0), then exponent is G[0:w+1] =>
        if ((y & MASK_STEERING_BITS) == MASK_STEERING_BITS) {
            exp_y = Int(y & MASK_BINARY_EXPONENT2) >> 51;
            sig_y = (y & MASK_BINARY_SIG2) | MASK_BINARY_OR2;
            if (sig_y > 9999999999999999) {
                non_canon_y = true
            } else {
                non_canon_y = false
            }
        } else {
            exp_y = Int(y & MASK_BINARY_EXPONENT1) >> 53;
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
    
    static func bid64_fma(_ x: UInt64, _ y: UInt64, _ z: UInt64, _ rnd_mode: Rounding, _ pfpsf: inout Status) -> UInt64 {
        return 0
    }
    
    static func mul(_ x:UInt64, _ y:UInt64, _ rnd_mode: Rounding, _ pfpsf: inout Status) -> UInt64 {
        return x
    }
    
}
