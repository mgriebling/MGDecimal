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
            if C1 > 9999999999999999 {    // non-canonical
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
                        res = P128.w[1]
                        fstar.w[1] = 0
                        fstar.w[0] = P128.w[0]
                    } else if (ind - 1 <= 21) {    // 3 <= ind - 1 <= 21 => 3 <= shift <= 63
                        let shift = bid_shiftright128[ind - 1]    // 3 <= shift <= 63
                        res = (P128.w[1] >> shift)
                        fstar.w[1] = P128.w[1] & bid_maskhigh128[ind - 1]
                        fstar.w[0] = P128.w[0]
                    }
                    // if (0 < f* < 10^(-x)) then the result is a midpoint
                    // since round_to_even, subtract 1 if current result is odd
                    if (res & 0x0000000000000001 != 0) && (fstar.w[1] == 0) && (fstar.w[0] < bid_ten2mk64[ind - 1]) {
                        res -= 1
                    }
                    // determine inexactness of the rounding of C*
                    // if (0 < f* - 1/2 < 10^(-x)) then
                    //   the result is exact
                    // else // if (f* - 1/2 > T*) then
                    //   the result is inexact
                    if (ind - 1 <= 2) {
                        if (fstar.w[0] > 0x8000000000000000) {
                            // f* > 1/2 and the result may be exact
                            // fstar.w[0] - 0x8000000000000000 is f* - 1/2
                            if ((fstar.w[0] - 0x8000000000000000) > bid_ten2mk64[ind - 1]) {
                                // set the inexact flag
                                pfpsf.insert(.inexact)
                            }    // else the result is exact
                        } else {    // the result is inexact; f2* <= 1/2
                            // set the inexact flag
                            pfpsf.insert(.inexact)
                        }
                    } else {    // if 3 <= ind - 1 <= 21
                        if fstar.w[1] > bid_onehalf128[ind - 1] || (fstar.w[1] == bid_onehalf128[ind - 1] && fstar.w[0] != 0) {
                            // f2* > 1/2 and the result may be exact
                            // Calculate f2* - 1/2
                            if fstar.w[1] > bid_onehalf128[ind - 1] || fstar.w[0] > bid_ten2mk64[ind - 1] {
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
                        res = P128.w[1]
                        fstar.w[1] = 0
                        fstar.w[0] = P128.w[0]
                    } else if ind - 1 <= 21 {    // 3 <= ind - 1 <= 21 => 3 <= shift <= 63
                        let shift = bid_shiftright128[ind - 1]    // 3 <= shift <= 63
                        res = (P128.w[1] >> shift)
                        fstar.w[1] = P128.w[1] & bid_maskhigh128[ind - 1]
                        fstar.w[0] = P128.w[0]
                    }
                    // midpoints are already rounded correctly
                    // determine inexactness of the rounding of C*
                    // if (0 < f* - 1/2 < 10^(-x)) then
                    //   the result is exact
                    // else // if (f* - 1/2 > T*) then
                    //   the result is inexact
                    if ind - 1 <= 2 {
                        if fstar.w[0] > 0x8000000000000000 {
                            // f* > 1/2 and the result may be exact
                            // fstar.w[0] - 0x8000000000000000 is f* - 1/2
                            if (fstar.w[0] - 0x8000000000000000) > bid_ten2mk64[ind - 1] {
                                // set the inexact flag
                                pfpsf.insert(.inexact)
                            }    // else the result is exact
                        } else {    // the result is inexact; f2* <= 1/2
                            // set the inexact flag
                            pfpsf.insert(.inexact)
                        }
                    } else {    // if 3 <= ind - 1 <= 21
                        if fstar.w[1] > bid_onehalf128[ind - 1] || (fstar.w[1] == bid_onehalf128[ind - 1] && fstar.w[0] != 0) {
                            // f2* > 1/2 and the result may be exact
                            // Calculate f2* - 1/2
                            if fstar.w[1] > bid_onehalf128[ind - 1] || fstar.w[0] > bid_ten2mk64[ind - 1] {
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
                        res = P128.w[1]
                        fstar.w[1] = 0
                        fstar.w[0] = P128.w[0]
                    } else if ind - 1 <= 21 {    // 3 <= ind - 1 <= 21 => 3 <= shift <= 63
                        let shift = bid_shiftright128[ind - 1]    // 3 <= shift <= 63
                        res = (P128.w[1] >> shift)
                        fstar.w[1] = P128.w[1] & bid_maskhigh128[ind - 1]
                        fstar.w[0] = P128.w[0]
                    }
                    // if (f* > 10^(-x)) then the result is inexact
                    if (fstar.w[1] != 0) || (fstar.w[0] >= bid_ten2mk64[ind - 1]) {
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
                        res = P128.w[1]
                        fstar.w[1] = 0
                        fstar.w[0] = P128.w[0]
                    } else if ind - 1 <= 21 {    // 3 <= ind - 1 <= 21 => 3 <= shift <= 63
                        let shift = bid_shiftright128[ind - 1]    // 3 <= shift <= 63
                        res = (P128.w[1] >> shift)
                        fstar.w[1] = P128.w[1] & bid_maskhigh128[ind - 1]
                        fstar.w[0] = P128.w[0]
                    }
                    // if (f* > 10^(-x)) then the result is inexact
                    if (fstar.w[1] != 0) || (fstar.w[0] >= bid_ten2mk64[ind - 1]) {
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
                        res = P128.w[1]
                        fstar.w[1] = 0
                        fstar.w[0] = P128.w[0]
                    } else if ind - 1 <= 21 {    // 3 <= ind - 1 <= 21 => 3 <= shift <= 63
                        let shift = bid_shiftright128[ind - 1]    // 3 <= shift <= 63
                        res = (P128.w[1] >> shift)
                        fstar.w[1] = P128.w[1] & bid_maskhigh128[ind - 1]
                        fstar.w[0] = P128.w[0]
                    }
                    // if (f* > 10^(-x)) then the result is inexact
                    if (fstar.w[1] != 0) || (fstar.w[0] >= bid_ten2mk64[ind - 1]) {
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

    
}
