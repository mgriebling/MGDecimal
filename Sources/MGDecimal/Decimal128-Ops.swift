//
//  File.swift
//  
//
//  Created by Mike Griebling on 2022-03-21.
//

import Foundation

extension Decimal128 {
    
    
    static func add(_ x: UInt128, _ y: UInt128, _ rnd_mode: Rounding, _ pfpsf: inout Status) -> UInt128 {
        var is_inexact = false, is_midpoint_lt_even = false, is_midpoint_gt_even = false
        var is_inexact_lt_midpoint = false, is_inexact_gt_midpoint = false
        var second_pass = false
        var x = x, y = y, res = UInt128.init(upper: 0xbadd_badd_badd_badd, lower: 0xbadd_badd_badd_badd)
        var halfulp64 = UInt64()
        var halfulp128 = UInt128(), C1 = UInt128(), C2 = UInt128(), ten2m1 = UInt128(), highf2star = UInt128()
        // top 128 bits in f2*; low 128 bits in R256[1], R256[0]
        var P256 = UInt256(), Q256 = UInt256(), R256 = UInt256()
        var x_exp = UInt64(), C1_hi = UInt64(), C1_lo = UInt64()
        
        BID_SWAP128(&x)
        BID_SWAP128(&y)
        var x_signi = x.hi & MASK_SIGN     // 0 for positive, MASK_SIGN for negative
        var y_signi = y.hi & MASK_SIGN     // 0 for positive, MASK_SIGN for negative
        var x_sign : Bool { x_signi != 0 }
        var y_sign : Bool { y_signi != 0 }
        
        // check for NaN or Infinity
        if ((x.hi & MASK_SPECIAL) == MASK_SPECIAL) || ((y.hi & MASK_SPECIAL) == MASK_SPECIAL) {
            // x is special or y is special
            if (x.hi & MASK_NAN) == MASK_NAN {    // x is NAN
                // check first for non-canonical NaN payload
                if ((x.hi & 0x0000_3fff_ffff_ffff) > Ten33M1.hi) ||
                   (((x.hi & 0x0000_3fff_ffff_ffff) == Ten33M1.hi) && (x.lo > Ten33M1.lo)) {
                    x.hi = x.hi & 0xffff_c000_0000_0000
                    x.lo = 0x0
                }
                if (x.hi & MASK_SNAN) == MASK_SNAN {    // x is SNAN
                    // set invalid flag
                    pfpsf.insert(.invalidOperation)
                    // return quiet (x)
                    res.hi = x.hi & 0xfc00_3fff_ffff_ffff
                    // clear out also G[6]-G[16]
                    res.lo = x.lo
                } else {    // x is QNaN
                    // return x
                    res.hi = x.hi & 0xfc00_3fff_ffff_ffff
                    // clear out G[6]-G[16]
                    res.lo = x.lo
                    // if y = SNaN signal invalid exception
                    if (y.hi & MASK_SNAN) == MASK_SNAN {
                        // set invalid flag
                        pfpsf.insert(.invalidOperation)
                    }
                }
                BID_SWAP128(&res)
                return res
            } else if ((y.hi & MASK_NAN) == MASK_NAN) {    // y is NAN
                // check first for non-canonical NaN payload
                if ((y.hi & 0x00003fffffffffff) > Ten33M1.hi) ||
                   (((y.hi & 0x00003fffffffffff) == Ten33M1.hi) && (y.lo > Ten33M1.lo)) {
                    y.hi = y.hi & 0xffffc00000000000
                    y.lo = 0x0
                }
                if (y.hi & MASK_SNAN) == MASK_SNAN {    // y is SNAN
                    // set invalid flag
                    pfpsf.insert(.invalidOperation)
                    // return quiet (y)
                    res.hi = y.hi &  0xfc00_3fff_ffff_ffff
                    // clear out also G[6]-G[16]
                    res.lo = y.lo
                } else {    // y is QNaN
                    // return y
                    res.hi = y.hi &  0xfc00_3fff_ffff_ffff
                    // clear out G[6]-G[16]
                    res.lo = y.lo
                }
                BID_SWAP128(&res)
                return res
            } else {    // neither x not y is NaN; at least one is infinity
                if (x.hi & Decimal64.MASK_ANY_INF) == MASK_INF {    // x is infinity
                    if (y.hi & Decimal64.MASK_ANY_INF) == MASK_INF {    // y is infinity
                        // if same sign, return either of them
                        if (x.hi & MASK_SIGN) == (y.hi & MASK_SIGN) {
                            res.hi = x_signi | MASK_INF
                            res.lo = 0x0
                        } else {    // x and y are infinities of opposite signs
                            // set invalid flag
                            pfpsf.insert(.invalidOperation)
                            // return QNaN Indefinite
                            res.hi = MASK_ANY_INF
                            res.lo = 0x0
                        }
                    } else {    // y is 0 or finite
                        // return x
                        res.hi = x_signi | MASK_INF
                        res.lo = 0x0
                    }
                } else {    // x is not NaN or infinity, so y must be infinity
                    res.hi = y_signi | MASK_INF
                    res.lo = 0x0
                }
                BID_SWAP128(&res)
                return res
            }
        }
        
        // unpack the arguments
        // unpack x
        x_exp = UInt64()
        C1_hi = x.hi & MASK_COEFF
        C1_lo = x.lo
        
        // test for non-canonical values:
        // - values whose encoding begins with x00, x01, or x10 and whose
        //   coefficient is larger than 10^34 -1, or
        // - values whose encoding begins with x1100, x1101, x1110 (if NaNs
        //   and infinitis were eliminated already this test is reduced to
        //   checking for x10x)
        // x is not infinity; check for non-canonical values - treated as zero
        if (x.hi & SPECIAL_ENCODING_MASK64) == SPECIAL_ENCODING_MASK64 {
            // G0_G1=11; non-canonical
            x_exp = (x.hi << 2) & MASK_EXP    // biased and shifted left 49 bits
            C1_hi = 0    // significand high
            C1_lo = 0    // significand low
        } else {    // G0_G1 != 11
            x_exp = x.hi & MASK_EXP    // biased and shifted left 49 bits
            if C1_hi > Ten34M1.hi || (C1_hi == Ten34M1.hi && C1_lo > Ten34M1.lo) {
                // x is non-canonical if coefficient is larger than 10^34 -1
                C1_hi = 0
                C1_lo = 0
            } else {    // canonical
                // nothing to do
            }
        }
        
        // unpack y
        var y_exp = UInt64()
        var C2_hi = y.hi & MASK_COEFF
        var C2_lo = y.lo
        
        // y is not infinity; check for non-canonical values - treated as zero
        if (y.hi & SPECIAL_ENCODING_MASK64) == SPECIAL_ENCODING_MASK64 {
            // G0_G1=11; non-canonical
            y_exp = (y.hi << 2) & MASK_EXP    // biased and shifted left 49 bits
            C2_hi = 0    // significand high
            C2_lo = 0    // significand low
        } else {    // G0_G1 != 11
            y_exp = y.hi & MASK_EXP;    // biased and shifted left 49 bits
            if C2_hi > Ten34M1.hi || (C2_hi == Ten34M1.hi && C2_lo > Ten34M1.lo) {
                // y is non-canonical if coefficient is larger than 10^34 -1
                C2_hi = 0
                C2_lo = 0
            } else {    // canonical
                // nothing to do
            }
        }
        
        if (C1_hi == 0x0) && (C1_lo == 0x0) {
            // x is 0 and y is not special
            // if y is 0 return 0 with the smaller exponent
            if (C2_hi == 0x0) && (C2_lo == 0x0) {
                if x_exp < y_exp {
                    res.hi = x_exp
                } else {
                    res.hi = y_exp
                }
                if x_sign && y_sign {
                    res.hi = res.hi | x_signi    // both negative
                } else if (rnd_mode == BID_ROUNDING_DOWN && x_sign != y_sign) {
                    res.hi = res.hi | MASK_SIGN;    // -0
                }
                // else; // res = +0
                res.lo = 0
            } else {
                // for 0 + y return y, with the preferred exponent
                if y_exp <= x_exp {
                    res = y
                } else {    // if y_exp > x_exp
                    // return (C2 * 10^scale) * 10^(y_exp - scale)
                    // where scale = min (P34-q2, y_exp-x_exp)
                    // determine q2 = nr. of decimal digits in y
                    //  determine first the nr. of bits in y (y_nr_bits)
                    let q2 = digitsIn(C2_hi, lo: C2_lo)
//                    var tmp2 = 0.0
//                    if C2_hi == 0 {    // y_bits is the nr. of bits in C2_lo
//                        if C2_lo >= 0x0020_0000_0000_0000 {    // y >= 2^53
//                            // split the 64-bit value in two 32-bit halves to avoid
//                            // rounding errors
//                            tmp2 = Double(C2_lo >> 32)    // exact conversion
//                            y_nr_bits = 32 + Int(((tmp2.bitPattern >> 52)) & 0x7ff) - BINARY_EXPONENT_BIAS
//                        } else {    // if y < 2^53
//                            tmp2 = Double(C2_lo)    // exact conversion
//                            y_nr_bits = Int(((tmp2.bitPattern >> 52)) & 0x7ff) - BINARY_EXPONENT_BIAS
//                        }
//                    } else {    // C2_hi != 0 => nr. bits = 64 + nr_bits (C2_hi)
//                        tmp2 = Double(C2_hi)    // exact conversion
//                        y_nr_bits = 64 + Int(((tmp2.bitPattern >> 52)) & 0x7ff) - BINARY_EXPONENT_BIAS
//                    }
//                    var q2 = Int(bid_nr_digits[y_nr_bits].digits)
//                    if q2 == 0 {
//                        q2 = Int(bid_nr_digits[y_nr_bits].digits1)
//                        if (C2_hi > bid_nr_digits[y_nr_bits].threshold_hi ||
//                           (C2_hi == bid_nr_digits[y_nr_bits].threshold_hi && C2_lo >= bid_nr_digits[y_nr_bits].threshold_lo)) {
//                            q2+=1
//                        }
//                    }
                    // return (C2 * 10^scale) * 10^(y_exp - scale)
                    // where scale = min (P34-q2, y_exp-x_exp)
                    var scale = P34 - q2
                    let ind = Int(y_exp - x_exp) >> 49
                    if ind < scale {
                        scale = ind
                    }
                    if scale == 0 {
                        res.hi = y.hi
                        res.lo = y.lo
                    } else if q2 <= 19 {    // y fits in 64 bits
                        if scale <= 19 {    // 10^scale fits in 64 bits
                            // 64 x 64 C2_lo * bid_ten2k64[scale]
                            __mul_64x64_to_128MACH(&res, C2_lo, bid_ten2k64[scale])
                        } else {    // 10^scale fits in 128 bits
                            // 64 x 128 C2_lo * bid_ten2k128[scale - 20]
                            __mul_128x64_to_128(&res, C2_lo, bid_ten2k128[scale - 20])
                        }
                    } else {    // y fits in 128 bits, but 10^scale must fit in 64 bits
                        // 64 x 128 bid_ten2k64[scale] * C2
                        C2.hi = C2_hi
                        C2.lo = C2_lo
                        __mul_128x64_to_128(&res, bid_ten2k64[scale], C2)
                    }
                    // subtract scale from the exponent
                    y_exp = y_exp - UInt64(scale << 49)
                    res.hi = res.hi | y_signi | y_exp
                }
            }
            BID_SWAP128(&res);
            return res;
        } else if ((C2_hi == 0x0) && (C2_lo == 0x0)) {
            // y is 0 and x is not special, and not zero
            // for x + 0 return x, with the preferred exponent
            if (x_exp <= y_exp) {
                res.hi = x.hi;
                res.lo = x.lo;
            } else {    // if x_exp > y_exp
                // return (C1 * 10^scale) * 10^(x_exp - scale)
                // where scale = min (P34-q1, x_exp-y_exp)
                // determine q1 = nr. of decimal digits in x
                //  determine first the nr. of bits in x
                let q1 = digitsIn(C1_hi, lo: C1_lo)
//                var tmp1 = 0.0
//                if (C1_hi == 0) {    // x_bits is the nr. of bits in C1_lo
//                    if C1_lo >= LARGE_COEFF_HIGH_BIT64 {    // x >= 2^53
//                        // split the 64-bit value in two 32-bit halves to avoid
//                        // rounding errors
//                        tmp1 = Double(C1_lo >> 32);    // exact conversion
//                        x_nr_bits = 32 + Int(((tmp1.bitPattern >> 52)) & 0x7ff) - BINARY_EXPONENT_BIAS
//                    } else {    // if x < 2^53
//                        tmp1 = Double(C1_lo)    // exact conversion
//                        x_nr_bits = Int(((tmp1.bitPattern >> 52)) & 0x7ff) - BINARY_EXPONENT_BIAS
//                    }
//                } else {    // C1_hi != 0 => nr. bits = 64 + nr_bits (C1_hi)
//                    tmp1 = Double(C1_hi)    // exact conversion
//                    x_nr_bits = 64 + Int(((tmp1.bitPattern >> 52)) & 0x7ff) - BINARY_EXPONENT_BIAS
//                }
//                var q1 = Int(bid_nr_digits[x_nr_bits].digits)
//                if q1 == 0 {
//                    q1 = Int(bid_nr_digits[x_nr_bits].digits1)
//                    if (C1_hi > bid_nr_digits[x_nr_bits].threshold_hi ||
//                        (C1_hi == bid_nr_digits[x_nr_bits].threshold_hi && C1_lo >= bid_nr_digits[x_nr_bits].threshold_lo)) {
//                        q1+=1
//                    }
//                }
                // return (C1 * 10^scale) * 10^(x_exp - scale)
                // where scale = min (P34-q1, x_exp-y_exp)
                var scale = P34 - q1
                let ind = Int(x_exp - y_exp) >> 49
                if ind < scale {
                    scale = ind
                }
                if scale == 0 {
                    res.hi = x.hi
                    res.lo = x.lo
                } else if q1 <= 19 {    // x fits in 64 bits
                    if scale <= 19 {    // 10^scale fits in 64 bits
                        // 64 x 64 C1_lo * bid_ten2k64[scale]
                        __mul_64x64_to_128MACH(&res, C1_lo, bid_ten2k64[scale])
                    } else {    // 10^scale fits in 128 bits
                        // 64 x 128 C1_lo * bid_ten2k128[scale - 20]
                        __mul_128x64_to_128(&res, C1_lo, bid_ten2k128[scale - 20])
                    }
                } else {    // x fits in 128 bits, but 10^scale must fit in 64 bits
                    // 64 x 128 bid_ten2k64[scale] * C1
                    C1.hi = C1_hi
                    C1.lo = C1_lo
                    __mul_128x64_to_128(&res, bid_ten2k64[scale], C1)
                }
                // subtract scale from the exponent
                x_exp = x_exp - UInt64(scale << 49)
                res.hi = res.hi | x_signi | x_exp
            }
            BID_SWAP128(&res)
            return res
        } else {    // x and y are not canonical, not special, and are not zero
            // note that the result may still be zero, and then it has to have the
            // preferred exponent
            var tmp_sign, tmp_signif_hi, tmp_signif_lo, tmp_exp: UInt64
            if x_exp < y_exp {
                // if exp_x < exp_y then swap x and y
                tmp_sign = x_signi
                tmp_exp = x_exp
                tmp_signif_hi = C1_hi
                tmp_signif_lo = C1_lo
                x_signi = y_signi
                x_exp = y_exp
                C1_hi = C2_hi
                C1_lo = C2_lo
                y_signi = tmp_sign
                y_exp = tmp_exp
                C2_hi = tmp_signif_hi
                C2_lo = tmp_signif_lo
            }
            // q1 = nr. of decimal digits in x
            //  determine first the nr. of bits in x
            let q1 = digitsIn(C1_hi, lo: C1_lo)
//            if C1_hi == 0 {    // x_bits is the nr. of bits in C1_lo
//                if C1_lo >= LARGE_COEFF_HIGH_BIT64 {    // x >= 2^53
//                    //split the 64-bit value in two 32-bit halves to avoid rounding errors
//                    tmp1 = Double(C1_lo >> 32);    // exact conversion
//                    x_nr_bits = 32 + Int(((tmp1.bitPattern >> 52)) & 0x7ff) - BINARY_EXPONENT_BIAS
//                } else {    // if x < 2^53
//                    tmp1 = Double(C1_lo)    // exact conversion
//                    x_nr_bits = Int(((tmp1.bitPattern >> 52)) & 0x7ff) - BINARY_EXPONENT_BIAS
//                }
//            } else {    // C1_hi != 0 => nr. bits = 64 + nr_bits (C1_hi)
//                tmp1 = Double(C1_hi)   // exact conversion
//                x_nr_bits = 64 + Int(((tmp1.bitPattern >> 52)) & 0x7ff) - BINARY_EXPONENT_BIAS
//            }
//
//            var q1 = Int(bid_nr_digits[x_nr_bits].digits)
//            if (q1 == 0) {
//                q1 = Int(bid_nr_digits[x_nr_bits].digits1)
//                if (C1_hi > bid_nr_digits[x_nr_bits].threshold_hi ||
//                    (C1_hi == bid_nr_digits[x_nr_bits].threshold_hi &&
//                     C1_lo >= bid_nr_digits[x_nr_bits].threshold_lo)) {
//                    q1+=1
//                }
//            }
            // q2 = nr. of decimal digits in y
            //  determine first the nr. of bits in y (y_nr_bits)
            let q2 = digitsIn(C2_hi, lo: C2_lo)
//            if C2_hi == 0 {    // y_bits is the nr. of bits in C2_lo
//                if C2_lo >= LARGE_COEFF_HIGH_BIT64 {    // y >= 2^53
//                    //split the 64-bit value in two 32-bit halves to avoid rounding errors
//                    tmp2 = Double(C2_lo >> 32)  // exact conversion
//                    y_nr_bits = 32 + Int(((tmp2.bitPattern >> 52)) & 0x7ff) - BINARY_EXPONENT_BIAS
//                } else {    // if y < 2^53
//                    tmp2 =  Double(C2_lo)       // exact conversion
//                    y_nr_bits = Int(((tmp2.bitPattern >> 52)) & 0x7ff) - BINARY_EXPONENT_BIAS
//                }
//            } else {    // C2_hi != 0 => nr. bits = 64 + nr_bits (C2_hi)
//                tmp2 = Double(C2_hi)   // exact conversion
//                y_nr_bits = 64 + Int(((tmp2.bitPattern >> 52)) & 0x7ff) - BINARY_EXPONENT_BIAS
//            }
//
//            var q2 = Int(bid_nr_digits[y_nr_bits].digits)
//            if q2 == 0 {
//                q2 = Int(bid_nr_digits[y_nr_bits].digits1)
//                if (C2_hi > bid_nr_digits[y_nr_bits].threshold_hi ||
//                    (C2_hi == bid_nr_digits[y_nr_bits].threshold_hi && C2_lo >= bid_nr_digits[y_nr_bits].threshold_lo)) {
//                    q2+=1
//                }
//            }
            
            let delta = q1 + Int(x_exp >> 49) - q2 - Int(y_exp >> 49)
            if delta >= P34 {
                // round the result directly because 0 < C2 < ulp (C1 * 10^(x_exp-e2))
                // n = C1 * 10^e1 or n = C1 +/- 10^(q1-P34)) * 10^e1
                // the result is inexact; the preferred exponent is the least possible
                
                if delta >= P34 + 1 {
                    // for RN the result is the operand with the larger magnitude,
                    // possibly scaled up by 10^(P34-q1)
                    // an overflow cannot occur in this case (rounding to nearest)
                    if q1 < P34 {    // scale C1 up by 10^(P34-q1)
                        // Note: because delta >= P34+1 it is certain that
                        //     x_exp - ((BID_UINT64)scale << 49) will stay above e_min
                        let scale = P34 - q1;
                        if q1 <= 19 {    // C1 fits in 64 bits
                            // 1 <= q1 <= 19 => 15 <= scale <= 33
                            if scale <= 19 {    // 10^scale fits in 64 bits
                                __mul_64x64_to_128MACH(&C1, bid_ten2k64[scale], C1_lo)
                            } else {    // if 20 <= scale <= 33
                                // C1 * 10^scale = (C1 * 10^(scale-19)) * 10^19 where
                                // (C1 * 10^(scale-19)) fits in 64 bits
                                C1_lo = C1_lo * bid_ten2k64[scale - 19]
                                __mul_64x64_to_128MACH(&C1, bid_ten2k64[19], C1_lo)
                            }
                        } else {    //if 20 <= q1 <= 33=P34-1 then C1 fits only in 128 bits
                            // => 1 <= P34 - q1 <= 14 so 10^(P34-q1) fits in 64 bits
                            C1.hi = C1_hi
                            C1.lo = C1_lo
                            // C1 = bid_ten2k64[P34 - q1] * C1
                            __mul_128x64_to_128(&C1, bid_ten2k64[P34 - q1], C1)
                        }
                        x_exp = x_exp - UInt64(scale << 49)
                        C1_hi = C1.hi
                        C1_lo = C1.lo
                    }
                    
                    // some special cases arise: if delta = P34 + 1 and C1 = 10^(P34-1)
                    // (after scaling) and x_sign != y_sign and C2 > 5*10^(q2-1) =>
                    // subtract 1 ulp
                    // Note: do this only for rounding to nearest; for other rounding
                    // modes the correction will be applied next
                    if ((rnd_mode == BID_ROUNDING_TO_NEAREST || rnd_mode == BID_ROUNDING_TIES_AWAY) &&
                        delta == (P34 + 1) && C1_hi == Ten33M1.hi && C1_lo == Ten33M1.lo+1 &&
                        x_sign != y_sign && ((q2 <= 19 && C2_lo > bid_midpoint64[q2 - 1]) ||
                                             (q2 >= 20 && (C2_hi > bid_midpoint128 [q2 - 20].hi ||
                                    (C2_hi == bid_midpoint128 [q2 - 20].hi && C2_lo > bid_midpoint128 [q2 - 20].lo))))) {
                        // C1 = 10^34 - 1 and decrement x_exp by 1 (no underflow possible)
                        C1_hi = Ten34M1.hi
                        C1_lo = Ten34M1.lo
                        x_exp = x_exp - EXP_P1
                    }
                    if rnd_mode != BID_ROUNDING_TO_NEAREST {
                        if (rnd_mode == BID_ROUNDING_DOWN && x_sign && y_sign) || (rnd_mode == BID_ROUNDING_UP && !x_sign && !y_sign) {
                            // add 1 ulp and then check for overflow
                            C1_lo += 1
                            if C1_lo == 0 { C1_hi += 1 }   // rounding overflow in the low 64 bits
                            if C1_hi == Ten34M1.hi && C1_lo == Ten34M1.lo+1 {
                                // C1 = 10^34 => rounding overflow
                                C1_hi = Ten33M1.hi
                                C1_lo = Ten33M1.lo+1    // 10^33
                                x_exp = x_exp + EXP_P1
                                if x_exp == EXP_MAX_P1 {    // overflow
                                    C1_hi = MASK_INF    // +inf
                                    C1_lo = 0x0
                                    x_exp = 0    // x_sign is preserved
                                    // set overflow flag (the inexact flag was set too)
                                    pfpsf.insert(.overflow)
                                }
                            }
                        } else if ((rnd_mode == BID_ROUNDING_DOWN && !x_sign && y_sign) ||
                                   (rnd_mode == BID_ROUNDING_UP && x_sign && !y_sign) ||
                                   (rnd_mode == BID_ROUNDING_TO_ZERO && x_sign != y_sign)) {
                            // subtract 1 ulp from C1
                            // Note: because delta >= P34 + 1 the result cannot be zero
                            C1_lo = C1_lo &- 1
                            if C1_lo == 0xffff_ffff_ffff_ffff { C1_hi -= 1 }
                            
                            // if the coefficient is 10^33 - 1 then make it 10^34 - 1 and
                            // decrease the exponent by 1 (because delta >= P34 + 1 the
                            // exponent will not become less than e_min)
                            // 10^33 - 1 = 0x0000314dc6448d9338c15b09ffffffff
                            // 10^34 - 1 = 0x0001ed09bead87c0378d8e63ffffffff
                            if C1_hi == Ten33M1.hi && C1_lo == Ten33M1.lo {
                                // make C1 = 10^34  - 1
                                C1_hi = Ten34M1.hi
                                C1_lo = Ten34M1.lo
                                x_exp = x_exp - EXP_P1
                            }
                        } else {
                            // the result is already correct
                        }
                    }
                    // set the inexact flag
                    pfpsf.insert(.inexact)
                    // assemble the result
                    res.hi = x_signi | x_exp | C1_hi
                    res.lo = C1_lo
                } else {    // delta = P34
                    // in most cases, the smaller operand may be < or = or > 1/2 ulp of the
                    // larger operand
                    // however, the case C1 = 10^(q1-1) and x_sign != y_sign is special due
                    // to accuracy loss after subtraction, and will be treated separately
                    if (x_sign == y_sign || (q1 <= 20 && (C1_hi != 0 || C1_lo != bid_ten2k64[q1 - 1]))
                        || (q1 >= 21 && (C1_hi != bid_ten2k128[q1 - 21].hi || C1_lo != bid_ten2k128[q1 - 21].lo))) {
                        // if x_sign == y_sign or C1 != 10^(q1-1)
                        // compare C2 with 1/2 ulp = 5 * 10^(q2-1), the latter read from table
                        // Note: cases q1<=19 and q1>=20 can be coalesced at some latency cost
                        if q2 <= 19 {    // C2 and 5*10^(q2-1) both fit in 64 bits
                            halfulp64 = bid_midpoint64[q2 - 1]    // 5 * 10^(q2-1)
                            if C2_lo < halfulp64 {    // n2 < 1/2 ulp (n1)
                                // for RN the result is the operand with the larger magnitude,
                                // possibly scaled up by 10^(P34-q1)
                                // an overflow cannot occur in this case (rounding to nearest)
                                if q1 < P34 {    // scale C1 up by 10^(P34-q1)
                                    // Note: because delta = P34 it is certain that
                                    //     x_exp - ((BID_UINT64)scale << 49) will stay above e_min
                                    let scale = P34 - q1
                                    if q1 <= 19 {    // C1 fits in 64 bits
                                        // 1 <= q1 <= 19 => 15 <= scale <= 33
                                        if scale <= 19 {    // 10^scale fits in 64 bits
                                            __mul_64x64_to_128MACH(&C1, bid_ten2k64[scale], C1_lo)
                                        } else {    // if 20 <= scale <= 33
                                            // C1 * 10^scale = (C1 * 10^(scale-19)) * 10^19 where
                                            // (C1 * 10^(scale-19)) fits in 64 bits
                                            C1_lo = C1_lo * bid_ten2k64[scale - 19]
                                            __mul_64x64_to_128MACH(&C1, bid_ten2k64[19], C1_lo)
                                        }
                                    } else { //if 20 <= q1 <= 33=P34-1 then C1 fits only in 128 bits
                                        // => 1 <= P34 - q1 <= 14 so 10^(P34-q1) fits in 64 bits
                                        C1.hi = C1_hi
                                        C1.lo = C1_lo
                                        // C1 = bid_ten2k64[P34 - q1] * C1
                                        __mul_128x64_to_128(&C1, bid_ten2k64[P34 - q1], C1)
                                    }
                                    x_exp = x_exp - UInt64(scale << 49)
                                    C1_hi = C1.hi
                                    C1_lo = C1.lo
                                }
                                if rnd_mode != BID_ROUNDING_TO_NEAREST {
                                    if (rnd_mode == BID_ROUNDING_DOWN && x_sign && y_sign) ||
                                       (rnd_mode == BID_ROUNDING_UP && !x_sign && !y_sign) {
                                        // add 1 ulp and then check for overflow
                                        C1_lo += 1
                                        if C1_lo == 0 { C1_hi += 1 }   // rounding overflow in the low 64 bits
                                        if C1_hi == Ten34M1.hi && C1_lo == Ten34M1.lo+1 {
                                            // C1 = 10^34 => rounding overflow
                                            C1_hi = Ten33M1.hi
                                            C1_lo = Ten33M1.lo+1    // 10^33
                                            x_exp = x_exp + EXP_P1
                                            if x_exp == EXP_MAX_P1 {    // overflow
                                                C1_hi = MASK_INF    // +inf
                                                C1_lo = 0x0
                                                x_exp = 0    // x_sign is preserved
                                                // set overflow flag (the inexact flag was set too)
                                                pfpsf.insert(.overflow)
                                            }
                                        }
                                    } else if ((rnd_mode == BID_ROUNDING_DOWN && !x_sign && y_sign)
                                               || (rnd_mode == BID_ROUNDING_UP && x_sign && !y_sign)
                                               || (rnd_mode == BID_ROUNDING_TO_ZERO && x_sign != y_sign)) {
                                        // subtract 1 ulp from C1
                                        // Note: because delta >= P34 + 1 the result cannot be zero
                                        C1_lo = C1_lo &- 1
                                        if C1_lo == 0xffff_ffff_ffff_ffff { C1_hi = C1_hi - 1 }
                                        
                                        // if the coefficient is 10^33-1 then make it 10^34-1 and
                                        // decrease the exponent by 1 (because delta >= P34 + 1 the
                                        // exponent will not become less than e_min)
                                        // 10^33 - 1 = 0x0000314dc6448d9338c15b09ffffffff
                                        // 10^34 - 1 = 0x0001ed09bead87c0378d8e63ffffffff
                                        if C1_hi == Ten33M1.hi && C1_lo == Ten33M1.lo {
                                            // make C1 = 10^34  - 1
                                            C1_hi = Ten34M1.hi
                                            C1_lo = Ten34M1.lo
                                            x_exp = x_exp - EXP_P1
                                        }
                                    } else {
                                        // the result is already correct
                                    }
                                }
                                // set the inexact flag
                                pfpsf.insert(.inexact)
                                
                                // assemble the result
                                res.hi = x_signi | x_exp | C1_hi
                                res.lo = C1_lo
                            } else if (C2_lo == halfulp64) && (q1 < P34 || ((C1_lo & 0x1) == 0)) {
                                // n2 = 1/2 ulp (n1) and q1 < P34 or C1 is even
                                // the result is the operand with the larger magnitude,
                                // possibly scaled up by 10^(P34-q1)
                                // an overflow cannot occur in this case (rounding to nearest)
                                if q1 < P34 {    // scale C1 up by 10^(P34-q1)
                                    // Note: because delta = P34 it is certain that
                                    //     x_exp - ((BID_UINT64)scale << 49) will stay above e_min
                                    let scale = P34 - q1
                                    if q1 <= 19 {    // C1 fits in 64 bits
                                        // 1 <= q1 <= 19 => 15 <= scale <= 33
                                        if scale <= 19 {    // 10^scale fits in 64 bits
                                            __mul_64x64_to_128MACH(&C1, bid_ten2k64[scale], C1_lo)
                                        } else {    // if 20 <= scale <= 33
                                            // C1 * 10^scale = (C1 * 10^(scale-19)) * 10^19 where
                                            // (C1 * 10^(scale-19)) fits in 64 bits
                                            C1_lo = C1_lo * bid_ten2k64[scale - 19]
                                            __mul_64x64_to_128MACH(&C1, bid_ten2k64[19], C1_lo)
                                        }
                                    } else {    //if 20 <= q1 <= 33=P34-1 then C1 fits only in 128 bits
                                        // => 1 <= P34 - q1 <= 14 so 10^(P34-q1) fits in 64 bits
                                        C1.hi = C1_hi
                                        C1.lo = C1_lo
                                        // C1 = bid_ten2k64[P34 - q1] * C1
                                        __mul_128x64_to_128(&C1, bid_ten2k64[P34 - q1], C1)
                                    }
                                    x_exp = x_exp - UInt64(scale << 49)
                                    C1_hi = C1.hi
                                    C1_lo = C1.lo
                                }
                                if ((rnd_mode == BID_ROUNDING_TO_NEAREST && x_sign == y_sign && (C1_lo & 0x01 != 0))
                                    || (rnd_mode == BID_ROUNDING_TIES_AWAY && x_sign == y_sign)
                                    || (rnd_mode == BID_ROUNDING_UP && !x_sign && !y_sign)
                                    || (rnd_mode == BID_ROUNDING_DOWN && x_sign && y_sign)) {
                                    // add 1 ulp and then check for overflow
                                    C1_lo = C1_lo + 1
                                    if C1_lo == 0 {  C1_hi = C1_hi + 1 }   // rounding overflow in the low 64 bits
                                    if C1_hi == Ten34M1.hi && C1_lo == Ten34M1.lo+1 {
                                        // C1 = 10^34 => rounding overflow
                                        C1_hi = Ten33M1.hi
                                        C1_lo = Ten33M1.lo+1    // 10^33
                                        x_exp = x_exp + EXP_P1
                                        if x_exp == EXP_MAX_P1 {    // overflow
                                            C1_hi = MASK_INF    // +inf
                                            C1_lo = 0x0
                                            x_exp = 0    // x_sign is preserved
                                            // set overflow flag (the inexact flag was set too)
                                            pfpsf.insert(.overflow)
                                        }
                                    }
                                } else if ((rnd_mode == BID_ROUNDING_TO_NEAREST && x_sign != y_sign &&
                                            ((C1_lo & 0x01) != 0)) ||
                                           (rnd_mode == BID_ROUNDING_DOWN && !x_sign && y_sign) ||
                                           (rnd_mode == BID_ROUNDING_UP && x_sign && !y_sign) ||
                                           (rnd_mode == BID_ROUNDING_TO_ZERO && x_sign != y_sign)) {
                                    // subtract 1 ulp from C1
                                    // Note: because delta >= P34 + 1 the result cannot be zero
                                    C1_lo = C1_lo &- 1
                                    if C1_lo == 0xffff_ffff_ffff_ffff { C1_hi = C1_hi - 1 }
                                    
                                    // if the coefficient is 10^33 - 1 then make it 10^34 - 1
                                    // and decrease the exponent by 1 (because delta >= P34 + 1
                                    // the exponent will not become less than e_min)
                                    // 10^33 - 1 = 0x0000314dc6448d9338c15b09ffffffff
                                    // 10^34 - 1 = 0x0001ed09bead87c0378d8e63ffffffff
                                    if C1_hi == Ten33M1.hi && C1_lo == Ten33M1.lo {
                                        // make C1 = 10^34  - 1
                                        C1_hi = Ten34M1.hi
                                        C1_lo = Ten34M1.lo
                                        x_exp = x_exp - EXP_P1
                                    }
                                } else {
                                    // the result is already correct
                                }
                                // set the inexact flag
                                pfpsf.insert(.inexact)
                                // assemble the result
                                res.hi = x_signi | x_exp | C1_hi
                                res.lo = C1_lo
                            } else {    // if C2_lo > halfulp64 ||
                                // (C2_lo == halfulp64 && q1 == P34 && ((C1_lo & 0x1) == 1)), i.e.
                                // 1/2 ulp(n1) < n2 < 1 ulp(n1) or n2 = 1/2 ulp(n1) and C1 odd
                                // res = x+1 ulp if n1*n2 > 0 and res = x-1 ulp if n1*n2 < 0
                                if q1 < P34 {    // then 1 ulp = 10^(e1+q1-P34) < 10^e1
                                    // Note: if (q1 == P34) then 1 ulp = 10^(e1+q1-P34) = 10^e1
                                    // because q1 < P34 we must first replace C1 by
                                    // C1 * 10^(P34-q1), and must decrease the exponent by
                                    // (P34-q1) (it will still be at least e_min)
                                    let scale = P34 - q1
                                    if q1 <= 19 {    // C1 fits in 64 bits
                                        // 1 <= q1 <= 19 => 15 <= scale <= 33
                                        if scale <= 19 {    // 10^scale fits in 64 bits
                                            __mul_64x64_to_128MACH(&C1, bid_ten2k64[scale], C1_lo)
                                        } else {    // if 20 <= scale <= 33
                                            // C1 * 10^scale = (C1 * 10^(scale-19)) * 10^19 where
                                            // (C1 * 10^(scale-19)) fits in 64 bits
                                            C1_lo = C1_lo * bid_ten2k64[scale - 19]
                                            __mul_64x64_to_128MACH(&C1, bid_ten2k64[19], C1_lo)
                                        }
                                    } else {    //if 20 <= q1 <= 33=P34-1 then C1 fits only in 128 bits
                                        // => 1 <= P34 - q1 <= 14 so 10^(P34-q1) fits in 64 bits
                                        C1.hi = C1_hi
                                        C1.lo = C1_lo
                                        // C1 = bid_ten2k64[P34 - q1] * C1
                                        __mul_128x64_to_128(&C1, bid_ten2k64[P34 - q1], C1)
                                    }
                                    x_exp = x_exp - UInt64(scale << 49)
                                    C1_hi = C1.hi
                                    C1_lo = C1.lo
                                    // check for rounding overflow
                                    if C1_hi == Ten34M1.hi && C1_lo == Ten34M1.lo+1 {
                                        // C1 = 10^34 => rounding overflow
                                        C1_hi = Ten33M1.hi
                                        C1_lo = Ten33M1.lo+1    // 10^33
                                        x_exp = x_exp + EXP_P1
                                    }
                                }
                                if ((rnd_mode == BID_ROUNDING_TO_NEAREST && x_sign != y_sign)
                                    || (rnd_mode == BID_ROUNDING_TIES_AWAY && x_sign != y_sign && C2_lo != halfulp64)
                                    || (rnd_mode == BID_ROUNDING_DOWN && !x_sign && y_sign)
                                    || (rnd_mode == BID_ROUNDING_UP && x_sign && !y_sign)
                                    || (rnd_mode == BID_ROUNDING_TO_ZERO && x_sign != y_sign)) {
                                    // the result is x - 1
                                    // for RN n1 * n2 < 0; underflow not possible
                                    C1_lo = C1_lo &- 1
                                    if C1_lo == 0xffff_ffff_ffff_ffff { C1_hi-=1 }
                                    
                                    // check if we crossed into the lower decade
                                    if (C1_hi == Ten33M1.hi && C1_lo == Ten33M1.lo) {    // 10^33 - 1
                                        C1_hi = Ten34M1.hi    // 10^34 - 1
                                        C1_lo = Ten34M1.lo
                                        x_exp = x_exp - EXP_P1    // no underflow, because n1 >> n2
                                    }
                                } else  if ((rnd_mode == BID_ROUNDING_TO_NEAREST && x_sign == y_sign)
                                            || (rnd_mode == BID_ROUNDING_TIES_AWAY && x_sign == y_sign)
                                            || (rnd_mode == BID_ROUNDING_DOWN && x_sign && y_sign)
                                            || (rnd_mode == BID_ROUNDING_UP && !x_sign && !y_sign)) {
                                    // the result is x + 1
                                    // for RN x_sign = y_sign, i.e. n1*n2 > 0
                                    C1_lo += 1
                                    if C1_lo == 0 { C1_hi += 1 } // rounding overflow in the low 64 bits
                                    if C1_hi == Ten34M1.hi && C1_lo == Ten34M1.lo+1 {
                                        // C1 = 10^34 => rounding overflow
                                        C1_hi = Ten33M1.hi
                                        C1_lo = Ten33M1.lo+1    // 10^33
                                        x_exp = x_exp + EXP_P1
                                        if x_exp == EXP_MAX_P1 {    // overflow
                                            C1_hi = MASK_INF    // +inf
                                            C1_lo = 0x0
                                            x_exp = 0    // x_sign is preserved
                                            // set the overflow flag
                                            pfpsf.insert(.overflow)
                                        }
                                    }
                                } else {
                                    // the result is x
                                }
                                // set the inexact flag
                                pfpsf.insert(.inexact)
                                // assemble the result
                                res.hi = x_signi | x_exp | C1_hi
                                res.lo = C1_lo
                            }
                        } else {    // if q2 >= 20 then 5*10^(q2-1) and C2 (the latter in
                            // most cases) fit only in more than 64 bits
                            halfulp128 = bid_midpoint128[q2 - 20]    // 5 * 10^(q2-1)
                            if (C2_hi < halfulp128.hi) || (C2_hi == halfulp128.hi && C2_lo < halfulp128.lo) {
                                // n2 < 1/2 ulp (n1)
                                // the result is the operand with the larger magnitude,
                                // possibly scaled up by 10^(P34-q1)
                                // an overflow cannot occur in this case (rounding to nearest)
                                if q1 < P34 {    // scale C1 up by 10^(P34-q1)
                                    // Note: because delta = P34 it is certain that
                                    //     x_exp - ((BID_UINT64)scale << 49) will stay above e_min
                                    let scale = P34 - q1
                                    if q1 <= 19 {    // C1 fits in 64 bits
                                        // 1 <= q1 <= 19 => 15 <= scale <= 33
                                        if scale <= 19 {    // 10^scale fits in 64 bits
                                            __mul_64x64_to_128MACH(&C1, bid_ten2k64[scale], C1_lo)
                                        } else {    // if 20 <= scale <= 33
                                            // C1 * 10^scale = (C1 * 10^(scale-19)) * 10^19 where
                                            // (C1 * 10^(scale-19)) fits in 64 bits
                                            C1_lo = C1_lo * bid_ten2k64[scale - 19];
                                            __mul_64x64_to_128MACH(&C1, bid_ten2k64[19], C1_lo)
                                        }
                                    } else {    //if 20 <= q1 <= 33=P34-1 then C1 fits only in 128 bits
                                        // => 1 <= P34 - q1 <= 14 so 10^(P34-q1) fits in 64 bits
                                        C1.hi = C1_hi
                                        C1.lo = C1_lo
                                        // C1 = bid_ten2k64[P34 - q1] * C1
                                        __mul_128x64_to_128(&C1, bid_ten2k64[P34 - q1], C1)
                                    }
                                    C1_hi = C1.hi;
                                    C1_lo = C1.lo;
                                    x_exp = x_exp - UInt64(scale << 49);
                                }
                                if rnd_mode != BID_ROUNDING_TO_NEAREST {
                                    if (rnd_mode == BID_ROUNDING_DOWN && x_sign && y_sign) ||
                                        (rnd_mode == BID_ROUNDING_UP && !x_sign && !y_sign) {
                                        // add 1 ulp and then check for overflow
                                        C1_lo += 1
                                        if C1_lo == 0 { C1_hi += 1 } // rounding overflow in the low 64 bits
                                        if C1_hi == Ten34M1.hi && C1_lo == Ten34M1.lo+1 {
                                            // C1 = 10^34 => rounding overflow
                                            C1_hi = Ten33M1.hi
                                            C1_lo = Ten33M1.lo+1  // 10^33
                                            x_exp = x_exp + EXP_P1
                                            if x_exp == EXP_MAX_P1 {    // overflow
                                                C1_hi = MASK_INF        // +inf
                                                C1_lo = 0x0
                                                x_exp = 0    // x_sign is preserved
                                                // set overflow flag (the inexact flag was set too)
                                                pfpsf.insert(.overflow)
                                            }
                                        }
                                    } else if ((rnd_mode == BID_ROUNDING_DOWN && !x_sign && y_sign)
                                               || (rnd_mode == BID_ROUNDING_UP && x_sign && !y_sign)
                                               || (rnd_mode == BID_ROUNDING_TO_ZERO && x_sign != y_sign)) {
                                        // subtract 1 ulp from C1
                                        // Note: because delta >= P34 + 1 the result cannot be zero
                                        C1_lo = C1_lo &- 1
                                        if C1_lo == 0xffff_ffff_ffff_ffff { C1_hi -= 1 }
                                        
                                        // if the coefficient is 10^33-1 then make it 10^34-1 and
                                        // decrease the exponent by 1 (because delta >= P34 + 1 the
                                        // exponent will not become less than e_min)
                                        // 10^33 - 1 = 0x0000314dc6448d93_38c15b09ffffffff
                                        // 10^34 - 1 = 0x0001ed09bead87c0_378d8e63ffffffff
                                        if C1_hi == Ten33M1.hi && C1_lo == Ten33M1.lo {
                                            // make C1 = 10^34  - 1
                                            C1_hi = Ten34M1.hi
                                            C1_lo = Ten34M1.lo
                                            x_exp = x_exp - EXP_P1
                                        }
                                    } else {
                                        // the result is already correct
                                    }
                                }
                                // set the inexact flag
                                pfpsf.insert(.inexact)
                                // assemble the result
                                res.hi = x_signi | x_exp | C1_hi
                                res.lo = C1_lo
                            } else if (C2_hi == halfulp128.hi && C2_lo == halfulp128.lo) && (q1 < P34 || ((C1_lo & 0x1) == 0)) {
                                // set the inexact flag
                                // midpoint & lsb in C1 is 0
                                // n2 = 1/2 ulp (n1) and C1 is even
                                // the result is the operand with the larger magnitude,
                                // possibly scaled up by 10^(P34-q1)
                                // an overflow cannot occur in this case (rounding to nearest)
                                if q1 < P34 {    // scale C1 up by 10^(P34-q1)
                                    // Note: because delta = P34 it is certain that
                                    //     x_exp - ((BID_UINT64)scale << 49) will stay above e_min
                                    let scale = P34 - q1
                                    if q1 <= 19 {    // C1 fits in 64 bits
                                        // 1 <= q1 <= 19 => 15 <= scale <= 33
                                        if scale <= 19 {    // 10^scale fits in 64 bits
                                            __mul_64x64_to_128MACH(&C1, bid_ten2k64[scale], C1_lo)
                                        } else {    // if 20 <= scale <= 33
                                            // C1 * 10^scale = (C1 * 10^(scale-19)) * 10^19 where
                                            // (C1 * 10^(scale-19)) fits in 64 bits
                                            C1_lo = C1_lo * bid_ten2k64[scale - 19]
                                            __mul_64x64_to_128MACH(&C1, bid_ten2k64[19], C1_lo)
                                        }
                                    } else {    //if 20 <= q1 <= 33=P34-1 then C1 fits only in 128 bits
                                        // => 1 <= P34 - q1 <= 14 so 10^(P34-q1) fits in 64 bits
                                        C1.hi = C1_hi
                                        C1.lo = C1_lo
                                        // C1 = bid_ten2k64[P34 - q1] * C1
                                        __mul_128x64_to_128(&C1, bid_ten2k64[P34 - q1], C1)
                                    }
                                    x_exp = x_exp - UInt64(scale << 49)
                                    C1_hi = C1.hi
                                    C1_lo = C1.lo
                                }
                                if rnd_mode != BID_ROUNDING_TO_NEAREST {
                                    if ((rnd_mode == BID_ROUNDING_TIES_AWAY && x_sign == y_sign) ||
                                        (rnd_mode == BID_ROUNDING_UP && !x_sign && !y_sign) ||
                                        (rnd_mode == BID_ROUNDING_DOWN && x_sign && y_sign)) {
                                        // add 1 ulp and then check for overflow
                                        C1_lo = C1_lo + 1
                                        if C1_lo == 0 { C1_hi = C1_hi + 1 } // rounding overflow in the low 64 bits
                                        if C1_hi == Ten34M1.hi && C1_lo == Ten34M1.lo+1 {
                                            // C1 = 10^34 => rounding overflow
                                            C1_hi = Ten33M1.hi
                                            C1_lo = Ten33M1.lo+1    // 10^33
                                            x_exp = x_exp + EXP_P1
                                            if x_exp == EXP_MAX_P1 {    // overflow
                                                C1_hi = MASK_INF    // +inf
                                                C1_lo = 0x0
                                                x_exp = 0    // x_sign is preserved
                                                // set overflow flag (the inexact flag was set too)
                                                pfpsf.insert(.overflow)
                                            }
                                        }
                                    } else if ((rnd_mode == BID_ROUNDING_DOWN && !x_sign && y_sign)
                                               || (rnd_mode == BID_ROUNDING_UP && x_sign && !y_sign)
                                               || (rnd_mode == BID_ROUNDING_TO_ZERO && x_sign != y_sign)) {
                                        // subtract 1 ulp from C1
                                        // Note: because delta >= P34 + 1 the result cannot be zero
                                        C1_lo = C1_lo &- 1
                                        if C1_lo == 0xffff_ffff_ffff_ffff { C1_hi = C1_hi - 1 }
                                        
                                        // if the coefficient is 10^33 - 1 then make it 10^34 - 1
                                        // and decrease the exponent by 1 (because delta >= P34 + 1
                                        // the exponent will not become less than e_min)
                                        // 10^33 - 1 = 0x0000314dc6448d9338c15b09ffffffff
                                        // 10^34 - 1 = 0x0001ed09bead87c0378d8e63ffffffff
                                        if C1_hi == Ten33M1.hi && C1_lo == Ten33M1.lo {
                                            // make C1 = 10^34  - 1
                                            C1_hi = Ten34M1.hi
                                            C1_lo = Ten34M1.lo
                                            x_exp = x_exp - EXP_P1
                                        }
                                    } else {
                                        // the result is already correct
                                    }
                                }
                                // set the inexact flag
                                pfpsf.insert(.inexact)
                                // assemble the result
                                res.hi = x_signi | x_exp | C1_hi
                                res.lo = C1_lo
                            } else {    // if C2 > halfulp128 ||
                                // (C2 == halfulp128 && q1 == P34 && ((C1 & 0x1) == 1)), i.e.
                                // 1/2 ulp(n1) < n2 < 1 ulp(n1) or n2 = 1/2 ulp(n1) and C1 odd
                                // res = x+1 ulp if n1*n2 > 0 and res = x-1 ulp if n1*n2 < 0
                                if q1 < P34 {    // then 1 ulp = 10^(e1+q1-P34) < 10^e1
                                    // Note: if (q1 == P34) then 1 ulp = 10^(e1+q1-P34) = 10^e1
                                    // because q1 < P34 we must first replace C1 by C1*10^(P34-q1),
                                    // and must decrease the exponent by (P34-q1) (it will still be
                                    // at least e_min)
                                    let scale = P34 - q1
                                    if q1 <= 19 {    // C1 fits in 64 bits
                                        // 1 <= q1 <= 19 => 15 <= scale <= 33
                                        if scale <= 19 {    // 10^scale fits in 64 bits
                                            __mul_64x64_to_128MACH(&C1, bid_ten2k64[scale], C1_lo)
                                        } else {    // if 20 <= scale <= 33
                                            // C1 * 10^scale = (C1 * 10^(scale-19)) * 10^19 where
                                            // (C1 * 10^(scale-19)) fits in 64 bits
                                            C1_lo = C1_lo * bid_ten2k64[scale - 19]
                                            __mul_64x64_to_128MACH(&C1, bid_ten2k64[19], C1_lo)
                                        }
                                    } else {    //if 20 <= q1 <= 33=P34-1 then C1 fits only in 128 bits
                                        // => 1 <= P34 - q1 <= 14 so 10^(P34-q1) fits in 64 bits
                                        C1.hi = C1_hi
                                        C1.lo = C1_lo
                                        // C1 = bid_ten2k64[P34 - q1] * C1
                                        __mul_128x64_to_128(&C1, bid_ten2k64[P34 - q1], C1)
                                    }
                                    C1_hi = C1.hi
                                    C1_lo = C1.lo
                                    x_exp = x_exp - UInt64(scale << 49)
                                }
                                if ((rnd_mode == BID_ROUNDING_TO_NEAREST && x_sign != y_sign)
                                    || (rnd_mode == BID_ROUNDING_TIES_AWAY && x_sign != y_sign
                                        && (C2_hi != halfulp128.hi || C2_lo != halfulp128.lo))
                                    || (rnd_mode == BID_ROUNDING_DOWN && !x_sign && y_sign)
                                    || (rnd_mode == BID_ROUNDING_UP && x_sign && !y_sign)
                                    || (rnd_mode == BID_ROUNDING_TO_ZERO && x_sign != y_sign)) {
                                    // the result is x - 1
                                    // for RN n1 * n2 < 0; underflow not possible
                                    C1_lo = C1_lo &- 1
                                    if C1_lo == 0xffff_ffff_ffff_ffff { C1_hi-=1 }
                                    // check if we crossed into the lower decade
                                    if C1_hi == Ten33M1.hi && C1_lo == Ten33M1.lo {    // 10^33 - 1
                                        C1_hi = Ten34M1.hi    // 10^34 - 1
                                        C1_lo = Ten34M1.lo
                                        x_exp = x_exp - EXP_P1    // no underflow, because n1 >> n2
                                    }
                                } else if (rnd_mode == BID_ROUNDING_TO_NEAREST && x_sign == y_sign)
                                           || (rnd_mode == BID_ROUNDING_TIES_AWAY && x_sign == y_sign)
                                           || (rnd_mode == BID_ROUNDING_DOWN && x_sign && y_sign)
                                           || (rnd_mode == BID_ROUNDING_UP && !x_sign && !y_sign) {
                                    // the result is x + 1
                                    // for RN x_sign = y_sign, i.e. n1*n2 > 0
                                    C1_lo = C1_lo + 1
                                    if C1_lo == 0 { C1_hi = C1_hi + 1 }
                                    if C1_hi == Ten34M1.hi && C1_lo == Ten34M1.lo+1 {
                                        // C1 = 10^34 => rounding overflow
                                        C1_hi = Ten33M1.hi
                                        C1_lo = Ten33M1.lo+1    // 10^33
                                        x_exp = x_exp + EXP_P1
                                        if x_exp == EXP_MAX_P1 {    // overflow
                                            C1_hi = MASK_INF    // +inf
                                            C1_lo = 0x0
                                            x_exp = 0    // x_sign is preserved
                                            // set the overflow flag
                                            pfpsf.insert(.overflow)
                                        }
                                    }
                                } else {
                                    // the result is x
                                }
                                // set the inexact flag
                                pfpsf.insert(.inexact)
                                // assemble the result
                                res.hi = x_signi | x_exp | C1_hi
                                res.lo = C1_lo
                            }
                        }    // end q1 >= 20
                        // end case where C1 != 10^(q1-1)
                    } else {    // C1 = 10^(q1-1) and x_sign != y_sign
                        // instead of C' = (C1 * 10^(e1-e2) + C2)rnd,P34
                        // calculate C' = C1 * 10^(e1-e2-x1) + (C2 * 10^(-x1))rnd,P34
                        // where x1 = q2 - 1, 0 <= x1 <= P34 - 1
                        // Because C1 = 10^(q1-1) and x_sign != y_sign, C' will have P34
                        // digits and n = C' * 10^(e2+x1)
                        // If the result has P34+1 digits, redo the steps above with x1+1
                        // If the result has P34-1 digits or less, redo the steps above with
                        // x1-1 but only if initially x1 >= 1
                        // NOTE: these two steps can be improved, e.g we could guess if
                        // P34+1 or P34-1 digits will be obtained by adding/subtracting
                        // just the top 64 bits of the two operands
                        // The result cannot be zero, and it cannot overflow
                        let x1 = q2 - 1    // 0 <= x1 <= P34-1
                        // Calculate C1 * 10^(e1-e2-x1) where 1 <= e1-e2-x1 <= P34
                        // scale = (int)(e1 >> 49) - (int)(e2 >> 49) - x1; 0 <= scale <= P34-1
                        let scale = P34 - q1 + 1    // scale=e1-e2-x1 = P34+1-q1; 1<=scale<=P34
                        // either C1 or 10^(e1-e2-x1) may not fit is 64 bits,
                        // but their product fits with certainty in 128 bits
                        if scale >= 20 {    //10^(e1-e2-x1) doesn't fit in 64 bits, but C1 does
                            __mul_128x64_to_128(&C1, C1_lo, bid_ten2k128[scale - 20])
                        } else {    // if (scale >= 1
                            // if 1 <= scale <= 19 then 10^(e1-e2-x1) fits in 64 bits
                            if q1 <= 19 {    // C1 fits in 64 bits
                                __mul_64x64_to_128MACH(&C1, C1_lo, bid_ten2k64[scale]);
                            } else {    // q1 >= 20
                                C1.hi = C1_hi
                                C1.lo = C1_lo
                                __mul_128x64_to_128(&C1, bid_ten2k64[scale], C1);
                            }
                        }
                        let tmp64 = C1.lo    // C1.hi, C1.lo contains C1 * 10^(e1-e2-x1)
                        
                        // now round C2 to q2-x1 = 1 decimal digit
                        // C2' = C2 + 1/2 * 10^x1 = C2 + 5 * 10^(x1-1)
                        let ind = x1 - 1    // -1 <= ind <= P34 - 2
                        if ind >= 0 {    // if (x1 >= 1)
                            C2.lo = C2_lo
                            C2.hi = C2_hi
                            if ind <= 18 {
                                C2.lo = C2.lo + bid_midpoint64[ind]
                                if C2.lo < C2_lo { C2.hi+=1 }
                            } else {    // 19 <= ind <= 32
                                C2.lo = C2.lo + bid_midpoint128[ind - 19].lo
                                C2.hi = C2.hi + bid_midpoint128[ind - 19].hi
                                if C2.lo < C2_lo { C2.hi+=1 }
                            }
                            // the approximation of 10^(-x1) was rounded up to 118 bits
                            __mul_128x128_to_256(&R256, C2, bid_ten2mk128[ind]);    // R256 = C2*, f2*
                            // calculate C2* and f2*
                            // C2* is actually floor(C2*) in this case
                            // C2* and f2* need shifting and masking, as shown by
                            // bid_shiftright128[] and bid_maskhigh128[]
                            // the top Ex bits of 10^(-x1) are T* = bid_ten2mk128trunc[ind], e.g.
                            // if x1=1, T*=bid_ten2mk128trunc[0]=0x19999999999999999999999999999999
                            // if (0 < f2* < 10^(-x1)) then
                            //   if floor(C1+C2*) is even then C2* = floor(C2*) - logical right
                            //       shift; C2* has p decimal digits, correct by Prop. 1)
                            //   else if floor(C1+C2*) is odd C2* = floor(C2*)-1 (logical right
                            //       shift; C2* has p decimal digits, correct by Pr. 1)
                            // else
                            //   C2* = floor(C2*) (logical right shift; C has p decimal digits,
                            //       correct by Property 1)
                            // n = C2* * 10^(e2+x1)
                            if ind <= 2 {
                                highf2star.hi = 0x0
                                highf2star.lo = 0x0   // low f2* ok
                            } else if ind <= 21 {
                                highf2star.hi = 0x0
                                highf2star.lo = R256.w[2] & bid_maskhigh128[ind]    // low f2* ok
                            } else {
                                highf2star.hi = R256.w[3] & bid_maskhigh128[ind]
                                highf2star.lo = R256.w[2]    // low f2* is ok
                            }
                            
                            // shift right C2* by Ex-128 = bid_shiftright128[ind]
                            if ind >= 3 {
                                let shift = bid_shiftright128[ind]
                                if shift < 64 {    // 3 <= shift <= 63
                                    R256.w[2] =
                                    (R256.w[2] >> shift) | (R256.w[3] << (64 - shift))
                                    R256.w[3] = (R256.w[3] >> shift)
                                } else {    // 66 <= shift <= 102
                                    R256.w[2] = (R256.w[3] >> (shift - 64))
                                    R256.w[3] = 0x0
                                }
                            }
                            // redundant
                            is_inexact_lt_midpoint = false
                            is_inexact_gt_midpoint = false
                            is_midpoint_lt_even = false
                            is_midpoint_gt_even = false
                            
                            // determine inexactness of the rounding of C2*
                            // (cannot be followed by a second rounding)
                            // if (0 < f2* - 1/2 < 10^(-x1)) then
                            //   the result is exact
                            // else (if f2* - 1/2 > T* then)
                            //   the result of is inexact
                            if ind <= 2 {
                                if R256.w[1] > MASK_SIGN || (R256.w[1] == MASK_SIGN && R256.w[0] > 0x0) {
                                    // f2* > 1/2 and the result may be exact
                                    let tmp64A = R256.w[1] - MASK_SIGN    // f* - 1/2
                                    if ((tmp64A > bid_ten2mk128trunc[ind].hi || (tmp64A == bid_ten2mk128trunc[ind].hi &&
                                        R256.w[0] >= bid_ten2mk128trunc[ind].lo))) {
                                        // set the inexact flag
                                        pfpsf.insert(.inexact)
                                        // this rounding is applied to C2 only!
                                        // x_sign != y_sign
                                        is_inexact_gt_midpoint = true
                                    }    // else the result is exact
                                    // rounding down, unless a midpoint in [ODD, EVEN]
                                } else {    // the result is inexact; f2* <= 1/2
                                    // set the inexact flag
                                    pfpsf.insert(.inexact)
                                    // this rounding is applied to C2 only!
                                    // x_sign != y_sign
                                    is_inexact_lt_midpoint = true
                                }
                            } else if ind <= 21 {    // if 3 <= ind <= 21
                                if (highf2star.hi > 0x0 || (highf2star.hi == 0x0 && highf2star.lo > bid_onehalf128[ind])
                                    || (highf2star.hi == 0x0 && highf2star.lo == bid_onehalf128[ind] &&
                                        (R256.w[1] != 0 || R256.w[0] != 0))) {
                                    // f2* > 1/2 and the result may be exact
                                    // Calculate f2* - 1/2
                                    let tmp64A = highf2star.lo - bid_onehalf128[ind]
                                    var tmp64B = highf2star.hi
                                    if tmp64A > highf2star.lo {
                                        tmp64B-=1
                                    }
                                    if (tmp64B != 0 || tmp64A != 0 || R256.w[1] > bid_ten2mk128trunc[ind].hi ||
                                        (R256.w[1] == bid_ten2mk128trunc[ind].hi && R256.w[0] > bid_ten2mk128trunc[ind].lo)) {
                                        // set the inexact flag
                                        pfpsf.insert(.inexact)
                                        // this rounding is applied to C2 only!
                                        // x_sign != y_sign
                                        is_inexact_gt_midpoint = true
                                    }    // else the result is exact
                                } else {    // the result is inexact; f2* <= 1/2
                                    // set the inexact flag
                                    pfpsf.insert(.inexact)
                                    // this rounding is applied to C2 only!
                                    // x_sign != y_sign
                                    is_inexact_lt_midpoint = true
                                }
                            } else {    // if 22 <= ind <= 33
                                if (highf2star.hi > bid_onehalf128[ind] || (highf2star.hi == bid_onehalf128[ind]
                                    && (highf2star.lo != 0 || R256.w[1] != 0 || R256.w[0] != 0))) {
                                    // f2* > 1/2 and the result may be exact
                                    // Calculate f2* - 1/2
                                    // tmp64A = highf2star.lo;
                                    let tmp64B = highf2star.hi - bid_onehalf128[ind];
                                    if (tmp64B != 0  || highf2star.lo != 0 || R256.w[1] > bid_ten2mk128trunc[ind].hi ||
                                        (R256.w[1] == bid_ten2mk128trunc[ind].hi && R256.w[0] > bid_ten2mk128trunc[ind].lo)) {
                                        // set the inexact flag
                                        pfpsf.insert(.inexact)
                                        // this rounding is applied to C2 only!
                                        // x_sign != y_sign
                                        is_inexact_gt_midpoint = true
                                    }    // else the result is exact
                                } else {    // the result is inexact; f2* <= 1/2
                                    // set the inexact flag
                                    pfpsf.insert(.inexact)
                                    // this rounding is applied to C2 only!
                                    // x_sign != y_sign
                                    is_inexact_lt_midpoint = true
                                }
                            }
                            // check for midpoints after determining inexactness
                            if ((R256.w[1] != 0 || R256.w[0] != 0 ) && (highf2star.hi == 0) && (highf2star.lo == 0)
                                && (R256.w[1] < bid_ten2mk128trunc[ind].hi
                                || (R256.w[1] == bid_ten2mk128trunc[ind].hi && R256.w[0] <= bid_ten2mk128trunc[ind].lo))) {
                                // the result is a midpoint
                                if (tmp64 + R256.w[2]) & 0x01 != 0 {    // MP in [EVEN, ODD]
                                    // if floor(C2*) is odd C = floor(C2*) - 1; the result may be 0
                                    R256.w[2] &-= 1
                                    if R256.w[2] == 0xffff_ffff_ffff_ffff { R256.w[3]-=1 }
                                    
                                    // this rounding is applied to C2 only!
                                    // x_sign != y_sign
                                    is_midpoint_lt_even = true
                                    is_inexact_lt_midpoint = false
                                    is_inexact_gt_midpoint = false
                                } else {
                                    // else MP in [ODD, EVEN]
                                    // this rounding is applied to C2 only!
                                    // x_sign != y_sign
                                    is_midpoint_gt_even = true
                                    is_inexact_lt_midpoint = false
                                    is_inexact_gt_midpoint = false
                                }
                            }
                        } else {    // if (ind == -1) only when x1 = 0
                            R256.w[2] = C2_lo;
                            R256.w[3] = C2_hi;
                            is_midpoint_lt_even = false
                            is_midpoint_gt_even = false
                            is_inexact_lt_midpoint = false
                            is_inexact_gt_midpoint = false
                        }
                        // and now subtract C1 * 10^(e1-e2-x1) - (C2 * 10^(-x1))rnd,P34
                        // because x_sign != y_sign this last operation is exact
                        C1.lo = C1.lo - R256.w[2]
                        C1.hi = C1.hi - R256.w[3]
                        if C1.lo > tmp64 { C1.hi-=1 } // borrow
                        if C1.hi >= MASK_SIGN {    // negative coefficient!
                            C1.lo = ~C1.lo
                            C1.lo+=1
                            C1.hi = ~C1.hi
                            if C1.lo == 0x0 { C1.hi+=1 }
                            tmp_sign = y_signi    // the result will have the sign of y
                        } else {
                            tmp_sign = x_signi
                        }
                        // the difference has exactly P34 digits
                        x_signi = tmp_sign
                        if x1 >= 1 {
                            y_exp = y_exp + UInt64(x1 << 49)
                        }
                        C1_hi = C1.hi
                        C1_lo = C1.lo
                        // general correction from RN to RA, RM, RP, RZ; result uses y_exp
                        if (rnd_mode != BID_ROUNDING_TO_NEAREST) {
                            if ((!x_sign && ((rnd_mode == BID_ROUNDING_UP && is_inexact_lt_midpoint) ||
                                ((rnd_mode == BID_ROUNDING_TIES_AWAY || rnd_mode == BID_ROUNDING_UP) && is_midpoint_gt_even))) ||
                                (x_sign && ((rnd_mode == BID_ROUNDING_DOWN && is_inexact_lt_midpoint) ||
                                ((rnd_mode == BID_ROUNDING_TIES_AWAY || rnd_mode == BID_ROUNDING_DOWN) && is_midpoint_gt_even)))) {
                                // C1 = C1 + 1
                                C1_lo = C1_lo + 1
                                if C1_lo == 0 { C1_hi = C1_hi + 1 } // rounding overflow in the low 64 bits
                                if (C1_hi == Ten34M1.hi && C1_lo == Ten34M1.lo+1) {
                                    // C1 = 10^34 => rounding overflow
                                    C1_hi = Ten33M1.hi
                                    C1_lo = Ten33M1.lo+1    // 10^33
                                    y_exp = y_exp + EXP_P1
                                }
                            } else if ((is_midpoint_lt_even || is_inexact_gt_midpoint) && (((x_sign)
                                         && (rnd_mode == BID_ROUNDING_UP || rnd_mode == BID_ROUNDING_TO_ZERO)) ||
                                            (!x_sign && (rnd_mode == BID_ROUNDING_DOWN || rnd_mode == BID_ROUNDING_TO_ZERO)))) {
                                // C1 = C1 - 1
                                C1_lo = C1_lo &- 1
                                if C1_lo == 0xffff_ffff_ffff_ffff { C1_hi-=1 }
                                
                                // check if we crossed into the lower decade
                                if (C1_hi == Ten33M1.hi && C1_lo == Ten33M1.lo) {    // 10^33 - 1
                                    C1_hi = Ten34M1.hi    // 10^34 - 1
                                    C1_lo = Ten34M1.lo
                                    y_exp = y_exp - EXP_P1
                                    // no underflow, because delta + q2 >= P34 + 1
                                }
                            } else {
                                // exact, the result is already correct
                            }
                        }
                        // assemble the result
                        res.hi = x_signi | y_exp | C1_hi
                        res.lo = C1_lo
                    }
                }    // end delta = P34
            } else {    // if (|delta| <= P34 - 1)
                if delta >= 0 {    // if (0 <= delta <= P34 - 1)
                    if delta <= P34 - 1 - q2 {
                        // calculate C' directly; the result is exact
                        // in this case 1<=q1<=P34-1, 1<=q2<=P34-1 and 0 <= e1-e2 <= P34-2
                        // The coefficient of the result is C1 * 10^(e1-e2) + C2 and the
                        // exponent is e2; either C1 or 10^(e1-e2) may not fit is 64 bits,
                        // but their product fits with certainty in 128 bits (actually in 113)
                        let scale = delta - q1 + q2    // scale = (int)(e1 >> 49) - (int)(e2 >> 49)
                        
                        if scale >= 20 {    // 10^(e1-e2) does not fit in 64 bits, but C1 does
                            __mul_128x64_to_128(&C1, C1_lo, bid_ten2k128[scale - 20])
                            C1_hi = C1.hi
                            C1_lo = C1.lo
                        } else if scale >= 1 {
                            // if 1 <= scale <= 19 then 10^(e1-e2) fits in 64 bits
                            if q1 <= 19 {    // C1 fits in 64 bits
                                __mul_64x64_to_128MACH(&C1, C1_lo, bid_ten2k64[scale])
                            } else {    // q1 >= 20
                                C1.hi = C1_hi
                                C1.lo = C1_lo
                                __mul_128x64_to_128(&C1, bid_ten2k64[scale], C1)
                            }
                            C1_hi = C1.hi
                            C1_lo = C1.lo
                        } else {    // if (scale == 0) C1 is unchanged
                            C1.lo = C1_lo    // C1.hi = C1_hi;
                        }
                        // now add C2
                        if x_sign == y_sign {
                            // the result cannot overflow
                            C1_lo = C1_lo + C2_lo
                            C1_hi = C1_hi + C2_hi
                            if C1_lo < C1.lo {
                                C1_hi+=1
                            }
                        } else {    // if x_sign != y_sign
                            C1_lo = C1_lo - C2_lo
                            C1_hi = C1_hi - C2_hi
                            if C1_lo > C1.lo {
                                C1_hi-=1
                            }
                            // the result can be zero, but it cannot overflow
                            if C1_lo == 0 && C1_hi == 0 {
                                // assemble the result
                                if (x_exp < y_exp) {
                                    res.hi = x_exp;
                                } else {
                                    res.hi = y_exp;
                                }
                                res.lo = 0;
                                if rnd_mode == BID_ROUNDING_DOWN {
                                    res.hi |= MASK_SIGN
                                }
                                BID_SWAP128(&res)
                                return res
                            }
                            if C1_hi >= MASK_SIGN {    // negative coefficient!
                                C1_lo = ~C1_lo
                                C1_lo+=1
                                C1_hi = ~C1_hi
                                if C1_lo == 0x0 {
                                    C1_hi+=1
                                }
                                x_signi = y_signi    // the result will have the sign of y
                            }
                        }
                        // assemble the result
                        res.hi = x_signi | y_exp | C1_hi
                        res.lo = C1_lo
                    } else if delta == P34 - q2 {
                        // calculate C' directly; the result may be inexact if it requires
                        // P34+1 decimal digits; in this case the 'cutoff' point for addition
                        // is at the position of the lsb of C2, so 0 <= e1-e2 <= P34-1
                        // The coefficient of the result is C1 * 10^(e1-e2) + C2 and the
                        // exponent is e2; either C1 or 10^(e1-e2) may not fit is 64 bits,
                        // but their product fits with certainty in 128 bits (actually in 113)
                        let scale = delta - q1 + q2    // scale = (int)(e1 >> 49) - (int)(e2 >> 49)
                        if scale >= 20 {    // 10^(e1-e2) does not fit in 64 bits, but C1 does
                            __mul_128x64_to_128(&C1, C1_lo, bid_ten2k128[scale - 20])
                        } else if scale >= 1 {
                            // if 1 <= scale <= 19 then 10^(e1-e2) fits in 64 bits
                            if q1 <= 19 {    // C1 fits in 64 bits
                                __mul_64x64_to_128MACH(&C1, C1_lo, bid_ten2k64[scale])
                            } else {    // q1 >= 20
                                C1.hi = C1_hi
                                C1.lo = C1_lo
                                __mul_128x64_to_128(&C1, bid_ten2k64[scale], C1)
                            }
                        } else {    // if (scale == 0) C1 is unchanged
                            C1.hi = C1_hi
                            C1.lo = C1_lo   // only the low part is necessary
                        }
                        C1_hi = C1.hi
                        C1_lo = C1.lo
                        // now add C2
                        if x_sign == y_sign {
                            // the result can overflow!
                            C1_lo = C1_lo + C2_lo
                            C1_hi = C1_hi + C2_hi
                            if C1_lo < C1.lo {
                                C1_hi+=1
                            }
                            // test for overflow, possible only when C1 >= 10^34
                            if (C1_hi > Ten34M1.hi || (C1_hi == Ten34M1.hi && C1_lo >= Ten34M1.lo+1)) {    // C1 >= 10^34
                                // in this case q = P34 + 1 and x = q - P34 = 1, so multiply
                                // C'' = C'+ 5 = C1 + 5 by k1 ~ 10^(-1) calculated for P34 + 1
                                // decimal digits
                                // Calculate C'' = C' + 1/2 * 10^x
                                if C1_lo >= 0xfffffffffffffffb {    // low half add has carry
                                    C1_lo = C1_lo + 5
                                    C1_hi = C1_hi + 1
                                } else {
                                    C1_lo = C1_lo + 5
                                }
                                // the approximation of 10^(-1) was rounded up to 118 bits
                                // 10^(-1) =~ 33333333333333333333333333333400 * 2^-129
                                // 10^(-1) =~ 19999999999999999999999999999a00 * 2^-128
                                C1.hi = C1_hi
                                C1.lo = C1_lo   // C''
                                ten2m1.hi = 0x1999_9999_9999_9999
                                ten2m1.lo = 0x9999999999999a00
                                __mul_128x128_to_256(&P256, C1, ten2m1);    // P256 = C*, f*
                                // C* is actually floor(C*) in this case
                                // the top Ex = 128 bits of 10^(-1) are
                                // T* = 0x00199999999999999999999999999999
                                // if (0 < f* < 10^(-x)) then
                                //   if floor(C*) is even then C = floor(C*) - logical right
                                //       shift; C has p decimal digits, correct by Prop. 1)
                                //   else if floor(C*) is odd C = floor(C*) - 1 (logical right
                                //       shift; C has p decimal digits, correct by Pr. 1)
                                // else
                                //   C = floor(C*) (logical right shift; C has p decimal digits,
                                //       correct by Property 1)
                                // n = C * 10^(e2+x)
                                if ((P256.w[1] != 0  || P256.w[0] != 0 )
                                    && (P256.w[1] < 0x1999_9999_9999_9999 ||
                                        (P256.w[1] == 0x1999_9999_9999_9999 && P256.w[0] <= 0x9999_9999_9999_9999))) {
                                    // the result is a midpoint
                                    if (P256.w[2] & 0x01 != 0 ) {
                                        is_midpoint_gt_even = true
                                        // if floor(C*) is odd C = floor(C*) - 1; the result is not 0
                                        P256.w[2]-=1
                                        if (P256.w[2] == 0xffff_ffff_ffff_ffff) {
                                            P256.w[3]-=1
                                        }
                                    } else {
                                        is_midpoint_lt_even = true
                                    }
                                }
                                // n = Cstar * 10^(e2+1)
                                y_exp = y_exp + EXP_P1;
                                // C* != 10^P because C* has P34 digits
                                // check for overflow
                                if (y_exp == EXP_MAX_P1 && (rnd_mode == BID_ROUNDING_TO_NEAREST || rnd_mode == BID_ROUNDING_TIES_AWAY)) {
                                    // overflow for RN
                                    res.hi = x_signi | MASK_INF    // +/-inf
                                    res.lo = 0x0;
                                    // set the inexact flag
                                    pfpsf.insert(.inexact)
                                    // set the overflow flag
                                    pfpsf.insert(.overflow)
                                    BID_SWAP128(&res)
                                    return res
                                }
                                // if (0 < f* - 1/2 < 10^(-x)) then
                                //   the result of the addition is exact
                                // else
                                //   the result of the addition is inexact
                                if (P256.w[1] > MASK_SIGN || (P256.w[1] == MASK_SIGN && P256.w[0] > 0x0)) {
                                    // the result may be exact
                                    let tmp64 = P256.w[1] - MASK_SIGN;    // f* - 1/2
                                    if ((tmp64 > 0x1999_9999_9999_9999 ||
                                         (tmp64 == 0x1999_9999_9999_9999 && P256.w[0] >= 0x9999_9999_9999_9999))) {
                                        // set the inexact flag
                                        pfpsf.insert(.inexact)
                                        is_inexact = true
                                    }    // else the result is exact
                                } else {    // the result is inexact
                                    // set the inexact flag
                                    pfpsf.insert(.inexact)
                                    is_inexact = true
                                }
                                C1_hi = P256.w[3]
                                C1_lo = P256.w[2]
                                if !is_midpoint_gt_even && !is_midpoint_lt_even {
                                    is_inexact_lt_midpoint = is_inexact && (P256.w[1] & MASK_SIGN != 0)
                                    is_inexact_gt_midpoint = is_inexact && (P256.w[1] & MASK_SIGN == 0)
                                }
                                // general correction from RN to RA, RM, RP, RZ;
                                // result uses y_exp
                                if (rnd_mode != BID_ROUNDING_TO_NEAREST) {
                                    if ((!x_sign && ((rnd_mode == BID_ROUNDING_UP && is_inexact_lt_midpoint) ||
                                          ((rnd_mode == BID_ROUNDING_TIES_AWAY || rnd_mode == BID_ROUNDING_UP)
                                           && is_midpoint_gt_even))) ||
                                        (x_sign && ((rnd_mode == BID_ROUNDING_DOWN && is_inexact_lt_midpoint) ||
                                        ((rnd_mode == BID_ROUNDING_TIES_AWAY || rnd_mode == BID_ROUNDING_DOWN) &&
                                        is_midpoint_gt_even))))
                                    {
                                        // C1 = C1 + 1
                                        C1_lo = C1_lo + 1
                                        if C1_lo == 0 {    // rounding overflow in the low 64 bits
                                            C1_hi = C1_hi + 1
                                        }
                                        if C1_hi == Ten34M1.hi && C1_lo == Ten34M1.lo+1 {
                                            // C1 = 10^34 => rounding overflow
                                            C1_hi = Ten33M1.hi
                                            C1_lo = Ten33M1.lo+1   // 10^33
                                            y_exp = y_exp + EXP_P1
                                        }
                                    } else if ((is_midpoint_lt_even || is_inexact_gt_midpoint) &&
                                               ((x_sign && (rnd_mode == BID_ROUNDING_UP || rnd_mode == BID_ROUNDING_TO_ZERO))
                                                || (!x_sign && (rnd_mode == BID_ROUNDING_DOWN || rnd_mode == BID_ROUNDING_TO_ZERO)))) {
                                        // C1 = C1 - 1
                                        C1_lo = C1_lo &- 1
                                        if C1_lo == 0xffff_ffff_ffff_ffff {
                                            C1_hi-=1
                                        }
                                        // check if we crossed into the lower decade
                                        if C1_hi == Ten33M1.hi && C1_lo == Ten33M1.lo {    // 10^33 - 1
                                            C1_hi = Ten34M1.hi;   // 10^34 - 1
                                            C1_lo = Ten34M1.lo
                                            y_exp = y_exp - EXP_P1
                                            // no underflow, because delta + q2 >= P34 + 1
                                        }
                                    } else {
                                        // exact, the result is already correct
                                    }
                                    // in all cases check for overflow (RN and RA solved already)
                                    if y_exp == EXP_MAX_P1 {    // overflow
                                        if (rnd_mode == BID_ROUNDING_DOWN && x_sign) ||    // RM and res < 0
                                            (rnd_mode == BID_ROUNDING_UP && !x_sign) {    // RP and res > 0
                                            C1_hi = MASK_INF    // +inf
                                            C1_lo = 0x0
                                        } else {    // RM and res > 0, RP and res < 0, or RZ
                                            C1_hi = 0x5fffed09bead87c0
                                            C1_lo = Ten34M1.lo
                                        }
                                        y_exp = 0    // x_sign is preserved
                                        // set the inexact flag (in case the exact addition was exact)
                                        pfpsf.insert(.inexact)
                                        // set the overflow flag
                                        pfpsf.insert(.overflow)
                                    }
                                }
                            }    // else if (C1 < 10^34) then C1 is the coeff.; the result is exact
                        } else {    // if x_sign != y_sign the result is exact
                            C1_lo = C1_lo - C2_lo
                            C1_hi = C1_hi - C2_hi
                            if C1_lo > C1.lo { C1_hi-=1 }
                            
                            // the result can be zero, but it cannot overflow
                            if C1_lo == 0 && C1_hi == 0 {
                                // assemble the result
                                if x_exp < y_exp {
                                    res.hi = x_exp
                                } else {
                                    res.hi = y_exp
                                }
                                res.lo = 0
                                if rnd_mode == BID_ROUNDING_DOWN {
                                    res.hi |= MASK_SIGN
                                }
                                BID_SWAP128(&res)
                                return res
                            }
                            if C1_hi >= MASK_SIGN {    // negative coefficient!
                                C1_lo = ~C1_lo
                                C1_lo+=1
                                C1_hi = ~C1_hi
                                if C1_lo == 0x0 { C1_hi+=1 }
                                x_signi = y_signi    // the result will have the sign of y
                            }
                        }
                        // assemble the result
                        res.hi = x_signi | y_exp | C1_hi
                        res.lo = C1_lo
                    } else {    // if (delta >= P34 + 1 - q2)
                        // instead of C' = (C1 * 10^(e1-e2) + C2)rnd,P34
                        // calculate C' = C1 * 10^(e1-e2-x1) + (C2 * 10^(-x1))rnd,P34
                        // where x1 = q1 + e1 - e2 - P34, 1 <= x1 <= P34 - 1
                        // In most cases C' will have P34 digits, and n = C' * 10^(e2+x1)
                        // If the result has P34+1 digits, redo the steps above with x1+1
                        // If the result has P34-1 digits or less, redo the steps above with
                        // x1-1 but only if initially x1 >= 1
                        // NOTE: these two steps can be improved, e.g we could guess if
                        // P34+1 or P34-1 digits will be obtained by adding/subtracting just
                        // the top 64 bits of the two operands
                        // The result cannot be zero, but it can overflow
                        var x1 = delta + q2 - P34;    // 1 <= x1 <= P34-1
                        var tmp_inexact = false
                        
                        //                   roundC2:
                        while true {  // roundC2 loop
                            // Calculate C1 * 10^(e1-e2-x1) where 0 <= e1-e2-x1 <= P34 - 1
                            // scale = (int)(e1 >> 49) - (int)(e2 >> 49) - x1; 0 <= scale <= P34-1
                            let scale = delta - q1 + q2 - x1    // scale = e1 - e2 - x1 = P34 - q1
                            // either C1 or 10^(e1-e2-x1) may not fit is 64 bits,
                            // but their product fits with certainty in 128 bits (actually in 113)
                            if scale >= 20 {    //10^(e1-e2-x1) doesn't fit in 64 bits, but C1 does
                                __mul_128x64_to_128(&C1, C1_lo, bid_ten2k128[scale - 20])
                            } else if scale >= 1 {
                                // if 1 <= scale <= 19 then 10^(e1-e2-x1) fits in 64 bits
                                if q1 <= 19 {    // C1 fits in 64 bits
                                    __mul_64x64_to_128MACH(&C1, C1_lo, bid_ten2k64[scale])
                                } else {    // q1 >= 20
                                    C1.hi = C1_hi
                                    C1.lo = C1_lo
                                    __mul_128x64_to_128(&C1, bid_ten2k64[scale], C1)
                                }
                            } else {    // if (scale == 0) C1 is unchanged
                                C1.hi = C1_hi
                                C1.lo = C1_lo
                            }
                            let tmp64 = C1.lo    // C1.hi, C1.lo contains C1 * 10^(e1-e2-x1)
                            
                            // now round C2 to q2-x1 decimal digits, where 1<=x1<=q2-1<=P34-1
                            // (but if we got here a second time after x1 = x1 - 1, then
                            // x1 >= 0; note that for x1 = 0 C2 is unchanged)
                            // C2' = C2 + 1/2 * 10^x1 = C2 + 5 * 10^(x1-1)
                            let ind = x1 - 1    // 0 <= ind <= q2-2<=P34-2=32; but note that if x1 = 0
                            // during a second pass, then ind = -1
                            if ind >= 0 {    // if (x1 >= 1)
                                C2.lo = C2_lo
                                C2.hi = C2_hi
                                if ind <= 18 {
                                    C2.lo = C2.lo + bid_midpoint64[ind]
                                    if C2.lo < C2_lo { C2.hi+=1 }
                                } else {    // 19 <= ind <= 32
                                    C2.lo = C2.lo + bid_midpoint128[ind - 19].lo
                                    C2.hi = C2.hi + bid_midpoint128[ind - 19].hi
                                    if (C2.lo < C2_lo) { C2.hi+=1 }
                                }
                                // the approximation of 10^(-x1) was rounded up to 118 bits
                                __mul_128x128_to_256(&R256, C2, bid_ten2mk128[ind]);    // R256 = C2*, f2*
                                // calculate C2* and f2*
                                // C2* is actually floor(C2*) in this case
                                // C2* and f2* need shifting and masking, as shown by
                                // bid_shiftright128[] and bid_maskhigh128[]
                                // the top Ex bits of 10^(-x1) are T* = bid_ten2mk128trunc[ind], e.g.
                                // if x1=1, T*=bid_ten2mk128trunc[0]=0x19999999999999999999999999999999
                                // if (0 < f2* < 10^(-x1)) then
                                //   if floor(C1+C2*) is even then C2* = floor(C2*) - logical right
                                //       shift; C2* has p decimal digits, correct by Prop. 1)
                                //   else if floor(C1+C2*) is odd C2* = floor(C2*)-1 (logical right
                                //       shift; C2* has p decimal digits, correct by Pr. 1)
                                // else
                                //   C2* = floor(C2*) (logical right shift; C has p decimal digits,
                                //       correct by Property 1)
                                // n = C2* * 10^(e2+x1)
                                
                                if ind <= 2 {
                                    highf2star.hi = 0x0
                                    highf2star.lo = 0x0    // low f2* ok
                                } else if ind <= 21 {
                                    highf2star.hi = 0x0
                                    highf2star.lo = R256.w[2] & bid_maskhigh128[ind]    // low f2* ok
                                } else {
                                    highf2star.hi = R256.w[3] & bid_maskhigh128[ind]
                                    highf2star.lo = R256.w[2]    // low f2* is ok
                                }
                                // shift right C2* by Ex-128 = bid_shiftright128[ind]
                                if ind >= 3 {
                                    let shift = bid_shiftright128[ind]
                                    if shift < 64 {    // 3 <= shift <= 63
                                        R256.w[2] = (R256.w[2] >> shift) | (R256.w[3] << (64 - shift))
                                        R256.w[3] = (R256.w[3] >> shift)
                                    } else {    // 66 <= shift <= 102
                                        R256.w[2] = (R256.w[3] >> (shift - 64))
                                        R256.w[3] = 0x0
                                    }
                                }
                                if second_pass {
                                    is_inexact_lt_midpoint = false
                                    is_inexact_gt_midpoint = false
                                    is_midpoint_lt_even = false
                                    is_midpoint_gt_even = false
                                }
                                // determine inexactness of the rounding of C2* (this may be
                                // followed by a second rounding only if we get P34+1
                                // decimal digits)
                                // if (0 < f2* - 1/2 < 10^(-x1)) then
                                //   the result is exact
                                // else (if f2* - 1/2 > T* then)
                                //   the result of is inexact
                                if ind <= 2 {
                                    if R256.w[1] > MASK_SIGN || (R256.w[1] == MASK_SIGN && R256.w[0] > 0x0) {
                                        // f2* > 1/2 and the result may be exact
                                        let tmp64A = R256.w[1] - MASK_SIGN;    // f* - 1/2
                                        if ((tmp64A > bid_ten2mk128trunc[ind].hi ||
                                            (tmp64A == bid_ten2mk128trunc[ind].hi && R256.w[0] >= bid_ten2mk128trunc[ind].lo))) {
                                            // set the inexact flag
                                            // pfpsf.insert(.inexact)
                                            tmp_inexact = true    // may be set again during a second pass
                                            // this rounding is applied to C2 only!
                                            if x_sign == y_sign {
                                                is_inexact_lt_midpoint = true
                                            } else {   // if (x_sign != y_sign)
                                                is_inexact_gt_midpoint = true
                                            }
                                        }    // else the result is exact
                                        // rounding down, unless a midpoint in [ODD, EVEN]
                                    } else {    // the result is inexact; f2* <= 1/2
                                        // set the inexact flag
                                        // pfpsf.insert(.inexact)
                                        tmp_inexact = true    // just in case we will round a second time
                                        // rounding up, unless a midpoint in [EVEN, ODD]
                                        // this rounding is applied to C2 only!
                                        if x_sign == y_sign {
                                            is_inexact_gt_midpoint = true
                                        } else { // if (x_sign != y_sign)
                                            is_inexact_lt_midpoint = true
                                        }
                                    }
                                } else if (ind <= 21) {    // if 3 <= ind <= 21
                                    if (highf2star.hi > 0x0 || (highf2star.hi == 0x0 && highf2star.lo > bid_onehalf128[ind])
                                        || (highf2star.hi == 0x0 && highf2star.lo == bid_onehalf128[ind]
                                            && (R256.w[1] != 0  || R256.w[0] != 0 ))) {
                                        // f2* > 1/2 and the result may be exact
                                        // Calculate f2* - 1/2
                                        let tmp64A = highf2star.lo - bid_onehalf128[ind]
                                        var tmp64B = highf2star.hi
                                        if tmp64A > highf2star.lo { tmp64B-=1 }
                                        if (tmp64B != 0  || tmp64A != 0
                                            || R256.w[1] > bid_ten2mk128trunc[ind].hi
                                            || (R256.w[1] == bid_ten2mk128trunc[ind].hi
                                                && R256.w[0] > bid_ten2mk128trunc[ind].lo)) {
                                            // set the inexact flag
                                            // pfpsf.insert(.inexact)
                                            tmp_inexact = true    // may be set again during a second pass
                                            // this rounding is applied to C2 only!
                                            if x_sign == y_sign {
                                                is_inexact_lt_midpoint = true
                                            } else {   // if (x_sign != y_sign)
                                                is_inexact_gt_midpoint = true
                                            }
                                        }    // else the result is exact
                                    } else {    // the result is inexact; f2* <= 1/2
                                        // set the inexact flag
                                        // pfpsf.insert(.inexact)
                                        tmp_inexact = true    // may be set again during a second pass
                                        // rounding up, unless a midpoint in [EVEN, ODD]
                                        // this rounding is applied to C2 only!
                                        if x_sign == y_sign {
                                            is_inexact_gt_midpoint = true
                                        } else {   // if (x_sign != y_sign)
                                            is_inexact_lt_midpoint = true
                                        }
                                    }
                                } else {    // if 22 <= ind <= 33
                                    if (highf2star.hi > bid_onehalf128[ind] || (highf2star.hi == bid_onehalf128[ind]
                                        && (highf2star.lo != 0  || R256.w[1] != 0 || R256.w[0] != 0 ))) {
                                        // f2* > 1/2 and the result may be exact
                                        // Calculate f2* - 1/2
                                        // tmp64A = highf2star.lo;
                                        let tmp64B = highf2star.hi - bid_onehalf128[ind];
                                        if (tmp64B != 0  || highf2star.lo != 0 || R256.w[1] > bid_ten2mk128trunc[ind].hi
                                            || (R256.w[1] == bid_ten2mk128trunc[ind].hi && R256.w[0] > bid_ten2mk128trunc[ind].lo)) {
                                            // set the inexact flag
                                            // pfpsf.insert(.inexact)
                                            tmp_inexact = true    // may be set again during a second pass
                                            // this rounding is applied to C2 only!
                                            if x_sign == y_sign {
                                                is_inexact_lt_midpoint = true
                                            } else {  // if (x_sign != y_sign)
                                                is_inexact_gt_midpoint = true
                                            }
                                        }    // else the result is exact
                                    } else {    // the result is inexact; f2* <= 1/2
                                        // set the inexact flag
                                        // pfpsf.insert(.inexact)
                                        tmp_inexact = true    // may be set again during a second pass
                                        // rounding up, unless a midpoint in [EVEN, ODD]
                                        // this rounding is applied to C2 only!
                                        if x_sign == y_sign {
                                            is_inexact_gt_midpoint = true
                                        } else  { // if (x_sign != y_sign)
                                            is_inexact_lt_midpoint = true
                                        }
                                    }
                                }
                                // check for midpoints
                                if ((R256.w[1] != 0  || R256.w[0] != 0 ) && (highf2star.hi == 0)
                                    && (highf2star.lo == 0) && (R256.w[1] < bid_ten2mk128trunc[ind].hi
                                    || (R256.w[1] == bid_ten2mk128trunc[ind].hi && R256.w[0] <= bid_ten2mk128trunc[ind].lo))) {
                                    // the result is a midpoint
                                    if ((tmp64 + R256.w[2]) & 0x01) != 0 {    // MP in [EVEN, ODD]
                                        // if floor(C2*) is odd C = floor(C2*) - 1; the result may be 0
                                        R256.w[2] &-= 1
                                        if R256.w[2] == 0xffff_ffff_ffff_ffff { R256.w[3] -= 1 }
                                        
                                        // this rounding is applied to C2 only!
                                        if x_sign == y_sign {
                                            is_midpoint_gt_even = true
                                        } else {   // if (x_sign != y_sign)
                                            is_midpoint_lt_even = true
                                        }
                                        is_inexact_lt_midpoint = false
                                        is_inexact_gt_midpoint = false
                                    } else {
                                        // else MP in [ODD, EVEN]
                                        // this rounding is applied to C2 only!
                                        if x_sign == y_sign {
                                            is_midpoint_lt_even = true
                                        } else {   // if (x_sign != y_sign)
                                            is_midpoint_gt_even = true
                                        }
                                        is_inexact_lt_midpoint = false
                                        is_inexact_gt_midpoint = false
                                    }
                                }
                                // end if (ind >= 0)
                            } else {    // if (ind == -1); only during a 2nd pass, and when x1 = 0
                                R256.w[2] = C2_lo
                                R256.w[3] = C2_hi
                                tmp_inexact = false
                                // to correct a possible setting to 1 from 1st pass
                                if second_pass {
                                    is_midpoint_lt_even = false
                                    is_midpoint_gt_even = false
                                    is_inexact_lt_midpoint = false
                                    is_inexact_gt_midpoint = false
                                }
                            }
                            // and now add/subtract C1 * 10^(e1-e2-x1) +/- (C2 * 10^(-x1))rnd,P34
                            if x_sign == y_sign {    // addition; could overflow
                                // no second pass is possible this way (only for x_sign != y_sign)
                                C1.lo = C1.lo + R256.w[2]
                                C1.hi = C1.hi + R256.w[3]
                                if C1.lo < tmp64 { C1.hi+=1 }   // carry
                                
                                // if the sum has P34+1 digits, i.e. C1>=10^34 redo the calculation
                                // with x1=x1+1
                                if C1.hi > Ten34M1.hi || (C1.hi == Ten34M1.hi && C1.lo >= Ten34M1.lo+1) {
                                    // C1 >= 10^34
                                    // chop off one more digit from the sum, but make sure there is
                                    // no double-rounding error (see table - double rounding logic)
                                    // now round C1 from P34+1 to P34 decimal digits
                                    // C1' = C1 + 1/2 * 10 = C1 + 5
                                    if C1.lo >= 0xffff_ffff_ffff_fffb {    // low half add has carry
                                        C1.lo = C1.lo + 5
                                        C1.hi = C1.hi + 1
                                    } else {
                                        C1.lo = C1.lo + 5
                                    }
                                    
                                    // the approximation of 10^(-1) was rounded up to 118 bits
                                    __mul_128x128_to_256(&Q256, C1, bid_ten2mk128[0])    // Q256 = C1*, f1*
                                    
                                    // C1* is actually floor(C1*) in this case
                                    // the top 128 bits of 10^(-1) are
                                    // T* = bid_ten2mk128trunc[0]=0x19999999999999999999999999999999
                                    // if (0 < f1* < 10^(-1)) then
                                    //   if floor(C1*) is even then C1* = floor(C1*) - logical right
                                    //       shift; C1* has p decimal digits, correct by Prop. 1)
                                    //   else if floor(C1*) is odd C1* = floor(C1*) - 1 (logical right
                                    //       shift; C1* has p decimal digits, correct by Pr. 1)
                                    // else
                                    //   C1* = floor(C1*) (logical right shift; C has p decimal digits
                                    //       correct by Property 1)
                                    // n = C1* * 10^(e2+x1+1)
                                    if ((Q256.w[1] != 0 || Q256.w[0] != 0)
                                        && (Q256.w[1] < bid_ten2mk128trunc[0].hi
                                            || (Q256.w[1] == bid_ten2mk128trunc[0].hi
                                                && Q256.w[0] <= bid_ten2mk128trunc[0].lo))) {
                                        // the result is a midpoint
                                        if is_inexact_lt_midpoint {    // for the 1st rounding
                                            is_inexact_gt_midpoint = true
                                            is_inexact_lt_midpoint = false
                                            is_midpoint_gt_even = false
                                            is_midpoint_lt_even = false
                                        } else if is_inexact_gt_midpoint {    // for the 1st rounding
                                            Q256.w[2] &-= 1
                                            if Q256.w[2] == 0xffff_ffff_ffff_ffff { Q256.w[3]-=1 }
                                            is_inexact_gt_midpoint = false
                                            is_inexact_lt_midpoint = true
                                            is_midpoint_gt_even = false
                                            is_midpoint_lt_even = false
                                        } else if (is_midpoint_gt_even) {    // for the 1st rounding
                                            // Note: cannot have is_midpoint_lt_even
                                            is_inexact_gt_midpoint = false
                                            is_inexact_lt_midpoint = true
                                            is_midpoint_gt_even = false
                                            is_midpoint_lt_even = false
                                        } else {    // the first rounding must have been exact
                                            if (Q256.w[2] & 0x01) != 0 {    // MP in [EVEN, ODD]
                                                // the truncated result is correct
                                                Q256.w[2] &-= 1
                                                if Q256.w[2] == 0xffff_ffff_ffff_ffff { Q256.w[3]-=1 }
                                                is_inexact_gt_midpoint = false
                                                is_inexact_lt_midpoint = false
                                                is_midpoint_gt_even = true
                                                is_midpoint_lt_even = false
                                            } else {    // MP in [ODD, EVEN]
                                                is_inexact_gt_midpoint = false
                                                is_inexact_lt_midpoint = false
                                                is_midpoint_gt_even = false
                                                is_midpoint_lt_even = true
                                            }
                                        }
                                        tmp_inexact = true    // in all cases
                                    } else {    // the result is not a midpoint
                                        // determine inexactness of the rounding of C1 (the sum C1+C2*)
                                        // if (0 < f1* - 1/2 < 10^(-1)) then
                                        //   the result is exact
                                        // else (if f1* - 1/2 > T* then)
                                        //   the result of is inexact
                                        // ind = 0
                                        if (Q256.w[1] > MASK_SIGN || (Q256.w[1] == MASK_SIGN && Q256.w[0] > 0x0)) {
                                            // f1* > 1/2 and the result may be exact
                                            Q256.w[1] = Q256.w[1] - MASK_SIGN;    // f1* - 1/2
                                            if ((Q256.w[1] > bid_ten2mk128trunc[0].hi
                                                 || (Q256.w[1] == bid_ten2mk128trunc[0].hi
                                                     && Q256.w[0] > bid_ten2mk128trunc[0].lo))) {
                                                is_inexact_gt_midpoint = false
                                                is_inexact_lt_midpoint = true
                                                is_midpoint_gt_even = false
                                                is_midpoint_lt_even = false
                                                // set the inexact flag
                                                tmp_inexact = true
                                                // pfpsf.insert(.inexact)
                                            } else {    // else the result is exact for the 2nd rounding
                                                if tmp_inexact {    // if the previous rounding was inexact
                                                    if is_midpoint_lt_even {
                                                        is_inexact_gt_midpoint = true
                                                        is_midpoint_lt_even = false
                                                    } else if is_midpoint_gt_even {
                                                        is_inexact_lt_midpoint = true
                                                        is_midpoint_gt_even = false
                                                    } else {
                                                        // no change
                                                    }
                                                }
                                            }
                                            // rounding down, unless a midpoint in [ODD, EVEN]
                                        } else {    // the result is inexact; f1* <= 1/2
                                            is_inexact_gt_midpoint = true
                                            is_inexact_lt_midpoint = false
                                            is_midpoint_gt_even = false
                                            is_midpoint_lt_even = false
                                            // set the inexact flag
                                            tmp_inexact = true
                                            // pfpsf.insert(.inexact)
                                        }
                                    }    // end 'the result is not a midpoint'
                                    // n = C1 * 10^(e2+x1)
                                    C1.hi = Q256.w[3]
                                    C1.lo = Q256.w[2]
                                    y_exp = y_exp + UInt64((x1 + 1) << 49)
                                } else {    // C1 < 10^34
                                    // C1.hi and C1.lo already set
                                    // n = C1 * 10^(e2+x1)
                                    y_exp = y_exp + UInt64(x1 << 49)
                                }
                                // check for overflow
                                if y_exp == EXP_MAX_P1 && (rnd_mode == BID_ROUNDING_TO_NEAREST || rnd_mode == BID_ROUNDING_TIES_AWAY) {
                                    res.hi = MASK_INF | x_signi    // +/-inf
                                    res.lo = 0x0
                                    // set the inexact flag
                                    pfpsf.insert(.inexact)
                                    // set the overflow flag
                                    pfpsf.insert(.overflow)
                                    BID_SWAP128(&res)
                                    return res
                                }    // else no overflow
                            } else {    // if x_sign != y_sign the result of this subtract. is exact
                                C1.lo = C1.lo - R256.w[2]
                                C1.hi = C1.hi - R256.w[3]
                                if C1.lo > tmp64 { C1.hi-=1 }   // borrow
                                if C1.hi >= MASK_SIGN {    // negative coefficient!
                                    C1.lo = ~C1.lo
                                    C1.lo+=1
                                    C1.hi = ~C1.hi
                                    if C1.lo == 0x0 { C1.hi+=1 }
                                    tmp_sign = y_signi
                                    // the result will have the sign of y if last rnd
                                } else {
                                    tmp_sign = x_signi
                                }
                                // if the difference has P34-1 digits or less, i.e. C1 < 10^33 then
                                //   redo the calculation with x1=x1-1;
                                // redo the calculation also if C1 = 10^33 and
                                //   (is_inexact_gt_midpoint or is_midpoint_lt_even);
                                //   (the last part should have really been
                                //   (is_inexact_lt_midpoint or is_midpoint_gt_even) from
                                //    the rounding of C2, but the position flags have been reversed)
                                // 10^33 = 0x0000314dc6448d93 0x38c15b0a00000000
                                if ((C1.hi < Ten33M1.hi || (C1.hi == Ten33M1.hi && C1.lo < Ten33M1.lo+1)) ||
                                    (C1.hi == Ten33M1.hi && C1.lo == Ten33M1.lo+1 && (is_inexact_gt_midpoint || is_midpoint_lt_even))) {    // C1=10^33
                                    x1 = x1 - 1   // x1 >= 0
                                    if x1 >= 0 {
                                        // clear position flags and tmp_inexact
                                        is_midpoint_lt_even = false
                                        is_midpoint_gt_even = false
                                        is_inexact_lt_midpoint = false
                                        is_inexact_gt_midpoint = false
                                        tmp_inexact = false
                                        second_pass = true
                                        continue // goto roundC2;    // else result has less than P34 digits
                                    }
                                }
                                // if the coefficient of the result is 10^34 it means that this
                                // must be the second pass, and we are done
                                if C1.hi == Ten34M1.hi && C1.lo == Ten34M1.lo+1 {    // if  C1 = 10^34
                                    C1.hi = Ten33M1.hi    // C1 = 10^33
                                    C1.lo = Ten33M1.lo+1
                                    y_exp += UInt64(1 << 49)
                                }
                                x_signi = tmp_sign
                                if x1 >= 1 { y_exp += UInt64(x1 << 49) }
                                
                                // x1 = -1 is possible at the end of a second pass when the
                                // first pass started with x1 = 1
                            }
                            break // exit loop
                        }  // roundC2 loop
                        
                        C1_hi = C1.hi
                        C1_lo = C1.lo
                        // general correction from RN to RA, RM, RP, RZ; result uses y_exp
                        if (rnd_mode != BID_ROUNDING_TO_NEAREST) {
                            if (((!x_sign) && ((rnd_mode == BID_ROUNDING_UP && is_inexact_lt_midpoint) ||
                                ((rnd_mode == BID_ROUNDING_TIES_AWAY || rnd_mode == BID_ROUNDING_UP) && is_midpoint_gt_even))) ||
                                (x_sign && ((rnd_mode == BID_ROUNDING_DOWN && is_inexact_lt_midpoint) ||
                                ((rnd_mode == BID_ROUNDING_TIES_AWAY || rnd_mode == BID_ROUNDING_DOWN) && is_midpoint_gt_even))))  {
                                // C1 = C1 + 1
                                C1_lo += 1
                                if C1_lo == 0 { C1_hi += 1 }   // rounding overflow in the low 64 bits
                                if C1_hi == Ten34M1.hi && C1_lo == Ten34M1.lo+1 {
                                    // C1 = 10^34 => rounding overflow
                                    C1_hi = Ten33M1.hi
                                    C1_lo = Ten33M1.lo+1    // 10^33
                                    y_exp = y_exp + EXP_P1
                                }
                            } else if ((is_midpoint_lt_even || is_inexact_gt_midpoint) &&
                                       ((x_sign && (rnd_mode == BID_ROUNDING_UP || rnd_mode == BID_ROUNDING_TO_ZERO))
                                        || (!x_sign && (rnd_mode == BID_ROUNDING_DOWN || rnd_mode == BID_ROUNDING_TO_ZERO)))) {
                                // C1 = C1 - 1
                                C1_lo = C1_lo &- 1
                                if C1_lo == 0xffff_ffff_ffff_ffff { C1_hi-=1 }
                                
                                // check if we crossed into the lower decade
                                if C1_hi == Ten33M1.hi && C1_lo == Ten33M1.lo {    // 10^33 - 1
                                    C1_hi = Ten34M1.hi    // 10^34 - 1
                                    C1_lo = Ten34M1.lo
                                    y_exp = y_exp - EXP_P1
                                    // no underflow, because delta + q2 >= P34 + 1
                                }
                            } else {
                                // exact, the result is already correct
                            }
                            // in all cases check for overflow (RN and RA solved already)
                            if y_exp == EXP_MAX_P1 {    // overflow
                                if ((rnd_mode == BID_ROUNDING_DOWN && x_sign) ||    // RM and res < 0
                                    (rnd_mode == BID_ROUNDING_UP && !x_sign)) {    // RP and res > 0
                                    C1_hi = MASK_INF    // +inf
                                    C1_lo = 0x0
                                } else {    // RM and res > 0, RP and res < 0, or RZ
                                    C1_hi = 0x5fff_ed09_bead_87c0
                                    C1_lo = Ten34M1.lo
                                }
                                y_exp = 0    // x_sign is preserved
                                // set the inexact flag (in case the exact addition was exact)
                                pfpsf.insert(.inexact)
                                // set the overflow flag
                                pfpsf.insert(.overflow)
                            }
                        }
                        // assemble the result
                        res.hi = x_signi | y_exp | C1_hi
                        res.lo = C1_lo
                        if tmp_inexact {
                            pfpsf.insert(.inexact)
                        }
                    }
                } else {    // if (-P34 + 1 <= delta <= -1) <=> 1 <= -delta <= P34 - 1
                    // NOTE: the following, up to "} else { // if x_sign != y_sign
                    // the result is exact" is identical to "else if (delta == P34 - q2) {"
                    // from above; also, the code is not symmetric: a+b and b+a may take
                    // different paths (need to unify eventually!)
                    // calculate C' = C2 + C1 * 10^(e1-e2) directly; the result may be
                    // inexact if it requires P34 + 1 decimal digits; in either case the
                    // 'cutoff' point for addition is at the position of the lsb of C2
                    // The coefficient of the result is C1 * 10^(e1-e2) + C2 and the
                    // exponent is e2; either C1 or 10^(e1-e2) may not fit is 64 bits,
                    // but their product fits with certainty in 128 bits (actually in 113)
                    // Note that 0 <= e1 - e2 <= P34 - 2
                    //   -P34 + 1 <= delta <= -1 <=> -P34 + 1 <= delta <= -1 <=>
                    //   -P34 + 1 <= q1 + e1 - q2 - e2 <= -1 <=>
                    //   q2 - q1 - P34 + 1 <= e1 - e2 <= q2 - q1 - 1 <=>
                    //   1 - P34 - P34 + 1 <= e1-e2 <= P34 - 1 - 1 => 0 <= e1-e2 <= P34 - 2
                    let scale = delta - q1 + q2    // scale = (int)(e1 >> 49) - (int)(e2 >> 49)
                    if scale >= 20 {    // 10^(e1-e2) does not fit in 64 bits, but C1 does
                        __mul_128x64_to_128(&C1, C1_lo, bid_ten2k128[scale - 20])
                    } else if scale >= 1 {
                        // if 1 <= scale <= 19 then 10^(e1-e2) fits in 64 bits
                        if q1 <= 19 {    // C1 fits in 64 bits
                            __mul_64x64_to_128MACH(&C1, C1_lo, bid_ten2k64[scale])
                        } else {    // q1 >= 20
                            C1.hi = C1_hi
                            C1.lo = C1_lo
                            __mul_128x64_to_128(&C1, bid_ten2k64[scale], C1)
                        }
                    } else {    // if (scale == 0) C1 is unchanged
                        C1.hi = C1_hi
                        C1.lo = C1_lo    // only the low part is necessary
                    }
                    C1_hi = C1.hi
                    C1_lo = C1.lo
                    // now add C2
                    if x_sign == y_sign {
                        // the result can overflow!
                        C1_lo = C1_lo + C2_lo
                        C1_hi = C1_hi + C2_hi
                        if C1_lo < C1.lo { C1_hi+=1 }
                        
                        // test for overflow, possible only when C1 >= 10^34
                        if C1_hi > Ten34M1.hi || (C1_hi == Ten34M1.hi && C1_lo >= Ten34M1.lo+1) {    // C1 >= 10^34
                            // in this case q = P34 + 1 and x = q - P34 = 1, so multiply
                            // C'' = C'+ 5 = C1 + 5 by k1 ~ 10^(-1) calculated for P34 + 1
                            // decimal digits
                            // Calculate C'' = C' + 1/2 * 10^x
                            if C1_lo >= 0xffff_ffff_ffff_fffb {    // low half add has carry
                                C1_lo = C1_lo + 5
                                C1_hi = C1_hi + 1
                            } else {
                                C1_lo = C1_lo + 5
                            }
                            // the approximation of 10^(-1) was rounded up to 118 bits
                            // 10^(-1) =~ 33333333333333333333333333333400 * 2^-129
                            // 10^(-1) =~ 19999999999999999999999999999a00 * 2^-128
                            C1.hi = C1_hi
                            C1.lo = C1_lo   // C''
                            ten2m1.hi = 0x1999_9999_9999_9999
                            ten2m1.lo = 0x9999_9999_9999_9a00
                            __mul_128x128_to_256(&P256, C1, ten2m1)    // P256 = C*, f*
                            // C* is actually floor(C*) in this case
                            // the top Ex = 128 bits of 10^(-1) are
                            // T* = 0x00199999999999999999999999999999
                            // if (0 < f* < 10^(-x)) then
                            //   if floor(C*) is even then C = floor(C*) - logical right
                            //       shift; C has p decimal digits, correct by Prop. 1)
                            //   else if floor(C*) is odd C = floor(C*) - 1 (logical right
                            //       shift; C has p decimal digits, correct by Pr. 1)
                            // else
                            //   C = floor(C*) (logical right shift; C has p decimal digits,
                            //       correct by Property 1)
                            // n = C * 10^(e2+x)
                            if (P256.w[1] != 0 || P256.w[0] != 0) && (P256.w[1] < 0x1999_9999_9999_9999 ||
                               (P256.w[1] == 0x1999_9999_9999_9999 && P256.w[0] <= 0x9999_9999_9999_9999)) {
                                // the result is a midpoint
                                if (P256.w[2] & 0x01) != 0 {
                                    is_midpoint_gt_even = true
                                    // if floor(C*) is odd C = floor(C*) - 1; the result is not 0
                                    P256.w[2] &-= 1
                                    if P256.w[2] == 0xffff_ffff_ffff_ffff { P256.w[3]-=1 }
                                } else {
                                    is_midpoint_lt_even = true
                                }
                            }
                            // n = Cstar * 10^(e2+1)
                            y_exp = y_exp + EXP_P1
                            
                            // C* != 10^P34 because C* has P34 digits
                            // check for overflow
                            if (y_exp == EXP_MAX_P1 && (rnd_mode == BID_ROUNDING_TO_NEAREST || rnd_mode == BID_ROUNDING_TIES_AWAY)) {
                                // overflow for RN
                                res.hi = x_signi | MASK_INF    // +/-inf
                                res.lo = 0x0
                                // set the inexact flag
                                pfpsf.insert(.inexact)
                                // set the overflow flag
                                pfpsf.insert(.overflow)
                                BID_SWAP128(&res)
                                return res
                            }
                            // if (0 < f* - 1/2 < 10^(-x)) then
                            //   the result of the addition is exact
                            // else
                            //   the result of the addition is inexact
                            if (P256.w[1] > MASK_SIGN || (P256.w[1] == MASK_SIGN && P256.w[0] > 0x0)) {
                                // the result may be exact
                                let tmp64 = P256.w[1] - MASK_SIGN;    // f* - 1/2
                                if tmp64 > 0x1999_9999_9999_9999 || (tmp64 == 0x1999_9999_9999_9999 && P256.w[0] >= 0x9999_9999_9999_9999) {
                                    // set the inexact flag
                                    pfpsf.insert(.inexact)
                                    is_inexact = true
                                }    // else the result is exact
                            } else {    // the result is inexact
                                // set the inexact flag
                                pfpsf.insert(.inexact)
                                is_inexact = true
                            }
                            C1_hi = P256.w[3]
                            C1_lo = P256.w[2]
                            if !is_midpoint_gt_even && !is_midpoint_lt_even {
                                is_inexact_lt_midpoint = is_inexact && (P256.w[1] & MASK_SIGN != 0)
                                is_inexact_gt_midpoint = is_inexact && (P256.w[1] & MASK_SIGN == 0)
                            }
                            // general correction from RN to RA, RM, RP, RZ; result uses y_exp
                            if rnd_mode != BID_ROUNDING_TO_NEAREST {
                                if (!x_sign && ((rnd_mode == BID_ROUNDING_UP && is_inexact_lt_midpoint)
                                    || ((rnd_mode == BID_ROUNDING_TIES_AWAY || rnd_mode == BID_ROUNDING_UP)
                                    && is_midpoint_gt_even))) || (x_sign &&
                                    ((rnd_mode == BID_ROUNDING_DOWN && is_inexact_lt_midpoint) ||
                                    ((rnd_mode == BID_ROUNDING_TIES_AWAY || rnd_mode == BID_ROUNDING_DOWN) && is_midpoint_gt_even)))
                                {
                                    // C1 = C1 + 1
                                    C1_lo = C1_lo + 1
                                    if C1_lo == 0 { C1_hi += 1 }   // rounding overflow in the low 64 bits
                                    if (C1_hi == Ten34M1.hi && C1_lo == Ten34M1.lo+1) {
                                        // C1 = 10^34 => rounding overflow
                                        C1_hi = Ten33M1.hi;
                                        C1_lo = Ten33M1.lo+1;    // 10^33
                                        y_exp = y_exp + EXP_P1;
                                    }
                                } else if (is_midpoint_lt_even || is_inexact_gt_midpoint) &&
                                           ((x_sign && (rnd_mode == BID_ROUNDING_UP || rnd_mode == BID_ROUNDING_TO_ZERO)) ||
                                            (!x_sign && (rnd_mode == BID_ROUNDING_DOWN || rnd_mode == BID_ROUNDING_TO_ZERO))) {
                                    // C1 = C1 - 1
                                    C1_lo = C1_lo &- 1
                                    if C1_lo == 0xffff_ffff_ffff_ffff { C1_hi-=1 }
                                    
                                    // check if we crossed into the lower decade
                                    if C1_hi == Ten33M1.hi && C1_lo == Ten33M1.lo {    // 10^33 - 1
                                        C1_hi = Ten34M1.hi    // 10^34 - 1
                                        C1_lo = Ten34M1.lo
                                        y_exp = y_exp - EXP_P1
                                        // no underflow, because delta + q2 >= P34 + 1
                                    }
                                } else {
                                    // exact, the result is already correct
                                }
                                // in all cases check for overflow (RN and RA solved already)
                                if y_exp == EXP_MAX_P1 {    // overflow
                                    if ((rnd_mode == BID_ROUNDING_DOWN && x_sign) ||    // RM and res < 0
                                        (rnd_mode == BID_ROUNDING_UP && !x_sign)) {    // RP and res > 0
                                        C1_hi = MASK_INF    // +inf
                                        C1_lo = 0x0;
                                    } else {    // RM and res > 0, RP and res < 0, or RZ
                                        C1_hi = 0x5fffed09bead87c0;
                                        C1_lo = Ten34M1.lo;
                                    }
                                    y_exp = 0;    // x_sign is preserved
                                    // set the inexact flag (in case the exact addition was exact)
                                    pfpsf.insert(.inexact)
                                    // set the overflow flag
                                    pfpsf.insert(.overflow)
                                }
                            }
                        }    // else if (C1 < 10^34) then C1 is the coeff.; the result is exact
                        // assemble the result
                        res.hi = x_signi | y_exp | C1_hi
                        res.lo = C1_lo
                    } else {    // if x_sign != y_sign the result is exact
                        C1_lo = C2_lo - C1_lo
                        C1_hi = C2_hi - C1_hi
                        if C1_lo > C2_lo {
                            C1_hi-=1
                        }
                        if C1_hi >= MASK_SIGN {    // negative coefficient!
                            C1_lo = ~C1_lo;
                            C1_lo+=1
                            C1_hi = ~C1_hi;
                            if C1_lo == 0x0 {
                                C1_hi+=1
                            }
                            x_signi = y_signi    // the result will have the sign of y
                        }
                        // the result can be zero, but it cannot overflow
                        if (C1_lo == 0 && C1_hi == 0) {
                            // assemble the result
                            if (x_exp < y_exp) {
                                res.hi = x_exp;
                            } else {
                                res.hi = y_exp;
                            }
                            res.lo = 0;
                            if (rnd_mode == BID_ROUNDING_DOWN) {
                                res.hi |= MASK_SIGN;
                            }
                            BID_SWAP128(&res);
                            return res;
                        }
                        // assemble the result
                        res.hi = y_signi | y_exp | C1_hi;
                        res.lo = C1_lo;
                    }
                }
            }
            BID_SWAP128(&res);
            return res
        }
    }
    
    /*
     If x is not a floating-point number, the results are unspecified (this
     implementation returns x and *exp = 0). Otherwise, the frexp function
     returns the value res, such that res has a magnitude in the interval
     [1/10, 1) or zero, and x = res*2^*exp. If x is zero, both parts of the
     result are zero
     frexp does not raise any exceptions
     */
    static func frexp(_ x:UInt128, _ res:inout UInt128, _ exp:inout Int) {
        var exp_x: UInt64
        var sig_x = UInt128()
        
        if (x.hi & MASK_SPECIAL) == MASK_SPECIAL {
            // if NaN or infinity
            exp = 0
            res = x
            // the binary frexp quitetizes SNaNs, so do the same
            if (x.hi & MASK_SNAN) == MASK_SNAN { // x is SNAN
                //   // set invalid flag
                //   *pfpsf |= BID_INVALID_EXCEPTION;
                // return quiet (x)
                res.hi = x.hi & 0xfdffffffffffffff;
            }
        } else {
            // x is 0, non-canonical, normal, or subnormal
            // check for non-canonical values with 114 bit-significands; can be zero too
            if (x.hi & SPECIAL_ENCODING_MASK64) == SPECIAL_ENCODING_MASK64 {
                exp = 0
                exp_x = (x.hi & MASK_EXP2) >> 47; // biased
                res.hi = (x.hi & MASK_SIGN) | (UInt64(exp_x) << 49)
                // zero of same sign
                res.lo = 0x0
                return
            }
            // unpack x
            exp_x = (x.hi & MASK_EXP) >> 49 // biased
            sig_x.hi = x.hi & MASK_COEFF
            sig_x.lo = x.lo
            
            // check for non-canonical values or zero
            if (sig_x.hi > Ten34M1.hi) || (sig_x.hi == Ten34M1.hi && (sig_x.lo > Ten34M1.lo)) ||
                ((sig_x.hi == 0x0) && (sig_x.lo == 0x0)) {
                exp = 0
                res.hi = (x.hi & MASK_SIGN) | (UInt64(exp_x) << 49)
                // zero of same sign
                res.lo = 0x0
                return
            } else {
                // continue, x is neither zero nor non-canonical
            }
            // x is normal or subnormal, with exp_x=biased exponent & sig_x=coefficient
            // determine the number of decimal digits in sig_x, which fits in 113 bits
            // q = nr. of decimal digits in sig_x (1 <= q <= 34)
            //  determine first the nr. of bits in sig_x
            let q = digitsIn(sig_x.hi, lo: sig_x.lo)
//            var tmp = 0.0, x_nr_bits = 0
//            if sig_x.hi == 0 {
//                if sig_x.lo >= LARGE_COEFF_HIGH_BIT64 { // z >= 2^53
//                    // split the 64-bit value in two 32-bit halves to avoid rounding errors
//                    if sig_x.lo >= 0x0000_0001_0000_0000 { // z >= 2^32
//                        tmp = Double(sig_x.lo >> 32); // exact conversion
//                        x_nr_bits = 32 + Int(((tmp.bitPattern >> 52)) & 0x7ff) - BINARY_EXPONENT_BIAS
//                    } else { // z < 2^32
//                        tmp = Double(sig_x.lo) // exact conversion
//                        x_nr_bits = Int(((tmp.bitPattern >> 52)) & 0x7ff) - BINARY_EXPONENT_BIAS
//                    }
//                } else { // if z < 2^53
//                    tmp = Double(sig_x.lo) // exact conversion
//                    x_nr_bits = Int(((tmp.bitPattern >> 52)) & 0x7ff) - BINARY_EXPONENT_BIAS
//                }
//            } else { // sig_x.hi != 0 => nr. bits = 65 + nr_bits (sig_x.hi)
//                tmp = Double(sig_x.hi) // exact conversion
//                x_nr_bits = 64 + Int(((tmp.bitPattern >> 52)) & 0x7ff) - BINARY_EXPONENT_BIAS
//            }
//            var q = Int(bid_nr_digits[x_nr_bits].digits)
//            if q == 0 {
//                q = Int(bid_nr_digits[x_nr_bits].digits1)
//                if (sig_x.hi > bid_nr_digits[x_nr_bits].threshold_hi ||
//                    (sig_x.hi == bid_nr_digits[x_nr_bits].threshold_hi &&
//                     sig_x.lo >= bid_nr_digits[x_nr_bits].threshold_lo)) {
//                    q+=1
//                }
//            }
            // Do not add trailing zeros if q < 34; leave sig_x with q digits
            exp = Int(exp_x) - EXPONENT_BIAS + q
            // assemble the result; sig_x < 2^113 so it fits in 113 bits
            res.hi = (x.hi & 0x8001ffffffffffff) | UInt64((-q + EXPONENT_BIAS) << 49)
            res.lo = x.lo
            // replace exponent
        }
    }
    
    static func div(_ x:UInt128, _ y:UInt128, _ rnd_mode: Rounding, _ pfpsf: inout Status) -> UInt128 {
        return x
    }
    
    static func rem(_ x:UInt128, _ y:UInt128, _ rnd_mode: Rounding, _ pfpsf: inout Status) -> UInt128 {
        return x
    }
    
    static func sqrt(_ x: UInt128, _ rnd_mode: Rounding, _ pfpsf: inout Status) -> UInt128 {
        // unpack arguments, check for NaN or Infinity
        var sign_x = UInt64(), Carry = UInt64(), CX = UInt128(), exponent_x = 0, res = UInt128()
        var M256 = UInt256(), C256 = UInt256(), C4 = UInt256(), C8 = UInt256(), CX1 = UInt128()
        if !unpack_BID128_value(&sign_x, &exponent_x, &CX, x) {
            res = CX
            //        res.hi = CX.hi;
            //        res.lo = CX.lo;
            // NaN ?
            if (x.hi & MASK_ANY_INF) == MASK_ANY_INF {
                if (x.hi & MASK_SNAN) == MASK_SNAN {   // sNaN
                    pfpsf.insert(.invalidOperation)
                }
                res.hi = CX.hi & QUIET_MASK64
                return res
            }
            // x is Infinity?
            if (x.hi & MASK_INF) == MASK_INF {
                res.hi = CX.hi
                if sign_x != 0 {
                    // -Inf, return NaN
                    res.hi = MASK_ANY_INF
                    pfpsf.insert(.invalidOperation)
                }
                return res
            }
            // x is 0 otherwise
            
            res.hi = sign_x | (((UInt64(exponent_x + EXPONENT_BIAS)) >> 1) << 49)
            res.lo = 0
            return res
        }
        if sign_x != 0 {
            res.hi = MASK_ANY_INF
            res.lo = 0
            pfpsf.insert(.invalidOperation)
            return res
        }
        // 2^64
        let f64 = Float(bitPattern: 0x5f800000)
        
        // fx ~ CX
        let fx = Float(CX.hi) * f64 + Float(CX.lo)
        let bin_expon_cx = Int((fx.bitPattern >> 23) & 0xff) - 0x7f
        var digits = Int(bid_estimate_decimal_digits[bin_expon_cx])
        
        var A10 = CX, CX2 = UInt128(), CS = UInt128(), S2 = UInt128()
        if (exponent_x & 1) != 0 {
            A10.hi = (CX.hi << 3) | (CX.lo >> 61)
            A10.lo = CX.lo << 3
            CX2.hi = (CX.hi << 1) | (CX.lo >> 63)
            CX2.lo = CX.lo << 1
            __add_128_128(&A10, A10, CX2)
        }
        
        CS.lo = short_sqrt128(A10)
        CS.hi = 0
        // check for exact result
        if (CS.lo * CS.lo == A10.lo) {
            __mul_64x64_to_128_fast(&S2, CS.lo, CS.lo)
            if (S2.hi == A10.hi) {   // && S2.lo==A10.lo)
                res = bid_get_BID128_very_fast(0, (exponent_x + EXPONENT_BIAS) >> 1, CS)
                return res
            }
        }
        // get number of digits in CX
        let D = CX.hi - bid_power10_index_binexp_128[bin_expon_cx].hi;
        if (D > 0 || (D == 0 && CX.lo >= bid_power10_index_binexp_128[bin_expon_cx].lo)) {
            digits+=1
        }
        
        // if exponent is odd, scale coefficient by 10
        var scale = 67 - digits;
        let exponent_q = exponent_x - scale;
        scale += (exponent_q & 1);    // exp. bias is even
        
        var T128 = UInt128(), TP128 = UInt128()
        if (scale > 38) {
            T128 = bid_power10_table_128[scale - 37]
            __mul_128x128_low(&CX1, CX, T128)
            
            TP128 = bid_power10_table_128[37]
            __mul_128x128_to_256(&C256, CX1, TP128)
        } else {
            T128 = bid_power10_table_128[scale]
            __mul_128x128_to_256(&C256, CX, T128)
        }
        
        
        // 4*C256
        C4.w[3] = (C256.w[3] << 2) | (C256.w[2] >> 62)
        C4.w[2] = (C256.w[2] << 2) | (C256.w[1] >> 62)
        C4.w[1] = (C256.w[1] << 2) | (C256.w[0] >> 62)
        C4.w[0] = C256.w[0] << 2
        
        bid_long_sqrt128(&CS, C256);
        //printf("C256=%016I64x %016I64x %016I64x %016I64x, CS=%016I64x %016I64x \n",C256.w[3],C256.w[2],C256.w[1],C256.w[0],CS.w[1],CS.w[0]);
        let rmode = roundboundIndex(rnd_mode)
        if (rmode & 3) == 0 {
            // compare to midpoints
            var CSM = UInt128()
            CSM.hi = (CS.hi << 1) | (CS.lo >> 63)
            CSM.lo = (CS.lo + CS.lo) | 1
            // CSM^2
            //__mul_128x128_to_256(M256, CSM, CSM);
            __sqr128_to_256(&M256, CSM)
            
            if (C4.w[3] > M256.w[3] || (C4.w[3] == M256.w[3] && (C4.w[2] > M256.w[2] ||
                (C4.w[2] == M256.w[2] && (C4.w[1] > M256.w[1] || (C4.w[1] == M256.w[1] && C4.w[0] > M256.w[0])))))) {
                // round up
                CS.lo+=1
                if CS.lo == 0 { CS.hi+=1 }
            } else {
                C8.w[1] = (CS.hi << 3) | (CS.lo >> 61)
                C8.w[0] = CS.lo << 3
                // M256 - 8*CSM
                __sub_borrow_out(&M256.w[0], &Carry, M256.w[0], C8.w[0]);
                __sub_borrow_in_out(&M256.w[1], &Carry, M256.w[1], C8.w[1], Carry);
                __sub_borrow_in_out(&M256.w[2], &Carry, M256.w[2], 0, Carry);
                M256.w[3] = M256.w[3] - Carry;
                
                // if CSM' > C256, round up
                if (M256.w[3] > C4.w[3] || (M256.w[3] == C4.w[3] && (M256.w[2] > C4.w[2] ||
                    (M256.w[2] == C4.w[2] && (M256.w[1] > C4.w[1] || (M256.w[1] == C4.w[1] && M256.w[0] > C4.w[0])))))) {
                    // round down
                    if CS.lo == 0 { CS.hi-=1 }
                    CS.lo-=1
                }
            }
        } else {
            __sqr128_to_256(&M256, CS);
            C8.w[1] = (CS.hi << 1) | (CS.lo >> 63)
            C8.w[0] = CS.lo << 1
            if (M256.w[3] > C256.w[3] || (M256.w[3] == C256.w[3] && (M256.w[2] > C256.w[2] ||
                (M256.w[2] == C256.w[2] && (M256.w[1] > C256.w[1] || (M256.w[1] == C256.w[1] && M256.w[0] > C256.w[0])))))) {
                __sub_borrow_out(&M256.w[0], &Carry, M256.w[0], C8.w[0])
                __sub_borrow_in_out(&M256.w[1], &Carry, M256.w[1], C8.w[1], Carry)
                __sub_borrow_in_out(&M256.w[2], &Carry, M256.w[2], 0, Carry)
                M256.w[3] = M256.w[3] - Carry
                M256.w[0]+=1
                if M256.w[0] == 0 {
                    M256.w[1]+=1
                    if M256.w[1] == 0 {
                        M256.w[2]+=1
                        if M256.w[2] == 0 { M256.w[3]+=1 }
                    }
                }
                
                if CS.lo == 0 { CS.hi-=1 }
                CS.lo-=1
                
                if (M256.w[3] > C256.w[3] || (M256.w[3] == C256.w[3] && (M256.w[2] > C256.w[2] ||
                    (M256.w[2] == C256.w[2] && (M256.w[1] > C256.w[1] || (M256.w[1] == C256.w[1] && M256.w[0] > C256.w[0])))))) {
                    if CS.lo == 0 { CS.hi-=1 }
                    CS.lo-=1
                }
            } else {
                __add_carry_out(&M256.w[0], &Carry, M256.w[0], C8.w[0])
                __add_carry_in_out(&M256.w[1], &Carry, M256.w[1], C8.w[1], Carry)
                __add_carry_in_out(&M256.w[2], &Carry, M256.w[2], 0, Carry)
                M256.w[3] = M256.w[3] + Carry
                M256.w[0]+=1
                if M256.w[0] == 0 {
                    M256.w[1]+=1
                    if M256.w[1] == 0 {
                        M256.w[2]+=1
                        if M256.w[2] == 0 { M256.w[3]+=1 }
                    }
                }
                if (M256.w[3] < C256.w[3] || (M256.w[3] == C256.w[3] && (M256.w[2] < C256.w[2] ||
                    (M256.w[2] == C256.w[2] && (M256.w[1] < C256.w[1] || (M256.w[1] == C256.w[1] && M256.w[0] <= C256.w[0])))))) {
                    CS.lo+=1
                    if CS.lo == 0 { CS.hi+=1 }
                }
            }
            // RU?
            if rnd_mode == BID_ROUNDING_UP {
                CS.lo+=1
                if CS.lo == 0 { CS.hi+=1 }
            }
        }
        
        pfpsf.insert(.inexact)
        return bid_get_BID128_fast(0, (exponent_q + EXPONENT_BIAS) >> 1, CS)
    }
    
    static func bid_long_sqrt128(_ pCS: inout UInt128, _ C256:UInt256) {
        // 2^64
        let f64 = Double(bitPattern: 0x43f0000000000000)
        let l64 = f64
        
        let l128 = l64 * l64;
        var lx = Double(C256.w[3]) * l64 * l128;
        let l2 = Double(C256.w[2]) * l128;
        lx = (lx + l2);
        let l1 =  Double(C256.w[1]) * l64;
        lx = (lx + l1);
        let l0 =  Double(C256.w[0])
        lx =  (lx + l0);
        // sqrt(C256)
        let ly = 1.0 / Foundation.sqrt(lx)
        
        let MY = (ly.bitPattern & 0x000fffffffffffff) | 0x0010000000000000
        let ey = UInt64(BINARY_EXPONENT_BIAS) - (ly.bitPattern >> 52)
        
        // A10*RS^2, scaled by 2^(2*ey+104)
        var ARS0 = UInt384(), ARS = UInt384()
        __mul_64x256_to_320(&ARS0, MY, C256)
        __mul_64x320_to_384(&ARS, MY, ARS0)
        
        // shr by k=(2*ey+104)-128
        // expect k is in the range (192, 256) if result in [10^33, 10^34)
        // apply an additional signed shift by 1 at the same time (to get eps=eps0/2)
        var k = (ey << 1) + 104 - 128 - 192
        var k2 = 64 - k
        var ES = UInt128(), ARS1 = UInt128(), ARS00 = UInt256(), CY = UInt64()
        var S = UInt256(), AE = UInt256(), AE2 = UInt256(), ES2 = UInt128()
        ES.lo = (ARS.w[3] >> (k + 1)) | (ARS.w[4] << (k2 - 1))
        ES.hi = (ARS.w[4] >> k) | (ARS.w[5] << k2)
        ES.hi = UInt64(Int64(ES.hi) >> 1)
        
        // A*RS >> 192 (for error term computation)
        ARS1.lo = ARS0.w[3]
        ARS1.hi = ARS0.w[4]
        
        // A*RS>>64
        ARS00.w[0...3] = ARS0.w[1...4]
        
        if (Int64(ES.hi) < 0) {
            ES.lo = 0 &- ES.lo
            ES.hi = 0 &- ES.hi
            if ES.lo != 0 { ES.hi-=1 }
            
            // A*RS*eps
            __mul_128x128_to_256(&AE, ES, ARS1)
            
            __add_carry_out(&S.w[0], &CY, ARS00.w[0], AE.w[0])
            __add_carry_in_out(&S.w[1], &CY, ARS00.w[1], AE.w[1], CY)
            __add_carry_in_out(&S.w[2], &CY, ARS00.w[2], AE.w[2], CY)
            S.w[3] = ARS00.w[3] + AE.w[3] + CY;
        } else {
            // A*RS*eps
            __mul_128x128_to_256(&AE, ES, ARS1)
            
            __sub_borrow_out(&S.w[0], &CY, ARS00.w[0], AE.w[0])
            __sub_borrow_in_out(&S.w[1], &CY, ARS00.w[1], AE.w[1], CY)
            __sub_borrow_in_out(&S.w[2], &CY, ARS00.w[2], AE.w[2], CY)
            S.w[3] = ARS00.w[3] - AE.w[3] - CY
        }
        
        // 3/2*eps^2, scaled by 2^128
        let ES32 = ES.hi + (ES.hi >> 1)
        __mul_64x64_to_128(&ES2, ES32, ES.hi)
        // A*RS*3/2*eps^2
        __mul_128x128_to_256(&AE2, ES2, ARS1)
        
        // result, scaled by 2^(ey+52-64)
        __add_carry_out(&S.w[0], &CY, S.w[0], AE2.w[0])
        __add_carry_in_out(&S.w[1], &CY, S.w[1], AE2.w[1], CY)
        __add_carry_in_out(&S.w[2], &CY, S.w[2], AE2.w[2], CY)
        S.w[3] = S.w[3] + AE2.w[3] + CY
        
        // k in (0, 64)
        k = ey + 51 - 128
        k2 = 64 - k
        S.w[0] = (S.w[1] >> k) | (S.w[2] << k2)
        S.w[1] = (S.w[2] >> k) | (S.w[3] << k2)
        
        // round to nearest
        S.w[0]+=1
        if S.w[0] == 0 { S.w[1]+=1 }
        
        pCS.lo = (S.w[1] << 63) | (S.w[0] >> 1)
        pCS.hi = S.w[1] >> 1
    }
    
    static func short_sqrt128(_ A10:UInt128) -> UInt64 {
        var ARS = UInt256(), ARS0 = UInt192(), AE0 = UInt256(), AE = UInt256(), S = UInt256()
        var MY, ES, CY : UInt64
        
        // 2^64
        let f64 = Double(bitPattern: 0x43f0000000000000)
        let l64 = f64
        let lx = Double(A10.hi) * l64 + Double(A10.lo)
        let ly = 1.0 / Foundation.sqrt(lx)
        
        MY = (ly.bitPattern & 0x000fffffffffffff) | 0x0010000000000000
        let ey = UInt64(BINARY_EXPONENT_BIAS) - (ly.bitPattern >> 52)
        
        // A10*RS^2
        __mul_64x128_to_192(&ARS0, MY, A10)
        __mul_64x192_to_256(&ARS, MY, ARS0)
        
        // shr by 2*ey+40, to get a 64-bit value
        var k = Int(ey << 1) + 104 - 64
        if k >= 128 {
            if k > 128 {
                ES = (ARS.w[2] >> (k - 128)) | (ARS.w[3] << (192 - k))
            } else {
                ES = ARS.w[2]
            }
        } else {
            var ARS0 = UInt128()
            if k >= 64 {
                ARS0.lo = ARS.w[1]
                ARS0.hi = ARS.w[2]
                k -= 64
            }

            if k != 0 {
                __shr_128(&ARS0, ARS0, k)
                ARS.w[0] = ARS0.lo
            }
            ES = ARS.w[0]
        }
        
        ES = UInt64(Int64(ES) >> 1)
        
        if Int64(ES) < 0 {
            ES = 0 &- ES
            
            // A*RS*eps (scaled by 2^64)
            __mul_64x192_to_256(&AE0, ES, ARS0)
            
            AE.w[0...2] = AE0.w[1...3]
            CY = 0
            __add_carry_out(&S.w[0], &CY, ARS0.w[0], AE.w[0])
            __add_carry_in_out(&S.w[1], &CY, ARS0.w[1], AE.w[1], CY)
            S.w[2] = ARS0.w[2] + AE.w[2] + CY
        } else {
            // A*RS*eps (scaled by 2^64)
            __mul_64x192_to_256(&AE0, ES, ARS0)
            
            AE.w[0...2] = AE0.w[1...3]
            CY = 0
            __sub_borrow_out(&S.w[0], &CY, ARS0.w[0], AE.w[0])
            __sub_borrow_in_out(&S.w[1], &CY, ARS0.w[1], AE.w[1], CY)
            S.w[2] = ARS0.w[2] - AE.w[2] - CY
        }
        
        k = Int(ey + 51)
        
        var S1 = UInt128()
        if k >= 64 {
            if k >= 128 {
                S1.lo = S.w[2]
                S1.hi = 0
                k -= 128
            } else {
                S1.lo = S.w[1]
                S1.hi = S.w[2]
            }
            k -= 64
        }
        if k != 0 { __shr_128(&S1, S1, k) }
        return (S1.lo + 1) >> 1
    }
    
    static func equal(_ x: UInt128, _ y: UInt128, _ pfpsf: inout Status) -> Bool {
        var x_is_zero = false, y_is_zero = false, non_canon_x = false, non_canon_y = false
        var exp_x = 0, exp_y = 0, sig_n_prime192 = UInt192(), sig_n_prime256 = UInt256()
        var sig_x = UInt128(), sig_y = UInt128()
        
        // NaN (CASE1)
        // if either number is NAN, the comparison is unordered,
        // rather than equal : return 0
        if (((x.hi & MASK_NAN) == MASK_NAN) || ((y.hi & MASK_NAN) == MASK_NAN)) {
            if ((x.hi & MASK_SNAN) == MASK_SNAN || (y.hi & MASK_SNAN) == MASK_SNAN) {
                pfpsf.insert(.invalidOperation)
            }
            return false
        }
        // SIMPLE (CASE2)
        // if all the bits are the same, these numbers are equivalent.
        if (x.lo == y.lo && x.hi == y.hi) {
            return true
        }
        // INFINITY (CASE3)
        if ((x.hi & MASK_INF) == MASK_INF) {
            if ((y.hi & MASK_INF) == MASK_INF) {
                return (((x.hi ^ y.hi) & MASK_SIGN) != MASK_SIGN)
            } else {
                return false
            }
        }
        if ((y.hi & MASK_INF) == MASK_INF) {
            return false
        }
        // CONVERT X
        sig_x.hi = x.hi & 0x0001ffffffffffff
        sig_x.lo = x.lo
        exp_x = Int(x.hi >> 49) & 0x000000000003fff
        
        // CHECK IF X IS CANONICAL
        // 9999999999999999999999999999999999(decimal) =
        //   1ed09_bead87c0_378d8e63_ffffffff(hexadecimal)
        // [0, 10^34) is the 754 supported canonical range.
        //   If the value exceeds that, it is interpreted as 0.
        if ((sig_x.hi > 0x0001ed09bead87c0) || ((sig_x.hi == 0x0001ed09bead87c0) && (sig_x.lo > 0x378d8e63ffffffff))
            || ((x.hi & 0x6000000000000000) == 0x6000000000000000)) {
            non_canon_x = true
        } else {
            non_canon_x = false
        }
        
        // CONVERT Y
        exp_y = Int(y.hi >> 49) & 0x0000000000003fff
        sig_y.hi = y.hi & 0x0001ffffffffffff
        sig_y.lo = y.lo
        
        // CHECK IF Y IS CANONICAL
        // 9999999999999999999999999999999999(decimal) =
        //   1ed09_bead87c0_378d8e63_ffffffff(hexadecimal)
        // [0, 10^34) is the 754 supported canonical range.
        // If the value exceeds that, it is interpreted as 0.
        if ((sig_y.hi > 0x0001ed09bead87c0) || ((sig_y.hi == 0x0001ed09bead87c0) && (sig_y.lo > 0x378d8e63ffffffff))
            || ((y.hi & 0x6000000000000000) == 0x6000000000000000)) {
            non_canon_y = true
        } else {
            non_canon_y = false
        }
        
        // some properties:
        //    (+ZERO == -ZERO) => therefore ignore the sign
        //    (ZERO x 10^A == ZERO x 10^B) for any valid A, B => therefore
        //    ignore the exponent field
        //    (Any non-canonical # is considered 0)
        if (non_canon_x || ((sig_x.hi == 0) && (sig_x.lo == 0))) {
            x_is_zero = true
        }
        if (non_canon_y || ((sig_y.hi == 0) && (sig_y.lo == 0))) {
            y_is_zero = true
        }
        
        if (x_is_zero && y_is_zero) {
            return true
        } else if ((x_is_zero && !y_is_zero) || (!x_is_zero && y_is_zero)) {
            return false
        }
        // OPPOSITE SIGN (CASE5)
        // now, if the sign bits differ => not equal : return 0
        if ((x.hi ^ y.hi) & MASK_SIGN) != 0 {
            return false
        }
        // REDUNDANT REPRESENTATIONS (CASE6)
        if exp_x > exp_y {    // to simplify the loop below,
            swap(&exp_x, &exp_y)
            //SWAP (exp_x, exp_y, exp_t)    // put the larger exp in y,
            swap(&sig_x.hi, &sig_y.hi)
            //SWAP (sig_x.hi, sig_y.hi, sig_t.hi)    // and the smaller exp in x
            swap(&sig_x.lo, &sig_y.lo)
            //SWAP (sig_x.lo, sig_y.lo, sig_t.lo)    // and the smaller exp in x
        }
        
        
        if (exp_y - exp_x > 33) {
            return false
        }    // difference cannot be greater than 10^33
        
        if (exp_y - exp_x > 19) {
            // recalculate y's significand upwards
            __mul_128x128_to_256(&sig_n_prime256, sig_y, bid_ten2k128[exp_y - exp_x - 20])
            return ((sig_n_prime256.w[3] == 0) && (sig_n_prime256.w[2] == 0) &&
                    (sig_n_prime256.w[1] == sig_x.hi) && (sig_n_prime256.w[0] == sig_x.lo))
        }
        //else{
        // recalculate y's significand upwards
        __mul_64x128_to_192(&sig_n_prime192, bid_ten2k64[exp_y - exp_x], sig_y)
        return ((sig_n_prime192.w[2] == 0) && (sig_n_prime192.w[1] == sig_x.hi)  && (sig_n_prime192.w[0] == sig_x.lo))
    }
    
    static func lessThan(_ x: UInt128, _ y: UInt128, _ pfpsf: inout Status) -> Bool {
        var x_is_zero = false, y_is_zero = false, non_canon_x = false, non_canon_y = false
        var exp_x = 0, exp_y = 0, sig_n_prime192 = UInt192(), sig_n_prime256 = UInt256()
        var sig_x = UInt128(), sig_y = UInt128()
        
        // NaN (CASE1)
        // if either number is NAN, the comparison is unordered,
        // rather than equal : return 0
        if (((x.hi & MASK_NAN) == MASK_NAN) || ((y.hi & MASK_NAN) == MASK_NAN)) {
            pfpsf.insert(.invalidOperation)
            return false
        }
        // SIMPLE (CASE2)
        // if all the bits are the same, these numbers are equal.
        if (x.lo == y.lo && x.hi == y.hi) {
            return false
        }
        // INFINITY (CASE3)
        if ((x.hi & MASK_INF) == MASK_INF) {
            // if x==neg_inf, { res = (y == neg_inf)?1:0; BID_RETURN_VAL (res) }
            if ((x.hi & MASK_SIGN) == MASK_SIGN) {
                // x is -inf, so it is less than y unless y is -inf
                return (((y.hi & MASK_INF) != MASK_INF) || (y.hi & MASK_SIGN) != MASK_SIGN)
            } else {
                // x is pos_inf, no way for it to be less than y
                return false
            }
        } else if (y.hi & MASK_INF) == MASK_INF {
            // x is finite, so if y is positive infinity, then x is less, return 0
            //                 if y is negative infinity, then x is greater, return 1
            return ((y.hi & MASK_SIGN) != MASK_SIGN)
        }
        // CONVERT X
        sig_x.hi = x.hi & 0x0001ffffffffffff
        sig_x.lo = x.lo
        exp_x = Int(x.hi >> 49) & 0x000000000003fff
        
        // CHECK IF X IS CANONICAL
        // 9999999999999999999999999999999999(decimal) =
        //   1ed09_bead87c0_378d8e63_ffffffff(hexadecimal)
        // [0, 10^34) is the 754 supported canonical range.
        //     If the value exceeds that, it is interpreted as 0.
        if ((sig_x.hi > 0x0001ed09bead87c0) || ((sig_x.hi == 0x0001ed09bead87c0) && (sig_x.lo > 0x378d8e63ffffffff))
            || ((x.hi & 0x6000000000000000) == 0x6000000000000000)) {
            non_canon_x = true
        } else {
            non_canon_x = false
        }
        
        // CONVERT Y
        exp_y = Int(y.hi >> 49) & 0x0000000000003fff
        sig_y.hi = y.hi & 0x0001ffffffffffff
        sig_y.lo = y.lo
        
        // CHECK IF Y IS CANONICAL
        // 9999999999999999999999999999999999(decimal) =
        //   1ed09_bead87c0_378d8e63_ffffffff(hexadecimal)
        // [0, 10^34) is the 754 supported canonical range.
        //     If the value exceeds that, it is interpreted as 0.
        if ((sig_y.hi > 0x0001ed09bead87c0) || ((sig_y.hi == 0x0001ed09bead87c0) && (sig_y.lo > 0x378d8e63ffffffff))
            || ((y.hi & 0x6000000000000000) == 0x6000000000000000)) {
            non_canon_y = true
        } else {
            non_canon_y = false
        }
        
        // ZERO (CASE4)
        // some properties:
        //    (+ZERO == -ZERO) => therefore ignore the sign
        //    (ZERO x 10^A == ZERO x 10^B) for any valid A, B => therefore
        //    ignore the exponent field
        //    (Any non-canonical # is considered 0)
        if (non_canon_x || ((sig_x.hi == 0) && (sig_x.lo == 0))) {
            x_is_zero = true
        }
        if (non_canon_y || ((sig_y.hi == 0) && (sig_y.lo == 0))) {
            y_is_zero = true
        }
        // if both numbers are zero, neither is greater => return NOTGREATERTHAN
        if x_is_zero && y_is_zero {
            return false
        }
        // is x is zero, it is greater if Y is negative
        else if x_is_zero {
            return ((y.hi & MASK_SIGN) != MASK_SIGN)
        }
        // is y is zero, X is greater if it is positive
        else if (y_is_zero) {
            return ((x.hi & MASK_SIGN) == MASK_SIGN)
        }
        // OPPOSITE SIGN (CASE5)
        // now, if the sign bits differ, x is greater if y is negative
        if (((x.hi ^ y.hi) & MASK_SIGN) == MASK_SIGN) {
            return ((y.hi & MASK_SIGN) != MASK_SIGN)
        }
        // REDUNDANT REPRESENTATIONS (CASE6)
        // if exponents are the same, then we have a simple comparison
        // of the significands
        if exp_y == exp_x {
            return (((sig_x.hi > sig_y.hi) || (sig_x.hi == sig_y.hi
                     && sig_x.lo >= sig_y.lo)) != ((x.hi & MASK_SIGN) != MASK_SIGN))
        }
        // if both components are either bigger or smaller,
        // it is clear what needs to be done
        if ((sig_x.hi > sig_y.hi || (sig_x.hi == sig_y.hi && sig_x.lo > sig_y.lo)) && exp_x >= exp_y) {
            return ((x.hi & MASK_SIGN) == MASK_SIGN)
        }
        if ((sig_x.hi < sig_y.hi || (sig_x.hi == sig_y.hi && sig_x.lo < sig_y.lo)) && exp_x <= exp_y) {
            return ((x.hi & MASK_SIGN) != MASK_SIGN)
        }
        
        var diff = exp_x - exp_y
        
        // if |exp_x - exp_y| < 33, it comes down to the compensated significand
        if diff > 0 {    // to simplify the loop below,
            
            // if exp_x is 33 greater than exp_y, no need for compensation
            if diff > 33 {
                return ((x.hi & MASK_SIGN) == MASK_SIGN)
            }    // difference cannot be greater than 10^33
            
            if diff > 19 {    //128 by 128 bit multiply -> 256 bits
                __mul_128x128_to_256(&sig_n_prime256, sig_x, bid_ten2k128[diff - 20])
                
                // if postitive, return whichever significand is larger
                // (converse if negative)
                if sig_n_prime256.w[3] == 0 && (sig_n_prime256.w[2] == 0)
                    && sig_n_prime256.w[1] == sig_y.hi && (sig_n_prime256.w[0] == sig_y.lo) {
                    return false
                }    // if equal, return 0
                return (((sig_n_prime256.w[3] > 0) || sig_n_prime256.w[2] > 0)
                        || (sig_n_prime256.w[1] > sig_y.hi) || (sig_n_prime256.w[1] == sig_y.hi
                            && sig_n_prime256.w[0] > sig_y.lo)) != ((y.hi & MASK_SIGN) != MASK_SIGN)
            }
            //else { //128 by 64 bit multiply -> 192 bits
            __mul_64x128_to_192(&sig_n_prime192, bid_ten2k64[diff], sig_x)
            
            // if postitive, return whichever significand is larger
            // (converse if negative)
            if (sig_n_prime192.w[2] == 0) && sig_n_prime192.w[1] == sig_y.hi && (sig_n_prime192.w[0] == sig_y.lo) {
                return false
            }    // if equal, return 0
            return ((sig_n_prime192.w[2] > 0) || (sig_n_prime192.w[1] > sig_y.hi) || (sig_n_prime192.w[1] == sig_y.hi
                    && sig_n_prime192.w[0] > sig_y.lo)) != ((y.hi & MASK_SIGN) != MASK_SIGN)
        }
        
        diff = exp_y - exp_x
        
        // if exp_x is 33 less than exp_y, |x| < |y|, return 1 if positive
        if diff > 33 {
            return ((x.hi & MASK_SIGN) != MASK_SIGN)
        }
        
        if diff > 19 {    //128 by 128 bit multiply -> 256 bits
            // adjust the y significand upwards
            __mul_128x128_to_256(&sig_n_prime256, sig_y, bid_ten2k128[diff - 20])
            
            // if postitive, return whichever significand is larger
            // (converse if negative)
            if (sig_n_prime256.w[3] == 0 && (sig_n_prime256.w[2] == 0)
                && sig_n_prime256.w[1] == sig_x.hi && (sig_n_prime256.w[0] == sig_x.lo)) {
                return false
            }    // if equal, return 1
            return ((sig_n_prime256.w[3] != 0 || sig_n_prime256.w[2] != 0
                    || (sig_n_prime256.w[1] > sig_x.hi || (sig_n_prime256.w[1] == sig_x.hi
                      && sig_n_prime256.w[0] > sig_x.lo))) != ((x.hi & MASK_SIGN) == MASK_SIGN))
        }
        //else { //128 by 64 bit multiply -> 192 bits
        // adjust the y significand upwards
        __mul_64x128_to_192(&sig_n_prime192, bid_ten2k64[diff], sig_y)
        
        // if postitive, return whichever significand is larger
        // (converse if negative)
        if sig_n_prime192.w[2] == 0 && sig_n_prime192.w[1] == sig_x.hi && sig_n_prime192.w[0] == sig_x.lo {
            return false // if equal, return false
        }
        return (sig_n_prime192.w[2] != 0 || (sig_n_prime192.w[1] > sig_x.hi || (sig_n_prime192.w[1] == sig_x.hi
                && sig_n_prime192.w[0] > sig_x.lo))) != ((y.hi & MASK_SIGN) == MASK_SIGN);
    }
    
    /*****************************************************************************
     *  BID128_round_integral_exact
     ****************************************************************************/
    static func round(_ x:UInt128, _ rnd_mode:Rounding, _ pfpsf:inout Status) -> UInt128 {
        var res = UInt128(upper: 0xbaddbaddbaddbadd, lower: 0xbaddbaddbaddbadd)
        var fstar = UInt256(), P256 = UInt256(), C1 = UInt128(), x = x
        
        // check for NaN or Infinity
        if ((x.hi & MASK_SPECIAL) == MASK_SPECIAL) {
            // x is special
            if ((x.hi & MASK_NAN) == MASK_NAN) {    // x is NAN
                // if x = NaN, then res = Q (x)
                // check first for non-canonical NaN payload
                if (((x.hi & 0x00003fffffffffff) > 0x0000314dc6448d93) ||
                    (((x.hi & 0x00003fffffffffff) == 0x0000314dc6448d93) &&
                     (x.lo > 0x38c15b09ffffffff))) {
                    x.hi = x.hi & 0xffffc00000000000;
                    x.lo = 0x0;
                }
                if ((x.hi & MASK_SNAN) == MASK_SNAN) {    // x is SNAN
                    // set invalid flag
                    pfpsf.insert(.invalidOperation)
                    // return quiet (x)
                    res.hi = x.hi & 0xfc003fffffffffff;    // clear out also G[6]-G[16]
                    res.lo = x.lo;
                } else {    // x is QNaN
                    // return x
                    res.hi = x.hi & 0xfc003fffffffffff;    // clear out G[6]-G[16]
                    res.lo = x.lo;
                }
                return res
            } else {    // x is not a NaN, so it must be infinity
                if ((x.hi & MASK_SIGN) == 0x0) {    // x is +inf
                    // return +inf
                    res.hi = 0x7800000000000000;
                    res.lo = 0x0000000000000000;
                } else {    // x is -inf
                    // return -inf
                    res.hi = 0xf800000000000000;
                    res.lo = 0x0000000000000000;
                }
                return res
            }
        }
        // unpack x
        var x_exp:UInt64
        let x_sign = x.hi & MASK_SIGN;    // 0 for positive, MASK_SIGN for negative
        C1.hi = x.hi & MASK_COEFF;
        C1.lo = x.lo;
        
        // check for non-canonical values (treated as zero)
        if ((x.hi & 0x6000000000000000) == 0x6000000000000000) {    // G0_G1=11
            // non-canonical
            x_exp = (x.hi << 2) & MASK_EXP;    // biased and shifted left 49 bits
            C1.hi = 0;    // significand high
            C1.lo = 0;    // significand low
        } else {    // G0_G1 != 11
            x_exp = x.hi & MASK_EXP;    // biased and shifted left 49 bits
            if (C1.hi > 0x0001ed09bead87c0 || (C1.hi == 0x0001ed09bead87c0 && C1.lo > 0x378d8e63ffffffff)) {
                // x is non-canonical if coefficient is larger than 10^34 -1
                C1.hi = 0;
                C1.lo = 0;
            } else {    // canonical
                // nothing
            }
        }
        
        // test for input equal to zero
        if ((C1.hi == 0x0) && (C1.lo == 0x0)) {
            // x is 0
            // return 0 preserving the sign bit and the preferred exponent
            // of MAX(Q(x), 0)
            if (x_exp <= (0x1820 << 49)) {
                res.hi = (x.hi & 0x8000000000000000) | 0x3040000000000000;
            } else {
                res.hi = x_sign | x_exp;
            }
            res.lo = 0x0000000000000000;
            return res
        }
        // x is not special and is not zero
        
        switch rnd_mode {
            case BID_ROUNDING_TO_NEAREST, BID_ROUNDING_TIES_AWAY:
                // if (exp <= -(p+1)) return 0.0
                if (x_exp <= 0x2ffa000000000000) {    // 0x2ffa000000000000 == -35
                    res.hi = x_sign | 0x3040000000000000;
                    res.lo = 0x0000000000000000;
                    pfpsf.insert(.inexact)
                    return res
                }
            case BID_ROUNDING_DOWN:
                // if (exp <= -p) return -1.0 or +0.0
                if (x_exp <= 0x2ffc000000000000) {    // 0x2ffa000000000000 == -34
                    if x_sign != 0 {
                        // if negative, return negative 1, because we know coefficient
                        // is non-zero (would have been caught above)
                        res.hi = 0xb040000000000000;
                        res.lo = 0x0000000000000001;
                    } else {
                        // if positive, return positive 0, because we know coefficient is
                        // non-zero (would have been caught above)
                        res.hi = 0x3040000000000000;
                        res.lo = 0x0000000000000000;
                    }
                    pfpsf.insert(.inexact)
                    return res
                }
            case BID_ROUNDING_UP:
                // if (exp <= -p) return -0.0 or +1.0
                if (x_exp <= 0x2ffc000000000000) {    // 0x2ffc000000000000 == -34
                    if x_sign != 0 {
                        // if negative, return negative 0, because we know the coefficient
                        // is non-zero (would have been caught above)
                        res.hi = 0xb040000000000000;
                        res.lo = 0x0000000000000000;
                    } else {
                        // if positive, return positive 1, because we know coefficient is
                        // non-zero (would have been caught above)
                        res.hi = 0x3040000000000000;
                        res.lo = 0x0000000000000001;
                    }
                    pfpsf.insert(.inexact)
                    return res
                }
            case BID_ROUNDING_TO_ZERO:
                // if (exp <= -p) return -0.0 or +0.0
                if (x_exp <= 0x2ffc000000000000) {    // 0x2ffc000000000000 == -34
                    res.hi = x_sign | 0x3040000000000000;
                    res.lo = 0x0000000000000000;
                    pfpsf.insert(.inexact)
                    return res
                }
            default: break
        }
        
        // q = nr. of decimal digits in x
        //  determine first the nr. of bits in x
        let q = digitsIn(C1.hi, lo: C1.lo)
//        var tmp1 = 0.0
//        if (C1.hi == 0) {
//            if (C1.lo >= 0x0020000000000000) {    // x >= 2^53
//                // split the 64-bit value in two 32-bit halves to avoid rounding errors
//                tmp1 = Double(C1.lo >> 32);    // exact conversion
//                x_nr_bits = 33 + ((((tmp1.bitPattern >> 52)) & 0x7ff) - 0x3ff);
//            } else {    // if x < 2^53
//                tmp1 = Double(C1.lo)    // exact conversion
//                x_nr_bits =
//                1 + ((((tmp1.bitPattern >> 52)) & 0x7ff) - 0x3ff);
//            }
//        } else {    // C1.hi != 0 => nr. bits = 64 + nr_bits (C1.hi)
//            tmp1 = Double(C1.hi)    // exact conversion
//            x_nr_bits =
//            65 + ((((unsigned int) (tmp1.ui64 >> 52)) & 0x7ff) - 0x3ff);
//        }
//
//        q = bid_nr_digits[x_nr_bits - 1].digits;
//        if (q == 0) {
//            q = bid_nr_digits[x_nr_bits - 1].digits1;
//            if (C1.hi > bid_nr_digits[x_nr_bits - 1].threshold_hi ||
//                (C1.hi == bid_nr_digits[x_nr_bits - 1].threshold_hi &&
//                 C1.lo >= bid_nr_digits[x_nr_bits - 1].threshold_lo))
//                q+=1
//        }
        let exp = Int(x_exp >> 49) - 6176;
        if (exp >= 0) {    // -exp <= 0
            // the argument is an integer already
            res.hi = x.hi;
            res.lo = x.lo;
            return res
        }
        
        // exp < 0
        var tmp64:UInt64, ind, shift:Int
        switch rnd_mode {
            case BID_ROUNDING_TO_NEAREST:
                if ((q + exp) >= 0) {    // exp < 0 and 1 <= -exp <= q
                    // need to shift right -exp digits from the coefficient; exp will be 0
                    ind = -exp;    // 1 <= ind <= 34; ind is a synonym for 'x'
                    // chop off ind digits from the lower part of C1
                    // C1 = C1 + 1/2 * 10^x where the result C1 fits in 127 bits
                    tmp64 = C1.lo
                    if (ind <= 19) {
                        C1.lo = C1.lo + bid_midpoint64[ind - 1];
                    } else {
                        C1.lo = C1.lo + bid_midpoint128[ind - 20].lo;
                        C1.hi = C1.hi + bid_midpoint128[ind - 20].hi;
                    }
                    if (C1.lo < tmp64) {
                        C1.hi+=1
                    }
                    // calculate C* and f*
                    // C* is actually floor(C*) in this case
                    // C* and f* need shifting and masking, as shown by
                    // bid_shiftright128[] and bid_maskhigh128[]
                    // 1 <= x <= 34
                    // kx = 10^(-x) = bid_ten2mk128[ind - 1]
                    // C* = (C1 + 1/2 * 10^x) * 10^(-x)
                    // the approximation of 10^(-x) was rounded up to 118 bits
                    __mul_128x128_to_256(&P256, C1, bid_ten2mk128[ind - 1]);
                    // determine the value of res and fstar
                    
                    // determine inexactness of the rounding of C*
                    // if (0 < f* - 1/2 < 10^(-x)) then
                    //   the result is exact
                    // else // if (f* - 1/2 > T*) then
                    //   the result is inexact
                    // Note: we are going to use bid_ten2mk128[] instead of bid_ten2mk128trunc[]
                    
                    if (ind - 1 <= 2) {    // 0 <= ind - 1 <= 2 => shift = 0
                        // redundant shift = bid_shiftright128[ind - 1]; // shift = 0
                        res.hi = P256.w[3];
                        res.lo = P256.w[2];
                        // redundant fstar.w[3] = 0;
                        // redundant fstar.w[2] = 0;
                        fstar.w[1] = P256.w[1];
                        fstar.w[0] = P256.w[0];
                        // fraction f* < 10^(-x) <=> midpoint
                        // f* is in the right position to be compared with
                        // 10^(-x) from bid_ten2mk128[]
                        // if 0 < fstar < 10^(-x), subtract 1 if odd (for rounding to even)
                        if ((res.lo & 0x0000000000000001 != 0) &&    // is result odd, and from MP?
                            ((fstar.w[1] < (bid_ten2mk128[ind - 1].hi))
                             || ((fstar.w[1] == bid_ten2mk128[ind - 1].hi)
                                 && (fstar.w[0] < bid_ten2mk128[ind - 1].lo)))) {
                            // subtract 1 to make even
                            res.lo-=1
                        }
                        if (fstar.w[1] > 0x8000000000000000 || (fstar.w[1] == 0x8000000000000000 && fstar.w[0] > 0x0)) {
                            // f* > 1/2 and the result may be exact
                            tmp64 = fstar.w[1] - 0x8000000000000000;    // f* - 1/2
                            if (tmp64 > bid_ten2mk128[ind - 1].hi ||
                                (tmp64 == bid_ten2mk128[ind - 1].hi &&
                                 fstar.w[0] >= bid_ten2mk128[ind - 1].lo)) {
                                // set the inexact flag
                                pfpsf.insert(.inexact)
                            }    // else the result is exact
                        } else {    // the result is inexact; f2* <= 1/2
                            // set the inexact flag
                            pfpsf.insert(.inexact)
                        }
                    } else if (ind - 1 <= 21) {    // 3 <= ind - 1 <= 21 => 3 <= shift <= 63
                        shift = bid_shiftright128[ind - 1];    // 3 <= shift <= 63
                        res.hi = (P256.w[3] >> shift);
                        res.lo = (P256.w[3] << (64 - shift)) | (P256.w[2] >> shift);
                        // redundant fstar.w[3] = 0;
                        fstar.w[2] = P256.w[2] & bid_maskhigh128[ind - 1];
                        fstar.w[1] = P256.w[1];
                        fstar.w[0] = P256.w[0];
                        // fraction f* < 10^(-x) <=> midpoint
                        // f* is in the right position to be compared with
                        // 10^(-x) from bid_ten2mk128[]
                        if ((res.lo & 0x0000000000000001 != 0) &&    // is result odd, and from MP?
                            fstar.w[2] == 0 && (fstar.w[1] < bid_ten2mk128[ind - 1].hi ||
                                                (fstar.w[1] == bid_ten2mk128[ind - 1].hi &&
                                                 fstar.w[0] < bid_ten2mk128[ind - 1].lo))) {
                            // subtract 1 to make even
                            res.lo-=1
                        }
                        if (fstar.w[2] > bid_onehalf128[ind - 1] ||
                            (fstar.w[2] == bid_onehalf128[ind - 1]
                             && (fstar.w[1] != 0 || fstar.w[0] != 0))) {
                            // f2* > 1/2 and the result may be exact
                            // Calculate f2* - 1/2
                            tmp64 = fstar.w[2] - bid_onehalf128[ind - 1];
                            if (tmp64 != 0 || fstar.w[1] > bid_ten2mk128[ind - 1].hi ||
                                (fstar.w[1] == bid_ten2mk128[ind - 1].hi &&
                                 fstar.w[0] >= bid_ten2mk128[ind - 1].lo)) {
                                // set the inexact flag
                                pfpsf.insert(.inexact)
                            }    // else the result is exact
                        } else {    // the result is inexact; f2* <= 1/2
                            // set the inexact flag
                            pfpsf.insert(.inexact)
                        }
                    } else {    // 22 <= ind - 1 <= 33
                        shift = bid_shiftright128[ind - 1] - 64;    // 2 <= shift <= 38
                        res.hi = 0;
                        res.lo = P256.w[3] >> shift;
                        fstar.w[3] = P256.w[3] & bid_maskhigh128[ind - 1];
                        fstar.w[2] = P256.w[2];
                        fstar.w[1] = P256.w[1];
                        fstar.w[0] = P256.w[0];
                        // fraction f* < 10^(-x) <=> midpoint
                        // f* is in the right position to be compared with
                        // 10^(-x) from bid_ten2mk128[]
                        if ((res.lo & 0x0000000000000001 != 0) &&    // is result odd, and from MP?
                            fstar.w[3] == 0 && fstar.w[2] == 0 &&
                            (fstar.w[1] < bid_ten2mk128[ind - 1].hi ||
                             (fstar.w[1] == bid_ten2mk128[ind - 1].hi &&
                              fstar.w[0] < bid_ten2mk128[ind - 1].lo))) {
                            // subtract 1 to make even
                            res.lo-=1
                        }
                        if (fstar.w[3] > bid_onehalf128[ind - 1] ||
                            (fstar.w[3] == bid_onehalf128[ind - 1] &&
                             (fstar.w[2] != 0 || fstar.w[1] != 0 || fstar.w[0] != 0))) {
                            // f2* > 1/2 and the result may be exact
                            // Calculate f2* - 1/2
                            tmp64 = fstar.w[3] - bid_onehalf128[ind - 1];
                            if (tmp64 != 0 || fstar.w[2] != 0 || fstar.w[1] > bid_ten2mk128[ind - 1].hi
                                || (fstar.w[1] == bid_ten2mk128[ind - 1].hi
                                    && fstar.w[0] >= bid_ten2mk128[ind - 1].lo)) {
                                // set the inexact flag
                                pfpsf.insert(.inexact)
                            }    // else the result is exact
                        } else {    // the result is inexact; f2* <= 1/2
                            // set the inexact flag
                            pfpsf.insert(.inexact)
                        }
                    }
                    res.hi = x_sign | 0x3040000000000000 | res.hi;
                    return res
                } else {    // if ((q + exp) < 0) <=> q < -exp
                    // the result is +0 or -0
                    res.hi = x_sign | 0x3040000000000000;
                    res.lo = 0x0000000000000000;
                    pfpsf.insert(.inexact)
                    return res
                }
            case BID_ROUNDING_TIES_AWAY:
                if ((q + exp) >= 0) {    // exp < 0 and 1 <= -exp <= q
                    // need to shift right -exp digits from the coefficient; exp will be 0
                    ind = -exp;    // 1 <= ind <= 34; ind is a synonym for 'x'
                    // chop off ind digits from the lower part of C1
                    // C1 = C1 + 1/2 * 10^x where the result C1 fits in 127 bits
                    tmp64 = C1.lo;
                    if (ind <= 19) {
                        C1.lo = C1.lo + bid_midpoint64[ind - 1];
                    } else {
                        C1.lo = C1.lo + bid_midpoint128[ind - 20].lo;
                        C1.hi = C1.hi + bid_midpoint128[ind - 20].hi;
                    }
                    if (C1.lo < tmp64) {
                        C1.hi+=1
                    }
                    // calculate C* and f*
                    // C* is actually floor(C*) in this case
                    // C* and f* need shifting and masking, as shown by
                    // bid_shiftright128[] and bid_maskhigh128[]
                    // 1 <= x <= 34
                    // kx = 10^(-x) = bid_ten2mk128[ind - 1]
                    // C* = (C1 + 1/2 * 10^x) * 10^(-x)
                    // the approximation of 10^(-x) was rounded up to 118 bits
                    __mul_128x128_to_256(&P256, C1, bid_ten2mk128[ind - 1]);
                    // the top Ex bits of 10^(-x) are T* = bid_ten2mk128trunc[ind], e.g.
                    // if x=1, T*=bid_ten2mk128trunc[0]=0x19999999999999999999999999999999
                    // if (0 < f* < 10^(-x)) then the result is a midpoint
                    //   if floor(C*) is even then C* = floor(C*) - logical right
                    //       shift; C* has p decimal digits, correct by Prop. 1)
                    //   else if floor(C*) is odd C* = floor(C*)-1 (logical right
                    //       shift; C* has p decimal digits, correct by Pr. 1)
                    // else
                    //   C* = floor(C*) (logical right shift; C has p decimal digits,
                    //       correct by Property 1)
                    // n = C* * 10^(e+x)
                    
                    // determine also the inexactness of the rounding of C*
                    // if (0 < f* - 1/2 < 10^(-x)) then
                    //   the result is exact
                    // else // if (f* - 1/2 > T*) then
                    //   the result is inexact
                    // Note: we are going to use bid_ten2mk128[] instead of bid_ten2mk128trunc[]
                    // shift right C* by Ex-128 = bid_shiftright128[ind]
                    if (ind - 1 <= 2) {    // 0 <= ind - 1 <= 2 => shift = 0
                        // redundant shift = bid_shiftright128[ind - 1]; // shift = 0
                        res.hi = P256.w[3];
                        res.lo = P256.w[2];
                        // redundant fstar.w[3] = 0;
                        // redundant fstar.w[2] = 0;
                        fstar.w[1] = P256.w[1];
                        fstar.w[0] = P256.w[0];
                        if (fstar.w[1] > 0x8000000000000000 ||
                            (fstar.w[1] == 0x8000000000000000
                             && fstar.w[0] > 0x0)) {
                            // f* > 1/2 and the result may be exact
                            let tmp64 = fstar.w[1] - 0x8000000000000000;    // f* - 1/2
                            if ((tmp64 > bid_ten2mk128[ind - 1].hi ||
                                 (tmp64 == bid_ten2mk128[ind - 1].hi &&
                                  fstar.w[0] >= bid_ten2mk128[ind - 1].lo))) {
                                // set the inexact flag
                                pfpsf.insert(.inexact)
                            }    // else the result is exact
                        } else {    // the result is inexact; f2* <= 1/2
                            // set the inexact flag
                            pfpsf.insert(.inexact)
                        }
                    } else if (ind - 1 <= 21) {    // 3 <= ind - 1 <= 21 => 3 <= shift <= 63
                        shift = bid_shiftright128[ind - 1];    // 3 <= shift <= 63
                        res.hi = (P256.w[3] >> shift);
                        res.lo = (P256.w[3] << (64 - shift)) | (P256.w[2] >> shift);
                        // redundant fstar.w[3] = 0;
                        fstar.w[2] = P256.w[2] & bid_maskhigh128[ind - 1];
                        fstar.w[1] = P256.w[1];
                        fstar.w[0] = P256.w[0];
                        if (fstar.w[2] > bid_onehalf128[ind - 1] || (fstar.w[2] == bid_onehalf128[ind - 1]
                             && (fstar.w[1] != 0 || fstar.w[0] != 0))) {
                            // f2* > 1/2 and the result may be exact
                            // Calculate f2* - 1/2
                            tmp64 = fstar.w[2] - bid_onehalf128[ind - 1];
                            if (tmp64 != 0 || fstar.w[1] > bid_ten2mk128[ind - 1].hi || (fstar.w[1] == bid_ten2mk128[ind - 1].hi && fstar.w[0] >= bid_ten2mk128[ind - 1].lo)) {
                                // set the inexact flag
                                pfpsf.insert(.inexact)
                            }    // else the result is exact
                        } else {    // the result is inexact; f2* <= 1/2
                            // set the inexact flag
                            pfpsf.insert(.inexact)
                        }
                    } else {    // 22 <= ind - 1 <= 33
                        shift = bid_shiftright128[ind - 1] - 64;    // 2 <= shift <= 38
                        res.hi = 0;
                        res.lo = P256.w[3] >> shift;
                        fstar.w[3] = P256.w[3] & bid_maskhigh128[ind - 1];
                        fstar.w[2] = P256.w[2];
                        fstar.w[1] = P256.w[1];
                        fstar.w[0] = P256.w[0];
                        if (fstar.w[3] > bid_onehalf128[ind - 1] || (fstar.w[3] == bid_onehalf128[ind - 1] &&
                             (fstar.w[2] != 0 || fstar.w[1] != 0 || fstar.w[0] != 0))) {
                            // f2* > 1/2 and the result may be exact
                            // Calculate f2* - 1/2
                            tmp64 = fstar.w[3] - bid_onehalf128[ind - 1];
                            if (tmp64 != 0 || fstar.w[2] != 0 || fstar.w[1] > bid_ten2mk128[ind - 1].hi
                                || (fstar.w[1] == bid_ten2mk128[ind - 1].hi
                                    && fstar.w[0] >= bid_ten2mk128[ind - 1].lo)) {
                                // set the inexact flag
                                pfpsf.insert(.inexact)
                            }    // else the result is exact
                        } else {    // the result is inexact; f2* <= 1/2
                            // set the inexact flag
                            pfpsf.insert(.inexact)
                        }
                    }
                    // if the result was a midpoint, it was already rounded away from zero
                    res.hi |= x_sign | 0x3040000000000000;
                    return res
                } else {    // if ((q + exp) < 0) <=> q < -exp
                    // the result is +0 or -0
                    res.hi = x_sign | 0x3040000000000000;
                    res.lo = 0x0000000000000000;
                    pfpsf.insert(.inexact)
                    return res
                }
            case BID_ROUNDING_DOWN:
                if ((q + exp) > 0) {    // exp < 0 and 1 <= -exp < q
                    // need to shift right -exp digits from the coefficient; exp will be 0
                    ind = -exp;    // 1 <= ind <= 34; ind is a synonym for 'x'
                    // (number of digits to be chopped off)
                    // chop off ind digits from the lower part of C1
                    // FOR ROUND_TO_NEAREST, WE ADD 1/2 ULP(y) then truncate
                    // FOR ROUND_TO_ZERO, WE DON'T NEED TO ADD 1/2 ULP
                    // FOR ROUND_TO_POSITIVE_INFINITY, WE TRUNCATE, THEN ADD 1 IF POSITIVE
                    // FOR ROUND_TO_NEGATIVE_INFINITY, WE TRUNCATE, THEN ADD 1 IF NEGATIVE
                    // tmp64 = C1.lo;
                    // if (ind <= 19) {
                    //   C1.lo = C1.lo + bid_midpoint64[ind - 1];
                    // } else {
                    //   C1.lo = C1.lo + bid_midpoint128[ind - 20].lo;
                    //   C1.hi = C1.hi + bid_midpoint128[ind - 20].hi;
                    // }
                    // if (C1.lo < tmp64) C1.hi+=1
                    // if carry-out from C1.lo, increment C1.hi
                    // calculate C* and f*
                    // C* is actually floor(C*) in this case
                    // C* and f* need shifting and masking, as shown by
                    // bid_shiftright128[] and bid_maskhigh128[]
                    // 1 <= x <= 34
                    // kx = 10^(-x) = bid_ten2mk128[ind - 1]
                    // C* = (C1 + 1/2 * 10^x) * 10^(-x)
                    // the approximation of 10^(-x) was rounded up to 118 bits
                    __mul_128x128_to_256(&P256, C1, bid_ten2mk128[ind - 1]);
                    if (ind - 1 <= 2) {    // 0 <= ind - 1 <= 2 => shift = 0
                        res.hi = P256.w[3];
                        res.lo = P256.w[2];
                        // redundant fstar.w[3] = 0;
                        // redundant fstar.w[2] = 0;
                        // redundant fstar.w[1] = P256.w[1];
                        // redundant fstar.w[0] = P256.w[0];
                        // fraction f* > 10^(-x) <=> inexact
                        // f* is in the right position to be compared with
                        // 10^(-x) from bid_ten2mk128[]
                        if ((P256.w[1] > bid_ten2mk128[ind - 1].hi)
                            || (P256.w[1] == bid_ten2mk128[ind - 1].hi
                                && (P256.w[0] >= bid_ten2mk128[ind - 1].lo))) {
                            pfpsf.insert(.inexact)
                            // if positive, the truncated value is already the correct result
                            if x_sign != 0 {    // if negative
                                res.lo &+= 1
                                if res.lo == 0 { res.hi+=1 }
                            }
                        }
                    } else if (ind - 1 <= 21) {    // 3 <= ind - 1 <= 21 => 3 <= shift <= 63
                        shift = bid_shiftright128[ind - 1];    // 0 <= shift <= 102
                        res.hi = (P256.w[3] >> shift);
                        res.lo = (P256.w[3] << (64 - shift)) | (P256.w[2] >> shift);
                        // redundant fstar.w[3] = 0;
                        fstar.w[2] = P256.w[2] & bid_maskhigh128[ind - 1];
                        fstar.w[1] = P256.w[1];
                        fstar.w[0] = P256.w[0];
                        // fraction f* > 10^(-x) <=> inexact
                        // f* is in the right position to be compared with
                        // 10^(-x) from bid_ten2mk128[]
                        if (fstar.w[2] != 0 || fstar.w[1] > bid_ten2mk128[ind - 1].hi ||
                            (fstar.w[1] == bid_ten2mk128[ind - 1].hi &&
                             fstar.w[0] >= bid_ten2mk128[ind - 1].lo)) {
                            pfpsf.insert(.inexact)
                            // if positive, the truncated value is already the correct result
                            if x_sign != 0 {    // if negative
                                res.lo &+= 1
                                if res.lo == 0 { res.hi+=1 }
                            }
                        }
                    } else {    // 22 <= ind - 1 <= 33
                        shift = bid_shiftright128[ind - 1] - 64;    // 2 <= shift <= 38
                        res.hi = 0;
                        res.lo = P256.w[3] >> shift;
                        fstar.w[3] = P256.w[3] & bid_maskhigh128[ind - 1];
                        fstar.w[2] = P256.w[2];
                        fstar.w[1] = P256.w[1];
                        fstar.w[0] = P256.w[0];
                        // fraction f* > 10^(-x) <=> inexact
                        // f* is in the right position to be compared with
                        // 10^(-x) from bid_ten2mk128[]
                        if (fstar.w[3] != 0 || fstar.w[2] != 0
                            || fstar.w[1] > bid_ten2mk128[ind - 1].hi
                            || (fstar.w[1] == bid_ten2mk128[ind - 1].hi
                                && fstar.w[0] >= bid_ten2mk128[ind - 1].lo)) {
                            pfpsf.insert(.inexact)
                            // if positive, the truncated value is already the correct result
                            if x_sign != 0 {    // if negative
                                res.lo &+= 1
                                if res.lo == 0 { res.hi+=1 }
                            }
                        }
                    }
                    res.hi = x_sign | 0x3040000000000000 | res.hi;
                    return res
                } else {    // if exp < 0 and q + exp <= 0
                    if x_sign != 0 {    // negative rounds down to -1.0
                        res.hi = 0xb040000000000000;
                        res.lo = 0x0000000000000001;
                    } else {    // positive rpunds down to +0.0
                        res.hi = 0x3040000000000000;
                        res.lo = 0x0000000000000000;
                    }
                    pfpsf.insert(.inexact)
                    return res
                }
            case BID_ROUNDING_UP:
                if ((q + exp) > 0) {    // exp < 0 and 1 <= -exp < q
                    // need to shift right -exp digits from the coefficient; exp will be 0
                    ind = -exp;    // 1 <= ind <= 34; ind is a synonym for 'x'
                    // (number of digits to be chopped off)
                    // chop off ind digits from the lower part of C1
                    // FOR ROUND_TO_NEAREST, WE ADD 1/2 ULP(y) then truncate
                    // FOR ROUND_TO_ZERO, WE DON'T NEED TO ADD 1/2 ULP
                    // FOR ROUND_TO_POSITIVE_INFINITY, WE TRUNCATE, THEN ADD 1 IF POSITIVE
                    // FOR ROUND_TO_NEGATIVE_INFINITY, WE TRUNCATE, THEN ADD 1 IF NEGATIVE
                    // tmp64 = C1.lo;
                    // if (ind <= 19) {
                    //   C1.lo = C1.lo + bid_midpoint64[ind - 1];
                    // } else {
                    //   C1.lo = C1.lo + bid_midpoint128[ind - 20].lo;
                    //   C1.hi = C1.hi + bid_midpoint128[ind - 20].hi;
                    // }
                    // if (C1.lo < tmp64) C1.hi+=1
                    // if carry-out from C1.lo, increment C1.hi
                    // calculate C* and f*
                    // C* is actually floor(C*) in this case
                    // C* and f* need shifting and masking, as shown by
                    // bid_shiftright128[] and bid_maskhigh128[]
                    // 1 <= x <= 34
                    // kx = 10^(-x) = bid_ten2mk128[ind - 1]
                    // C* = C1 * 10^(-x)
                    // the approximation of 10^(-x) was rounded up to 118 bits
                    __mul_128x128_to_256(&P256, C1, bid_ten2mk128[ind - 1]);
                    if (ind - 1 <= 2) {    // 0 <= ind - 1 <= 2 => shift = 0
                        res.hi = P256.w[3];
                        res.lo = P256.w[2];
                        // redundant fstar.w[3] = 0;
                        // redundant fstar.w[2] = 0;
                        // redundant fstar.w[1] = P256.w[1];
                        // redundant fstar.w[0] = P256.w[0];
                        // fraction f* > 10^(-x) <=> inexact
                        // f* is in the right position to be compared with
                        // 10^(-x) from bid_ten2mk128[]
                        if ((P256.w[1] > bid_ten2mk128[ind - 1].hi)
                            || (P256.w[1] == bid_ten2mk128[ind - 1].hi
                                && (P256.w[0] >= bid_ten2mk128[ind - 1].lo))) {
                            pfpsf.insert(.inexact)
                            // if negative, the truncated value is already the correct result
                            if x_sign == 0 {    // if positive
                                res.lo &+= 1
                                if res.lo == 0 { res.hi+=1 }
                            }
                        }
                    } else if (ind - 1 <= 21) {    // 3 <= ind - 1 <= 21 => 3 <= shift <= 63
                        shift = bid_shiftright128[ind - 1];    // 3 <= shift <= 63
                        res.hi = (P256.w[3] >> shift);
                        res.lo = (P256.w[3] << (64 - shift)) | (P256.w[2] >> shift);
                        // redundant fstar.w[3] = 0;
                        fstar.w[2] = P256.w[2] & bid_maskhigh128[ind - 1];
                        fstar.w[1] = P256.w[1];
                        fstar.w[0] = P256.w[0];
                        // fraction f* > 10^(-x) <=> inexact
                        // f* is in the right position to be compared with
                        // 10^(-x) from bid_ten2mk128[]
                        if (fstar.w[2] != 0 || fstar.w[1] > bid_ten2mk128[ind - 1].hi ||
                            (fstar.w[1] == bid_ten2mk128[ind - 1].hi &&
                             fstar.w[0] >= bid_ten2mk128[ind - 1].lo)) {
                            pfpsf.insert(.inexact)
                            // if negative, the truncated value is already the correct result
                            if x_sign == 0 {    // if positive
                                res.lo &+= 1
                                if res.lo == 0 { res.hi+=1 }
                            }
                        }
                    } else {    // 22 <= ind - 1 <= 33
                        shift = bid_shiftright128[ind - 1] - 64;    // 2 <= shift <= 38
                        res.hi = 0;
                        res.lo = P256.w[3] >> shift;
                        fstar.w[3] = P256.w[3] & bid_maskhigh128[ind - 1];
                        fstar.w[2] = P256.w[2];
                        fstar.w[1] = P256.w[1];
                        fstar.w[0] = P256.w[0];
                        // fraction f* > 10^(-x) <=> inexact
                        // f* is in the right position to be compared with
                        // 10^(-x) from bid_ten2mk128[]
                        if (fstar.w[3] != 0 || fstar.w[2] != 0
                            || fstar.w[1] > bid_ten2mk128[ind - 1].hi
                            || (fstar.w[1] == bid_ten2mk128[ind - 1].hi
                                && fstar.w[0] >= bid_ten2mk128[ind - 1].lo)) {
                            pfpsf.insert(.inexact)
                            // if negative, the truncated value is already the correct result
                            if x_sign == 0 {    // if positive
                                res.lo &+= 1
                                if res.lo == 0 { res.hi+=1 }
                            }
                        }
                    }
                    res.hi = x_sign | 0x3040000000000000 | res.hi;
                    return res
                } else {    // if exp < 0 and q + exp <= 0
                    if x_sign != 0 {    // negative rounds up to -0.0
                        res.hi = 0xb040000000000000;
                        res.lo = 0x0000000000000000;
                    } else {    // positive rpunds up to +1.0
                        res.hi = 0x3040000000000000;
                        res.lo = 0x0000000000000001;
                    }
                    pfpsf.insert(.inexact)
                    return res
                }
            case BID_ROUNDING_TO_ZERO:
                if ((q + exp) > 0) {    // exp < 0 and 1 <= -exp < q
                    // need to shift right -exp digits from the coefficient; exp will be 0
                    ind = -exp;    // 1 <= ind <= 34; ind is a synonym for 'x'
                    // (number of digits to be chopped off)
                    // chop off ind digits from the lower part of C1
                    // FOR ROUND_TO_NEAREST, WE ADD 1/2 ULP(y) then truncate
                    // FOR ROUND_TO_ZERO, WE DON'T NEED TO ADD 1/2 ULP
                    // FOR ROUND_TO_POSITIVE_INFINITY, WE TRUNCATE, THEN ADD 1 IF POSITIVE
                    // FOR ROUND_TO_NEGATIVE_INFINITY, WE TRUNCATE, THEN ADD 1 IF NEGATIVE
                    //tmp64 = C1.lo;
                    // if (ind <= 19) {
                    //   C1.lo = C1.lo + bid_midpoint64[ind - 1];
                    // } else {
                    //   C1.lo = C1.lo + bid_midpoint128[ind - 20].lo;
                    //   C1.hi = C1.hi + bid_midpoint128[ind - 20].hi;
                    // }
                    // if (C1.lo < tmp64) C1.hi+=1
                    // if carry-out from C1.lo, increment C1.hi
                    // calculate C* and f*
                    // C* is actually floor(C*) in this case
                    // C* and f* need shifting and masking, as shown by
                    // bid_shiftright128[] and bid_maskhigh128[]
                    // 1 <= x <= 34
                    // kx = 10^(-x) = bid_ten2mk128[ind - 1]
                    // C* = (C1 + 1/2 * 10^x) * 10^(-x)
                    // the approximation of 10^(-x) was rounded up to 118 bits
                    __mul_128x128_to_256(&P256, C1, bid_ten2mk128[ind - 1]);
                    if (ind - 1 <= 2) {    // 0 <= ind - 1 <= 2 => shift = 0
                        res.hi = P256.w[3];
                        res.lo = P256.w[2];
                        // redundant fstar.w[3] = 0;
                        // redundant fstar.w[2] = 0;
                        // redundant fstar.w[1] = P256.w[1];
                        // redundant fstar.w[0] = P256.w[0];
                        // fraction f* > 10^(-x) <=> inexact
                        // f* is in the right position to be compared with
                        // 10^(-x) from bid_ten2mk128[]
                        if ((P256.w[1] > bid_ten2mk128[ind - 1].hi)
                            || (P256.w[1] == bid_ten2mk128[ind - 1].hi
                                && (P256.w[0] >= bid_ten2mk128[ind - 1].lo))) {
                            pfpsf.insert(.inexact)
                        }
                    } else if (ind - 1 <= 21) {    // 3 <= ind - 1 <= 21 => 3 <= shift <= 63
                        shift = bid_shiftright128[ind - 1];    // 3 <= shift <= 63
                        res.hi = (P256.w[3] >> shift);
                        res.lo = (P256.w[3] << (64 - shift)) | (P256.w[2] >> shift);
                        // redundant fstar.w[3] = 0;
                        fstar.w[2] = P256.w[2] & bid_maskhigh128[ind - 1];
                        fstar.w[1] = P256.w[1];
                        fstar.w[0] = P256.w[0];
                        // fraction f* > 10^(-x) <=> inexact
                        // f* is in the right position to be compared with
                        // 10^(-x) from bid_ten2mk128[]
                        if (fstar.w[2] != 0 || fstar.w[1] > bid_ten2mk128[ind - 1].hi ||
                            (fstar.w[1] == bid_ten2mk128[ind - 1].hi &&
                             fstar.w[0] >= bid_ten2mk128[ind - 1].lo)) {
                            pfpsf.insert(.inexact)
                        }
                    } else {    // 22 <= ind - 1 <= 33
                        shift = bid_shiftright128[ind - 1] - 64;    // 2 <= shift <= 38
                        res.hi = 0;
                        res.lo = P256.w[3] >> shift;
                        fstar.w[3] = P256.w[3] & bid_maskhigh128[ind - 1];
                        fstar.w[2] = P256.w[2];
                        fstar.w[1] = P256.w[1];
                        fstar.w[0] = P256.w[0];
                        // fraction f* > 10^(-x) <=> inexact
                        // f* is in the right position to be compared with
                        // 10^(-x) from bid_ten2mk128[]
                        if (fstar.w[3] != 0 || fstar.w[2] != 0
                            || fstar.w[1] > bid_ten2mk128[ind - 1].hi
                            || (fstar.w[1] == bid_ten2mk128[ind - 1].hi
                                && fstar.w[0] >= bid_ten2mk128[ind - 1].lo)) {
                            pfpsf.insert(.inexact)
                        }
                    }
                    res.hi = x_sign | 0x3040000000000000 | res.hi;
                    return res
                } else {    // if exp < 0 and q + exp <= 0 the result is +0 or -0
                    res.hi = x_sign | 0x3040000000000000;
                    res.lo = 0x0000000000000000;
                    pfpsf.insert(.inexact)
                    return res
                }
            default: break
        }
        return res
    }
    
    /*****************************************************************************
     *  BID128 nextup
     ****************************************************************************/
    static func nextup(_ x: UInt128, _ pfpsf: inout Status) -> UInt128 {
        var C1 = UInt128(), res = UInt128(), exp = 0
        var x_exp: UInt64, x = x
        
        //BID_SWAP128 (x);
        // unpack the argument
        let x_sign = x.hi & MASK_SIGN;    // 0 for positive, MASK_SIGN for negative
        C1.hi = x.hi & MASK_COEFF;
        C1.lo = x.lo;
        
        // check for NaN or Infinity
        if ((x.hi & MASK_SPECIAL) == MASK_SPECIAL) {
            // x is special
            if ((x.hi & MASK_NAN) == MASK_NAN) {    // x is NAN
                // if x = NaN, then res = Q (x)
                // check first for non-canonical NaN payload
                if (((x.hi & 0x00003fffffffffff) > 0x0000314dc6448d93) ||
                    (((x.hi & 0x00003fffffffffff) == 0x0000314dc6448d93) && (x.lo > 0x38c15b09ffffffff))) {
                    x.hi = x.hi & 0xffffc00000000000;
                    x.lo = 0x0;
                }
                if ((x.hi & MASK_SNAN) == MASK_SNAN) {    // x is SNAN
                    // set invalid flag
                    pfpsf.insert(.invalidOperation)
                    // return quiet (x)
                    res.hi = x.hi & 0xfc003fffffffffff;    // clear out also G[6]-G[16]
                    res.lo = x.lo;
                } else {    // x is QNaN
                    // return x
                    res.hi = x.hi & 0xfc003fffffffffff;    // clear out G[6]-G[16]
                    res.lo = x.lo;
                }
            } else {    // x is not NaN, so it must be infinity
                if x_sign == 0 {    // x is +inf
                    res.hi = 0x7800000000000000;    // +inf
                    res.lo = 0x0000000000000000;
                } else {    // x is -inf
                    res.hi = 0xdfffed09bead87c0;    // -MAXFP = -999...99 * 10^emax
                    res.lo = 0x378d8e63ffffffff;
                }
            }
            return res
        }
        
        // check for non-canonical values (treated as zero)
        if ((x.hi & 0x6000000000000000) == 0x6000000000000000) {    // G0_G1=11
            // non-canonical
            x_exp = (x.hi << 2) & MASK_EXP;    // biased and shifted left 49 bits
            C1.hi = 0;    // significand high
            C1.lo = 0;    // significand low
        } else {    // G0_G1 != 11
            x_exp = x.hi & MASK_EXP;    // biased and shifted left 49 bits
            if (C1.hi > 0x0001ed09bead87c0 ||
                (C1.hi == 0x0001ed09bead87c0
                 && C1.lo > 0x378d8e63ffffffff)) {
                // x is non-canonical if coefficient is larger than 10^34 -1
                C1.hi = 0;
                C1.lo = 0;
            } else {    // canonical
                // nothing to do
            }
        }
        
        if ((C1.hi == 0x0) && (C1.lo == 0x0)) {
            // x is +/-0
            res.hi = 0x0000000000000000;    // +1 * 10^emin
            res.lo = 0x0000000000000001;
        } else {    // x is not special and is not zero
            if (x.hi == 0x5fffed09bead87c0
                && x.lo == 0x378d8e63ffffffff) {
                // x = +MAXFP = 999...99 * 10^emax
                res.hi = 0x7800000000000000;    // +inf
                res.lo = 0x0000000000000000;
            } else if (x.hi == 0x8000000000000000
                       && x.lo == 0x0000000000000001) {
                // x = -MINFP = 1...99 * 10^emin
                res.hi = 0x8000000000000000;    // -0
                res.lo = 0x0000000000000000;
            } else {    // -MAXFP <= x <= -MINFP - 1 ulp OR MINFP <= x <= MAXFP - 1 ulp
                // can add/subtract 1 ulp to the significand
                
                // Note: we could check here if x >= 10^34 to speed up the case q1 = 34
                // q1 = nr. of decimal digits in x
                // determine first the nr. of bits in x
                let q1 = digitsIn(C1.hi, lo: C1.lo)
//                if (C1.hi == 0) {
//                    if (C1.lo >= 0x0020000000000000) {    // x >= 2^53
//                        // split the 64-bit value in two 32-bit halves to avoid rnd errors
//                        if (C1.lo >= 0x0000000100000000) {    // x >= 2^32
//                            tmp1.d = (double) (C1.lo >> 32);    // exact conversion
//                            x_nr_bits =
//                            33 + ((((unsigned int) (tmp1.ui64 >> 52)) & 0x7ff) -
//                                  0x3ff);
//                        } else {    // x < 2^32
//                            tmp1.d = (double) (C1.lo);    // exact conversion
//                            x_nr_bits =
//                            1 + ((((unsigned int) (tmp1.ui64 >> 52)) & 0x7ff) -
//                                 0x3ff);
//                        }
//                    } else {    // if x < 2^53
//                        tmp1.d = (double) C1.lo;    // exact conversion
//                        x_nr_bits =
//                        1 + ((((unsigned int) (tmp1.ui64 >> 52)) & 0x7ff) - 0x3ff);
//                    }
//                } else {    // C1.hi != 0 => nr. bits = 64 + nr_bits (C1.hi)
//                    tmp1.d = (double) C1.hi;    // exact conversion
//                    x_nr_bits =
//                    65 + ((((unsigned int) (tmp1.ui64 >> 52)) & 0x7ff) - 0x3ff);
//                }
//                q1 = bid_nr_digits[x_nr_bits - 1].digits;
//                if (q1 == 0) {
//                    q1 = bid_nr_digits[x_nr_bits - 1].digits1;
//                    if (C1.hi > bid_nr_digits[x_nr_bits - 1].threshold_hi
//                        || (C1.hi == bid_nr_digits[x_nr_bits - 1].threshold_hi
//                            && C1.lo >= bid_nr_digits[x_nr_bits - 1].threshold_lo))
//                        q1++;
//                }
                // if q1 < P34 then pad the significand with zeros
                var ind = 0
                if (q1 < P34) {
                    exp = Int(x_exp >> 49) - 6176;
                    if (exp + 6176 > P34 - q1) {
                        ind = P34 - q1;    // 1 <= ind <= P34 - 1
                        // pad with P34 - q1 zeros, until exponent = emin
                        // C1 = C1 * 10^ind
                        if (q1 <= 19) {    // 64-bit C1
                            if (ind <= 19) {    // 64-bit 10^ind and 64-bit C1
                                __mul_64x64_to_128MACH (&C1, C1.lo, bid_ten2k64[ind]);
                            } else {    // 128-bit 10^ind and 64-bit C1
                                __mul_128x64_to_128 (&C1, C1.lo, bid_ten2k128[ind - 20]);
                            }
                        } else {    // C1 is (most likely) 128-bit
                            if (ind <= 14) {    // 64-bit 10^ind and 128-bit C1 (most likely)
                                __mul_128x64_to_128 (&C1, bid_ten2k64[ind], C1);
                            } else if (ind <= 19) {    // 64-bit 10^ind and 64-bit C1 (q1 <= 19)
                                __mul_64x64_to_128MACH (&C1, C1.lo, bid_ten2k64[ind]);
                            } else {    // 128-bit 10^ind and 64-bit C1 (C1 must be 64-bit)
                                __mul_128x64_to_128 (&C1, C1.lo, bid_ten2k128[ind - 20]);
                            }
                        }
                        x_exp = x_exp - (UInt64(ind) << 49);
                    } else {    // pad with zeros until the exponent reaches emin
                        ind = exp + 6176;
                        // C1 = C1 * 10^ind
                        if (ind <= 19) {    // 1 <= P34 - q1 <= 19 <=> 15 <= q1 <= 33
                            if (q1 <= 19) {    // 64-bit C1, 64-bit 10^ind
                                __mul_64x64_to_128MACH (&C1, C1.lo, bid_ten2k64[ind]);
                            } else {    // 20 <= q1 <= 33 => 128-bit C1, 64-bit 10^ind
                                __mul_128x64_to_128 (&C1, bid_ten2k64[ind], C1);
                            }
                        } else {    // if 20 <= P34 - q1 <= 33 <=> 1 <= q1 <= 14 =>
                            // 64-bit C1, 128-bit 10^ind
                            __mul_128x64_to_128 (&C1, C1.lo, bid_ten2k128[ind - 20]);
                        }
                        x_exp = EXP_MIN;
                    }
                }
                if x_sign == 0 {    // x > 0
                    // add 1 ulp (add 1 to the significand)
                    C1.lo &+= 1
                    if C1.lo == 0 { C1.hi+=1 }
                    if (C1.hi == 0x0001ed09bead87c0 && C1.lo == 0x378d8e6400000000) {    // if  C1 = 10^34
                        C1.hi = 0x0000314dc6448d93;    // C1 = 10^33
                        C1.lo = 0x38c15b0a00000000;
                        x_exp = x_exp + EXP_P1;
                    }
                } else {    // x < 0
                    // subtract 1 ulp (subtract 1 from the significand)
                    C1.lo &-= 1
                    if C1.lo == 0xffffffffffffffff { C1.hi-=1 }
                    if (x_exp != 0 && C1.hi == 0x0000314dc6448d93 && C1.lo == 0x38c15b09ffffffff) {    // if  C1 = 10^33 - 1
                        C1.hi = 0x0001ed09bead87c0;    // C1 = 10^34 - 1
                        C1.lo = 0x378d8e63ffffffff;
                        x_exp = x_exp - EXP_P1;
                    }
                }
                // assemble the result
                res.hi = x_sign | x_exp | C1.hi;
                res.lo = C1.lo;
            }    // end -MAXFP <= x <= -MINFP - 1 ulp OR MINFP <= x <= MAXFP - 1 ulp
        }    // end x is not special and is not zero
        return (res);
    }
    
    
    static func mul(_ x:UInt128, _ y:UInt128, _ rnd_mode: Rounding, _ pfpsf: inout Status) -> UInt128 {
        var  z = UInt128(upper: 0x5ffe000000000000, lower: 0x0000000000000000)
        var res = UInt128(upper: 0xbaddbaddbaddbadd, lower: 0xbaddbaddbaddbadd)
        var x_exp, y_exp, x_sign, y_sign:UInt64
        var C1 = UInt128(), C2 = UInt128(), x = x, y = y
        
        BID_SWAP128(&x)
        BID_SWAP128(&y)
        
        // skip cases where at least one operand is NaN or infinity
        if (!(((x.hi & MASK_NAN) == MASK_NAN) ||
              ((y.hi & MASK_NAN) == MASK_NAN) ||
              ((x.hi & MASK_ANY_INF) == MASK_INF) ||
              ((y.hi & MASK_ANY_INF) == MASK_INF))) {
            // x, y are 0 or f but not inf or NaN => unpack the arguments and check
            // for non-canonical values
            
            x_sign = x.hi & MASK_SIGN;    // 0 for positive, MASK_SIGN for negative
            C1.hi = x.hi & MASK_COEFF;
            C1.lo = x.lo;
            // check for non-canonical values - treated as zero
            if ((x.hi & 0x6000000000000000) == 0x6000000000000000) {
                // G0_G1=11 => non-canonical
                x_exp = (x.hi << 2) & MASK_EXP;    // biased and shifted left 49 bits
                C1.hi = 0;    // significand high
                C1.lo = 0;    // significand low
            } else {    // G0_G1 != 11
                x_exp = x.hi & MASK_EXP;    // biased and shifted left 49 bits
                if (C1.hi > 0x0001ed09bead87c0 ||
                    (C1.hi == 0x0001ed09bead87c0 &&
                     C1.lo > 0x378d8e63ffffffff)) {
                    // x is non-canonical if coefficient is larger than 10^34 -1
                    C1.hi = 0;
                    C1.lo = 0;
                } else {    // canonical
                    // nothing
                }
            }
            y_sign = y.hi & MASK_SIGN;    // 0 for positive, MASK_SIGN for negative
            C2.hi = y.hi & MASK_COEFF;
            C2.lo = y.lo;
            // check for non-canonical values - treated as zero
            if ((y.hi & 0x6000000000000000) == 0x6000000000000000) {
                // G0_G1=11 => non-canonical
                y_exp = (y.hi << 2) & MASK_EXP;    // biased and shifted left 49 bits
                C2.hi = 0;    // significand high
                C2.lo = 0;    // significand low
            } else {    // G0_G1 != 11
                y_exp = y.hi & MASK_EXP;    // biased and shifted left 49 bits
                if (C2.hi > 0x0001ed09bead87c0 ||
                    (C2.hi == 0x0001ed09bead87c0 &&
                     C2.lo > 0x378d8e63ffffffff)) {
                    // y is non-canonical if coefficient is larger than 10^34 -1
                    C2.hi = 0;
                    C2.lo = 0;
                } else {    // canonical
                    // nothing
                }
            }
            
            let p_sign = x_sign ^ y_sign;    // sign of the product
            var p_exp:UInt64
            let true_p_exp = Int(x_exp >> 49) - 6176 + Int(y_exp >> 49) - 6176;
            // true_p_exp, p_exp are used only for 0 * 0, 0 * f, or f * 0
            if (true_p_exp < -6176) {
                p_exp = 0;    // cannot be less than EXP_MIN
            } else if (true_p_exp > 6111) {
                p_exp = UInt64(6111 + 6176) << 49;    // cannot be more than EXP_MAX
            } else {
                p_exp = UInt64(true_p_exp + 6176) << 49;
            }
            
            if ((C1.hi == 0x0 && C1.lo == 0x0) || (C2.hi == 0x0 && C2.lo == 0x0)) {
                // x = 0 or y = 0
                // the result is 0
                res.hi = p_sign | p_exp;    // preferred exponent in [EXP_MIN, EXP_MAX]
                res.lo = 0x0;
                BID_SWAP128(&res);
                return res
            }    // else continue
        }
        
        BID_SWAP128(&x);
        BID_SWAP128(&y);
        BID_SWAP128(&z);
        
        // swap x and y - ensure that a NaN in x has 'higher precedence' than one in y
        res = fma(y, x, z, rnd_mode, &pfpsf)
        return (res);
    }
    
    static func fma(_ x: UInt128, _ y: UInt128, _ z: UInt128, _ rnd_mode: Rounding, _ pfpsf: inout Status) -> UInt128 {
        var res = UInt128(upper: 0xbaddbaddbaddbadd, lower: 0xbaddbaddbaddbadd)
        var x_sign, y_sign, z_sign, p_sign, tmp_sign, tmp64:UInt64
        var x_exp = 0, y_exp = 0, z_exp = 0, p_exp = 0, ind = 0, R64 = UInt64()
        var true_p_exp:Int
        var C1 = UInt128(), C2 = UInt128(), C3 = UInt128(), P128 = UInt128(), R128 = UInt128()
        var C4 = UInt256(), R256 = UInt256()
        var q1 = 0, q2 = 0, q3 = 0, q4 = 0
        var e1, e2, e3, e4, scale, delta, x0:Int
        let p34 = P34 // used to modify the limit on the number of digits
        var tmp:Double
        var lsb:Int
        var save_fpsf:Status
        var is_midpoint_lt_even = false, is_midpoint_gt_even = false, is_inexact_lt_midpoint = false, is_inexact_gt_midpoint = false
        var is_midpoint_lt_even0 = false, is_midpoint_gt_even0 = false, is_inexact_lt_midpoint0 = false, is_inexact_gt_midpoint0 = false
        var incr_exp = 0, lt_half_ulp = false, eq_half_ulp = false, gt_half_ulp = false, is_tiny = false
        var R192 = UInt192(), P192 = UInt192()
        var C4gt5toq4m1:Bool
        var x = x, y = y, z = z // make these mutable
        
        // the following are based on the table of special cases for fma; the NaN
        // behavior is similar to that of the IA-64 Architecture fma
        
        // identify cases where at least one operand is NaN
        BID_SWAP128(&x)
        BID_SWAP128(&y)
        BID_SWAP128(&z)
        if ((y.hi & MASK_NAN) == MASK_NAN) { // y is NAN
            // if x = {0, f, inf, NaN}, y = NaN, z = {0, f, inf, NaN} then res = Q (y)
            // check first for non-canonical NaN payload
            if (((y.hi & 0x00003fffffffffff) > 0x0000314dc6448d93) ||
                (((y.hi & 0x00003fffffffffff) == 0x0000314dc6448d93) &&
                 (y.lo > 0x38c15b09ffffffff))) {
                y.hi = y.hi & 0xffffc00000000000
                y.lo = 0x0;
            }
            if ((y.hi & MASK_SNAN) == MASK_SNAN) { // y is SNAN
                // set invalid flag
                pfpsf.insert(.invalidOperation)
                
                // return quiet (y)
                res.hi = y.hi & 0xfc003fffffffffff; // clear out also G[6]-G[16]
                res.lo = y.lo;
            } else { // y is QNaN
                // return y
                res.hi = y.hi & 0xfc003fffffffffff; // clear out G[6]-G[16]
                res.lo = y.lo;
                // if z = SNaN or x = SNaN signal invalid exception
                if ((z.hi & MASK_SNAN) == MASK_SNAN ||
                    (x.hi & MASK_SNAN) == MASK_SNAN) {
                    // set invalid flag
                    pfpsf.insert(.invalidOperation)
                }
            }
            //            ptr_is_midpoint_lt_even = is_midpoint_lt_even;
            //            ptr_is_midpoint_gt_even = is_midpoint_gt_even;
            //            ptr_is_inexact_lt_midpoint = is_inexact_lt_midpoint;
            //            ptr_is_inexact_gt_midpoint = is_inexact_gt_midpoint;
            BID_SWAP128(&res)
            return res
        } else if ((z.hi & MASK_NAN) == MASK_NAN) { // z is NAN
            // if x = {0, f, inf, NaN}, y = {0, f, inf}, z = NaN then res = Q (z)
            // check first for non-canonical NaN payload
            if (((z.hi & 0x00003fffffffffff) > 0x0000314dc6448d93) ||
                (((z.hi & 0x00003fffffffffff) == 0x0000314dc6448d93) &&
                 (z.lo > 0x38c15b09ffffffff))) {
                z.hi = z.hi & 0xffffc00000000000;
                z.lo = 0x0;
            }
            if ((z.hi & MASK_SNAN) == MASK_SNAN) { // z is SNAN
                // set invalid flag
                pfpsf.insert(.invalidOperation)
                // return quiet (z)
                res.hi = z.hi & 0xfc003fffffffffff; // clear out also G[6]-G[16]
                res.lo = z.lo;
            } else { // z is QNaN
                // return z
                res.hi = z.hi & 0xfc003fffffffffff; // clear out G[6]-G[16]
                res.lo = z.lo;
                // if x = SNaN signal invalid exception
                if ((x.hi & MASK_SNAN) == MASK_SNAN) {
                    // set invalid flag
                    pfpsf.insert(.invalidOperation)
                }
            }
            //            ptr_is_midpoint_lt_even = is_midpoint_lt_even;
            //            ptr_is_midpoint_gt_even = is_midpoint_gt_even;
            //            ptr_is_inexact_lt_midpoint = is_inexact_lt_midpoint;
            //            ptr_is_inexact_gt_midpoint = is_inexact_gt_midpoint;
            BID_SWAP128(&res)
            return res
        } else if ((x.hi & MASK_NAN) == MASK_NAN) { // x is NAN
            // if x = NaN, y = {0, f, inf}, z = {0, f, inf} then res = Q (x)
            // check first for non-canonical NaN payload
            if (((x.hi & 0x00003fffffffffff) > 0x0000314dc6448d93) ||
                (((x.hi & 0x00003fffffffffff) == 0x0000314dc6448d93) &&
                 (x.lo > 0x38c15b09ffffffff))) {
                x.hi = x.hi & 0xffffc00000000000;
                x.lo = 0x0;
            }
            if ((x.hi & MASK_SNAN) == MASK_SNAN) { // x is SNAN
                // set invalid flag
                pfpsf.insert(.invalidOperation)
                // return quiet (x)
                res.hi = x.hi & 0xfc003fffffffffff; // clear out also G[6]-G[16]
                res.lo = x.lo;
            } else { // x is QNaN
                // return x
                res.hi = x.hi & 0xfc003fffffffffff; // clear out G[6]-G[16]
                res.lo = x.lo;
            }
            //            ptr_is_midpoint_lt_even = is_midpoint_lt_even;
            //            ptr_is_midpoint_gt_even = is_midpoint_gt_even;
            //            ptr_is_inexact_lt_midpoint = is_inexact_lt_midpoint;
            //            ptr_is_inexact_gt_midpoint = is_inexact_gt_midpoint;
            BID_SWAP128(&res)
            return res
        }
        // x, y, z are 0, f, or inf but not NaN => unpack the arguments and check
        // for non-canonical values
        
        x_sign = x.hi & MASK_SIGN; // 0 for positive, MASK_SIGN for negative
        C1.hi = x.hi & MASK_COEFF;
        C1.lo = x.lo;
        if ((x.hi & MASK_ANY_INF) != MASK_INF) { // x != inf
            // if x is not infinity check for non-canonical values - treated as zero
            if ((x.hi & 0x6000000000000000) == 0x6000000000000000) { // G0_G1=11
                // non-canonical
                x_exp = Int((x.hi << 2) & MASK_EXP) // biased and shifted left 49 bits
                C1.hi = 0; // significand high
                C1.lo = 0; // significand low
            } else { // G0_G1 != 11
                x_exp = Int(x.hi & MASK_EXP) // biased and shifted left 49 bits
                if (C1.hi > 0x0001ed09bead87c0 ||
                    (C1.hi == 0x0001ed09bead87c0 &&
                     C1.lo > 0x378d8e63ffffffff)) {
                    // x is non-canonical if coefficient is larger than 10^34 -1
                    C1.hi = 0;
                    C1.lo = 0;
                } else { // canonical
                    // nothing
                }
            }
        }
        y_sign = y.hi & MASK_SIGN; // 0 for positive, MASK_SIGN for negative
        C2.hi = y.hi & MASK_COEFF;
        C2.lo = y.lo;
        if ((y.hi & MASK_ANY_INF) != MASK_INF) { // y != inf
            // if y is not infinity check for non-canonical values - treated as zero
            if ((y.hi & 0x6000000000000000) == 0x6000000000000000) { // G0_G1=11
                // non-canonical
                y_exp = Int((y.hi << 2) & MASK_EXP) // biased and shifted left 49 bits
                C2.hi = 0; // significand high
                C2.lo = 0; // significand low
            } else { // G0_G1 != 11
                y_exp = Int(y.hi & MASK_EXP) // biased and shifted left 49 bits
                if (C2.hi > 0x0001ed09bead87c0 ||
                    (C2.hi == 0x0001ed09bead87c0 &&
                     C2.lo > 0x378d8e63ffffffff)) {
                    // y is non-canonical if coefficient is larger than 10^34 -1
                    C2.hi = 0;
                    C2.lo = 0;
                } else { // canonical
                    // nothing
                }
            }
        }
        z_sign = z.hi & MASK_SIGN; // 0 for positive, MASK_SIGN for negative
        C3.hi = z.hi & MASK_COEFF;
        C3.lo = z.lo;
        if ((z.hi & MASK_ANY_INF) != MASK_INF) { // z != inf
            // if z is not infinity check for non-canonical values - treated as zero
            if ((z.hi & 0x6000000000000000) == 0x6000000000000000) { // G0_G1=11
                // non-canonical
                z_exp = Int((z.hi << 2) & MASK_EXP) // biased and shifted left 49 bits
                C3.hi = 0; // significand high
                C3.lo = 0; // significand low
            } else { // G0_G1 != 11
                z_exp = Int(z.hi & MASK_EXP) // biased and shifted left 49 bits
                if (C3.hi > 0x0001ed09bead87c0 ||
                    (C3.hi == 0x0001ed09bead87c0 &&
                     C3.lo > 0x378d8e63ffffffff)) {
                    // z is non-canonical if coefficient is larger than 10^34 -1
                    C3.hi = 0;
                    C3.lo = 0;
                } else { // canonical
                    // nothing
                }
            }
        }
        
        p_sign = x_sign ^ y_sign; // sign of the product
        
        // identify cases where at least one operand is infinity
        
        if ((x.hi & MASK_ANY_INF) == MASK_INF) { // x = inf
            if ((y.hi & MASK_ANY_INF) == MASK_INF) { // y = inf
                if ((z.hi & MASK_ANY_INF) == MASK_INF) { // z = inf
                    if (p_sign == z_sign) {
                        res.hi = z_sign | MASK_INF;
                        res.lo = 0x0;
                    } else {
                        // return QNaN Indefinite
                        res.hi = 0x7c00000000000000;
                        res.lo = 0x0000000000000000;
                        // set invalid flag
                        pfpsf.insert(.invalidOperation)
                    }
                } else { // z = 0 or z = f
                    res.hi = p_sign | MASK_INF;
                    res.lo = 0x0;
                }
            } else if (C2.hi != 0 || C2.lo != 0) { // y = f
                if ((z.hi & MASK_ANY_INF) == MASK_INF) { // z = inf
                    if (p_sign == z_sign) {
                        res.hi = z_sign | MASK_INF;
                        res.lo = 0x0;
                    } else {
                        // return QNaN Indefinite
                        res.hi = 0x7c00000000000000;
                        res.lo = 0x0000000000000000;
                        // set invalid flag
                        pfpsf.insert(.invalidOperation)
                    }
                } else { // z = 0 or z = f
                    res.hi = p_sign | MASK_INF;
                    res.lo = 0x0;
                }
            } else { // y = 0
                // return QNaN Indefinite
                res.hi = 0x7c00000000000000;
                res.lo = 0x0000000000000000;
                // set invalid flag
                pfpsf.insert(.invalidOperation)
            }
            //            ptr_is_midpoint_lt_even = is_midpoint_lt_even;
            //            ptr_is_midpoint_gt_even = is_midpoint_gt_even;
            //            ptr_is_inexact_lt_midpoint = is_inexact_lt_midpoint;
            //            ptr_is_inexact_gt_midpoint = is_inexact_gt_midpoint;
            BID_SWAP128(&res)
            return res
        } else if ((y.hi & MASK_ANY_INF) == MASK_INF) { // y = inf
            if ((z.hi & MASK_ANY_INF) == MASK_INF) { // z = inf
                // x = f, necessarily
                if ((p_sign != z_sign)
                    || (C1.hi == 0x0 && C1.lo == 0x0)) {
                    // return QNaN Indefinite
                    res.hi = 0x7c00000000000000;
                    res.lo = 0x0000000000000000;
                    // set invalid flag
                    pfpsf.insert(.invalidOperation)
                } else {
                    res.hi = z_sign | MASK_INF;
                    res.lo = 0x0;
                }
            } else if (C1.hi == 0x0 && C1.lo == 0x0) { // x = 0
                // z = 0, f, inf
                // return QNaN Indefinite
                res.hi = 0x7c00000000000000;
                res.lo = 0x0000000000000000;
                // set invalid flag
                pfpsf.insert(.invalidOperation)
            } else {
                // x = f and z = 0, f, necessarily
                res.hi = p_sign | MASK_INF;
                res.lo = 0x0;
            }
            //            ptr_is_midpoint_lt_even = is_midpoint_lt_even;
            //            ptr_is_midpoint_gt_even = is_midpoint_gt_even;
            //            ptr_is_inexact_lt_midpoint = is_inexact_lt_midpoint;
            //            ptr_is_inexact_gt_midpoint = is_inexact_gt_midpoint;
            BID_SWAP128(&res)
            return res
        } else if ((z.hi & MASK_ANY_INF) == MASK_INF) { // z = inf
            // x = 0, f and y = 0, f, necessarily
            res.hi = z_sign | MASK_INF;
            res.lo = 0x0;
            //            ptr_is_midpoint_lt_even = is_midpoint_lt_even;
            //            ptr_is_midpoint_gt_even = is_midpoint_gt_even;
            //            ptr_is_inexact_lt_midpoint = is_inexact_lt_midpoint;
            //            ptr_is_inexact_gt_midpoint = is_inexact_gt_midpoint;
            BID_SWAP128(&res)
            return res
        }
        
        true_p_exp = (x_exp >> 49) - 6176 + (y_exp >> 49) - 6176;
        if (true_p_exp < -6176) {
            p_exp = 0; // cannot be less than EXP_MIN
        } else {
            p_exp = Int(UInt64(true_p_exp + 6176) << 49)
        }
        
        if (((C1.hi == 0x0 && C1.lo == 0x0) || (C2.hi == 0x0 && C2.lo == 0x0)) && C3.hi == 0x0 && C3.lo == 0x0) {
            // (x = 0 or y = 0) and z = 0
            // the result is 0
            if (p_exp < z_exp) {
                res.hi = UInt64(p_exp) // preferred exponent
            } else {
                res.hi = UInt64(z_exp) // preferred exponent
            }
            if (p_sign == z_sign) {
                res.hi |= z_sign;
                res.lo = 0x0;
            } else { // x * y and z have opposite signs
                if (rnd_mode == BID_ROUNDING_DOWN) {
                    // res = -0.0
                    res.hi |= MASK_SIGN;
                    res.lo = 0x0;
                } else {
                    // res = +0.0
                    // res.hi |= 0x0;
                    res.lo = 0x0;
                }
            }
            //            ptr_is_midpoint_lt_even = is_midpoint_lt_even;
            //            ptr_is_midpoint_gt_even = is_midpoint_gt_even;
            //            ptr_is_inexact_lt_midpoint = is_inexact_lt_midpoint;
            //            ptr_is_inexact_gt_midpoint = is_inexact_gt_midpoint;
            BID_SWAP128(&res)
            return res
        }
        // from this point on, we may need to know the number of decimal digits
        // in the significands of x, y, z when x, y, z != 0
        q1 = digitsIn(C1.hi, lo: C1.lo)
        //    if (C1.hi != 0 || C1.lo != 0) { // x = f (non-zero finite)
        //      // q1 = nr. of decimal digits in x
        //      // determine first the nr. of bits in x
        //      if (C1.hi == 0) {
        //        if (C1.lo >= 0x0020000000000000) { // x >= 2^53
        //          // split the 64-bit value in two 32-bit halves to avoid rounding errors
        //          tmp.d = (double) (C1.lo >> 32); // exact conversion
        //          x_nr_bits =
        //            33 + ((((unsigned int) (tmp.ui64 >> 52)) & 0x7ff) - 0x3ff);
        //        } else { // if x < 2^53
        //          tmp.d = (double) C1.lo; // exact conversion
        //          x_nr_bits =
        //            1 + ((((unsigned int) (tmp.ui64 >> 52)) & 0x7ff) - 0x3ff);
        //        }
        //      } else { // C1.hi != 0 => nr. bits = 64 + nr_bits (C1.hi)
        //        tmp.d = (double) C1.hi; // exact conversion
        //        x_nr_bits =
        //          65 + ((((unsigned int) (tmp.ui64 >> 52)) & 0x7ff) - 0x3ff);
        //      }
        //      q1 = bid_nr_digits[x_nr_bits - 1].digits;
        //      if (q1 == 0) {
        //        q1 = bid_nr_digits[x_nr_bits - 1].digits1;
        //        if (C1.hi > bid_nr_digits[x_nr_bits - 1].threshold_hi ||
        //            (C1.hi == bid_nr_digits[x_nr_bits - 1].threshold_hi &&
        //             C1.lo >= bid_nr_digits[x_nr_bits - 1].threshold_lo))
        //          q1+=1
        //      }
        //    }
        
        q2 = digitsIn(C2.hi, lo: C2.lo)
        //    if (C2.hi != 0 || C2.lo != 0) { // y = f (non-zero finite)
        //      // q2 = nr. of decimal digits in y
        //      // determine first the nr. of bits in y
        //      if (C2.hi == 0) {
        //        if (C2.lo >= 0x0020000000000000) { // y >= 2^53
        //          // split the 64-bit value in two 32-bit halves to avoid rounding errors
        //          tmp.d = (double) (C2.lo >> 32); // exact conversion
        //          y_nr_bits =
        //            33 + ((((unsigned int) (tmp.ui64 >> 52)) & 0x7ff) - 0x3ff);
        //        } else { // if y < 2^53
        //          tmp.d = (double) C2.lo; // exact conversion
        //          y_nr_bits =
        //            1 + ((((unsigned int) (tmp.ui64 >> 52)) & 0x7ff) - 0x3ff);
        //        }
        //      } else { // C2.hi != 0 => nr. bits = 64 + nr_bits (C2.hi)
        //        tmp.d = (double) C2.hi; // exact conversion
        //        y_nr_bits =
        //          65 + ((((unsigned int) (tmp.ui64 >> 52)) & 0x7ff) - 0x3ff);
        //      }
        //      q2 = bid_nr_digits[y_nr_bits - 1].digits;
        //      if (q2 == 0) {
        //        q2 = bid_nr_digits[y_nr_bits - 1].digits1;
        //        if (C2.hi > bid_nr_digits[y_nr_bits - 1].threshold_hi ||
        //            (C2.hi == bid_nr_digits[y_nr_bits - 1].threshold_hi &&
        //             C2.lo >= bid_nr_digits[y_nr_bits - 1].threshold_lo))
        //          q2+=1
        //      }
        //    }
        
        q3 = digitsIn(C3.hi, lo: C3.lo)
        //    if (C3.hi != 0 || C3.lo != 0) { // z = f (non-zero finite)
        //      // q3 = nr. of decimal digits in z
        //      // determine first the nr. of bits in z
        //      if (C3.hi == 0) {
        //        if (C3.lo >= 0x0020000000000000) { // z >= 2^53
        //          // split the 64-bit value in two 32-bit halves to avoid rounding errors
        //          tmp.d = (double) (C3.lo >> 32); // exact conversion
        //          z_nr_bits =
        //            33 + ((((unsigned int) (tmp.ui64 >> 52)) & 0x7ff) - 0x3ff);
        //        } else { // if z < 2^53
        //          tmp.d = (double) C3.lo; // exact conversion
        //          z_nr_bits =
        //            1 + ((((unsigned int) (tmp.ui64 >> 52)) & 0x7ff) - 0x3ff);
        //        }
        //      } else { // C3.hi != 0 => nr. bits = 64 + nr_bits (C3.hi)
        //        tmp.d = (double) C3.hi; // exact conversion
        //        z_nr_bits =
        //          65 + ((((unsigned int) (tmp.ui64 >> 52)) & 0x7ff) - 0x3ff);
        //      }
        //      q3 = bid_nr_digits[z_nr_bits - 1].digits;
        //      if (q3 == 0) {
        //        q3 = bid_nr_digits[z_nr_bits - 1].digits1;
        //        if (C3.hi > bid_nr_digits[z_nr_bits - 1].threshold_hi ||
        //            (C3.hi == bid_nr_digits[z_nr_bits - 1].threshold_hi &&
        //             C3.lo >= bid_nr_digits[z_nr_bits - 1].threshold_lo)) {
        //          q3+=1
        //        }
        //      }
        //    }
        
        if ((C1.hi == 0x0 && C1.lo == 0x0) || (C2.hi == 0x0 && C2.lo == 0x0)) {
            // x = 0 or y = 0
            // z = f, necessarily; for 0 + z return z, with the preferred exponent
            // the result is z, but need to get the preferred exponent
            if (z_exp <= p_exp) { // the preferred exponent is z_exp
                res.hi = z_sign | (UInt64(z_exp) & MASK_EXP) | C3.hi;
                res.lo = C3.lo;
            } else { // if (p_exp < z_exp) the preferred exponent is p_exp
                // return (C3 * 10^scale) * 10^(z_exp - scale)
                // where scale = min (p34-q3, (z_exp-p_exp) >> 49)
                scale = p34 - q3;
                ind = (z_exp - p_exp) >> 49;
                if (ind < scale) {
                    scale = ind;
                }
                if (scale == 0) {
                    res.hi = z.hi; // & MASK_COEFF, which is redundant
                    res.lo = z.lo;
                } else if (q3 <= 19) { // z fits in 64 bits
                    if (scale <= 19) { // 10^scale fits in 64 bits
                        // 64 x 64 C3.lo * bid_ten2k64[scale]
                        __mul_64x64_to_128MACH(&res, C3.lo, bid_ten2k64[scale]);
                    } else { // 10^scale fits in 128 bits
                        // 64 x 128 C3.lo * bid_ten2k128[scale - 20]
                        __mul_128x64_to_128(&res, C3.lo, bid_ten2k128[scale - 20]);
                    }
                } else { // z fits in 128 bits, but 10^scale must fit in 64 bits
                    // 64 x 128 bid_ten2k64[scale] * C3
                    __mul_128x64_to_128(&res, bid_ten2k64[scale], C3);
                }
                // subtract scale from the exponent
                z_exp = z_exp - Int(scale << 49);
                res.hi = z_sign | (UInt64(z_exp) & MASK_EXP) | res.hi;
            }
            //            ptr_is_midpoint_lt_even = is_midpoint_lt_even;
            //            ptr_is_midpoint_gt_even = is_midpoint_gt_even;
            //            ptr_is_inexact_lt_midpoint = is_inexact_lt_midpoint;
            //            ptr_is_inexact_gt_midpoint = is_inexact_gt_midpoint;
            BID_SWAP128(&res)
            return res
        } else {
            // continue with x = f, y = f, z = 0 or x = f, y = f, z = f
        }
        
        e1 = (x_exp >> 49) - 6176; // unbiased exponent of x
        e2 = (y_exp >> 49) - 6176; // unbiased exponent of y
        e3 = (z_exp >> 49) - 6176; // unbiased exponent of z
        e4 = e1 + e2; // unbiased exponent of the exact x * y
        
        // calculate C1 * C2 and its number of decimal digits, q4
        
        // the exact product has either q1 + q2 - 1 or q1 + q2 decimal digits
        // where 2 <= q1 + q2 <= 68
        // calculate C4 = C1 * C2 and determine q
        C4.w[3] = 0; C4.w[2] = 0; C4.w[1] = 0; C4.w[0] = 0
        var C4s = UInt128()
        if (q1 + q2 <= 19) { // if 2 <= q1 + q2 <= 19, C4 = C1 * C2 fits in 64 bits
            C4.w[0] = C1.lo * C2.lo;
            // if C4 < 10^(q1+q2-1) then q4 = q1 + q2 - 1 else q4 = q1 + q2
            if (C4.w[0] < bid_ten2k64[q1 + q2 - 1]) {
                q4 = q1 + q2 - 1; // q4 in [1, 18]
            } else {
                q4 = q1 + q2; // q4 in [2, 19]
            }
            // length of C1 * C2 rounded up to a multiple of 64 bits is len = 64;
        } else if (q1 + q2 == 20) { // C4 = C1 * C2 fits in 64 or 128 bits
            // q1 <= 19 and q2 <= 19 so both C1 and C2 fit in 64 bits
            __mul_64x64_to_128MACH(&C4s, C1.lo, C2.lo)
            C4.w[0] = C4s.lo; C4.w[1] = C4s.hi
            // if C4 < 10^(q1+q2-1) = 10^19 then q4 = q1+q2-1 = 19 else q4 = q1+q2 = 20
            if (C4.w[1] == 0 && C4.w[0] < bid_ten2k64[19]) { // 19 = q1+q2-1
                // length of C1 * C2 rounded up to a multiple of 64 bits is len = 64;
                q4 = 19; // 19 = q1 + q2 - 1
            } else {
                // if (C4.hi == 0)
                //   length of C1 * C2 rounded up to a multiple of 64 bits is len = 64;
                // else
                //   length of C1 * C2 rounded up to a multiple of 64 bits is len = 128;
                q4 = 20; // 20 = q1 + q2
            }
        } else if (q1 + q2 <= 38) { // 21 <= q1 + q2 <= 38
            // C4 = C1 * C2 fits in 64 or 128 bits
            // (64 bits possibly, but only when q1 + q2 = 21 and C4 has 20 digits)
            // at least one of C1, C2 has at most 19 decimal digits & fits in 64 bits
            if (q1 <= 19) {
                __mul_128x64_to_128(&C4s, C1.lo, C2);
            } else { // q2 <= 19
                __mul_128x64_to_128(&C4s, C2.lo, C1);
            }
            C4.w[0] = C4s.lo; C4.w[1] = C4s.hi
            // if C4 < 10^(q1+q2-1) then q4 = q1 + q2 - 1 else q4 = q1 + q2
            if (C4.w[1] < bid_ten2k128[q1 + q2 - 21].hi ||
                (C4.w[1] == bid_ten2k128[q1 + q2 - 21].hi &&
                 C4.w[0] < bid_ten2k128[q1 + q2 - 21].lo)) {
                // if (C4.hi == 0) // q4 = 20, necessarily
                //   length of C1 * C2 rounded up to a multiple of 64 bits is len = 64;
                // else
                //   length of C1 * C2 rounded up to a multiple of 64 bits is len = 128;
                q4 = q1 + q2 - 1; // q4 in [20, 37]
            } else {
                // length of C1 * C2 rounded up to a multiple of 64 bits is len = 128;
                q4 = q1 + q2; // q4 in [21, 38]
            }
        } else if (q1 + q2 == 39) { // C4 = C1 * C2 fits in 128 or 192 bits
            // both C1 and C2 fit in 128 bits (actually in 113 bits)
            // may replace this by 128x128_to192
            __mul_128x128_to_256(&C4, C1, C2); // C4.w[3] is 0
            // if C4 < 10^(q1+q2-1) = 10^38 then q4 = q1+q2-1 = 38 else q4 = q1+q2 = 39
            if (C4.w[2] == 0 && (C4.w[1] < bid_ten2k128[18].hi ||
                                 (C4.w[1] == bid_ten2k128[18].hi
                                  && C4.w[0] < bid_ten2k128[18].lo))) {
                // 18 = 38 - 20 = q1+q2-1 - 20
                // length of C1 * C2 rounded up to a multiple of 64 bits is len = 128;
                q4 = 38; // 38 = q1 + q2 - 1
            } else {
                // if (C4.w[2] == 0)
                // length of C1 * C2 rounded up to a multiple of 64 bits is len = 128;
                // else
                //   length of C1 * C2 rounded up to a multiple of 64 bits is len = 192;
                q4 = 39; // 39 = q1 + q2
            }
        } else if (q1 + q2 <= 57) { // 40 <= q1 + q2 <= 57
            // C4 = C1 * C2 fits in 128 or 192 bits
            // (128 bits possibly, but only when q1 + q2 = 40 and C4 has 39 digits)
            // both C1 and C2 fit in 128 bits (actually in 113 bits); at most one
            // may fit in 64 bits
            C4s.lo = C4.w[0]; C4s.hi = C4.w[1]
            if (C1.hi == 0) { // C1 fits in 64 bits
                // __mul_64x128_full (REShi64, RESlo128, A64, B128)
                __mul_64x128_full(&C4.w[2], &C4s, C1.lo, C2)
                C4.w[0] = C4s.lo; C4.w[1] = C4s.hi
            } else if (C2.hi == 0) { // C2 fits in 64 bits
                // __mul_64x128_full (REShi64, RESlo128, A64, B128)
                __mul_64x128_full(&C4.w[2], &C4s, C2.lo, C1)
                C4.w[0] = C4s.lo; C4.w[1] = C4s.hi
            } else { // both C1 and C2 require 128 bits
                // may use __mul_128x128_to_192 (C4.w[2], C4.w[0], C2.w[0], C1);
                __mul_128x128_to_256(&C4, C1, C2); // C4.w[3] = 0
            }
            // if C4 < 10^(q1+q2-1) then q4 = q1 + q2 - 1 else q4 = q1 + q2
            if (C4.w[2] < bid_ten2k256[q1 + q2 - 40].w[2] ||
                (C4.w[2] == bid_ten2k256[q1 + q2 - 40].w[2] &&
                 (C4.w[1] < bid_ten2k256[q1 + q2 - 40].w[1] ||
                  (C4.w[1] == bid_ten2k256[q1 + q2 - 40].w[1] &&
                   C4.w[0] < bid_ten2k256[q1 + q2 - 40].w[0])))) {
                // if (C4.w[2] == 0) // q4 = 39, necessarily
                //   length of C1 * C2 rounded up to a multiple of 64 bits is len = 128;
                // else
                //   length of C1 * C2 rounded up to a multiple of 64 bits is len = 192;
                q4 = q1 + q2 - 1; // q4 in [39, 56]
            } else {
                // length of C1 * C2 rounded up to a multiple of 64 bits is len = 192;
                q4 = q1 + q2; // q4 in [40, 57]
            }
        } else if (q1 + q2 == 58) { // C4 = C1 * C2 fits in 192 or 256 bits;
            // both C1 and C2 fit in 128 bits (actually in 113 bits); none can
            // fit in 64 bits, because each number must have at least 24 decimal
            // digits for the sum to have 58 (as the max. nr. of digits is 34) =>
            // C1.hi != 0 and C2.hi != 0
            __mul_128x128_to_256(&C4, C1, C2);
            // if C4 < 10^(q1+q2-1) = 10^57 then q4 = q1+q2-1 = 57 else q4 = q1+q2 = 58
            if (C4.w[3] == 0 && (C4.w[2] < bid_ten2k256[18].w[2] ||
                                 (C4.w[2] == bid_ten2k256[18].w[2]
                                  && (C4.w[1] < bid_ten2k256[18].w[1]
                                      || (C4.w[1] == bid_ten2k256[18].w[1]
                                          && C4.w[0] < bid_ten2k256[18].w[0]))))) {
                // 18 = 57 - 39 = q1+q2-1 - 39
                // length of C1 * C2 rounded up to a multiple of 64 bits is len = 192;
                q4 = 57; // 57 = q1 + q2 - 1
            } else {
                // if (C4.w[3] == 0)
                //   length of C1 * C2 rounded up to a multiple of 64 bits is len = 192;
                // else
                //   length of C1 * C2 rounded up to a multiple of 64 bits is len = 256;
                q4 = 58; // 58 = q1 + q2
            }
        } else { // if 59 <= q1 + q2 <= 68
            // C4 = C1 * C2 fits in 192 or 256 bits
            // (192 bits possibly, but only when q1 + q2 = 59 and C4 has 58 digits)
            // both C1 and C2 fit in 128 bits (actually in 113 bits); none fits in
            // 64 bits
            // may use __mul_128x128_to_192 (C4.w[2], C4.w[0], C2.w[0], C1);
            __mul_128x128_to_256(&C4, C1, C2); // C4.w[3] = 0
            // if C4 < 10^(q1+q2-1) then q4 = q1 + q2 - 1 else q4 = q1 + q2
            if (C4.w[3] < bid_ten2k256[q1 + q2 - 40].w[3] ||
                (C4.w[3] == bid_ten2k256[q1 + q2 - 40].w[3] &&
                 (C4.w[2] < bid_ten2k256[q1 + q2 - 40].w[2] ||
                  (C4.w[2] == bid_ten2k256[q1 + q2 - 40].w[2] &&
                   (C4.w[1] < bid_ten2k256[q1 + q2 - 40].w[1] ||
                    (C4.w[1] == bid_ten2k256[q1 + q2 - 40].w[1] &&
                     C4.w[0] < bid_ten2k256[q1 + q2 - 40].w[0])))))) {
                // if (C4.w[3] == 0) // q4 = 58, necessarily
                //   length of C1 * C2 rounded up to a multiple of 64 bits is len = 192;
                // else
                //   length of C1 * C2 rounded up to a multiple of 64 bits is len = 256;
                q4 = q1 + q2 - 1; // q4 in [58, 67]
            } else {
                // length of C1 * C2 rounded up to a multiple of 64 bits is len = 256;
                q4 = q1 + q2; // q4 in [59, 68]
            }
        }
        
        if (C3.hi == 0x0 && C3.lo == 0x0) { // x = f, y = f, z = 0
            save_fpsf = pfpsf; // sticky bits - caller value must be preserved
            pfpsf = Status.clearFlags
            
            if (q4 > p34) {
                
                // truncate C4 to p34 digits into res
                // x = q4-p34, 1 <= x <= 34 because 35 <= q4 <= 68
                x0 = q4 - p34;
                if (q4 <= 38) {
                    P128.hi = C4.w[1];
                    P128.lo = C4.w[0];
                    bid_round128_19_38 (q4, x0, P128, &res, &incr_exp,
                                        &is_midpoint_lt_even, &is_midpoint_gt_even,
                                        &is_inexact_lt_midpoint,
                                        &is_inexact_gt_midpoint);
                } else if (q4 <= 57) { // 35 <= q4 <= 57
                    P192.w[2] = C4.w[2];
                    P192.w[1] = C4.w[1];
                    P192.w[0] = C4.w[0];
                    bid_round192_39_57 (q4, x0, P192, &R192, &incr_exp,
                                        &is_midpoint_lt_even, &is_midpoint_gt_even,
                                        &is_inexact_lt_midpoint,
                                        &is_inexact_gt_midpoint);
                    res.lo = R192.w[0];
                    res.hi = R192.w[1];
                } else { // if (q4 <= 68)
                    bid_round256_58_76 (q4, x0, C4, &R256, &incr_exp,
                                        &is_midpoint_lt_even, &is_midpoint_gt_even,
                                        &is_inexact_lt_midpoint,
                                        &is_inexact_gt_midpoint);
                    res.lo = R256.w[0];
                    res.hi = R256.w[1];
                }
                e4 = e4 + x0;
                q4 = p34;
                if incr_exp != 0 {
                    e4 = e4 + 1;
                    if (q4 + e4 == expmin + p34) { pfpsf.formUnion([.inexact, .underflow]) }
                }
                // res is now the coefficient of the result rounded to the destination
                // precision, with unbounded exponent; the exponent is e4; q4=digits(res)
            } else { // if (q4 <= p34)
                // C4 * 10^e4 is the result rounded to the destination precision, with
                // unbounded exponent (which is exact)
                
                if ((q4 + e4 <= p34 + expmax) && (e4 > expmax)) {
                    // e4 is too large, but can be brought within range by scaling up C4
                    scale = e4 - expmax; // 1 <= scale < P-q4 <= P-1 => 1 <= scale <= P-2
                    // res = (C4 * 10^scale) * 10^expmax
                    if (q4 <= 19) { // C4 fits in 64 bits
                        if (scale <= 19) { // 10^scale fits in 64 bits
                            // 64 x 64 C4.w[0] * bid_ten2k64[scale]
                            __mul_64x64_to_128MACH(&res, C4.w[0], bid_ten2k64[scale]);
                        } else { // 10^scale fits in 128 bits
                            // 64 x 128 C4.w[0] * bid_ten2k128[scale - 20]
                            __mul_128x64_to_128(&res, C4.w[0], bid_ten2k128[scale - 20]);
                        }
                    } else { // C4 fits in 128 bits, but 10^scale must fit in 64 bits
                        // 64 x 128 bid_ten2k64[scale] * CC43
                        C4s.lo = C4.w[0]; C4s.hi = C4.w[1]
                        __mul_128x64_to_128(&res, bid_ten2k64[scale], C4s)
                    }
                    e4 = e4 - scale; // expmax
                    q4 = q4 + scale;
                } else {
                    res.hi = C4.w[1];
                    res.lo = C4.w[0];
                }
                // res is the coefficient of the result rounded to the destination
                // precision, with unbounded exponent (it has q4 digits); the exponent
                // is e4 (exact result)
            }
            
            // check for overflow
            if (q4 + e4 > p34 + expmax) {
                if (rnd_mode == BID_ROUNDING_TO_NEAREST) {
                    res.hi = p_sign | 0x7800000000000000; // +/-inf
                    res.lo = 0x0000000000000000;
                    pfpsf.formUnion([.inexact, .overflow])
                } else {
                    res.hi = p_sign | res.hi;
                    bid_rounding_correction (rnd_mode,
                                             is_inexact_lt_midpoint,
                                             is_inexact_gt_midpoint,
                                             is_midpoint_lt_even, is_midpoint_gt_even,
                                             e4, &res, &pfpsf);
                }
                pfpsf.formUnion(save_fpsf)
                //                ptr_is_midpoint_lt_even = is_midpoint_lt_even;
                //                ptr_is_midpoint_gt_even = is_midpoint_gt_even;
                //                ptr_is_inexact_lt_midpoint = is_inexact_lt_midpoint;
                //                ptr_is_inexact_gt_midpoint = is_inexact_gt_midpoint;
                BID_SWAP128(&res)
                return res
            }
            // check for underflow
            if (q4 + e4 < expmin + p34) {
                is_tiny = true // the result is tiny
                // (good also for most cases if 'before rounding')
                if (e4 < expmin) {
                    // if e4 < expmin, we must truncate more of res
                    x0 = expmin - e4; // x0 >= 1
                    is_inexact_lt_midpoint0 = is_inexact_lt_midpoint;
                    is_inexact_gt_midpoint0 = is_inexact_gt_midpoint;
                    is_midpoint_lt_even0 = is_midpoint_lt_even;
                    is_midpoint_gt_even0 = is_midpoint_gt_even;
                    is_inexact_lt_midpoint = false
                    is_inexact_gt_midpoint = false
                    is_midpoint_lt_even = false
                    is_midpoint_gt_even = false
                    // the number of decimal digits in res is q4
                    if (x0 < q4) { // 1 <= x0 <= q4-1 => round res to q4 - x0 digits
                        if (q4 <= 18) { // 2 <= q4 <= 18, 1 <= x0 <= 17
                            bid_round64_2_18 (q4, x0, res.lo, &R64, &incr_exp,
                                              &is_midpoint_lt_even, &is_midpoint_gt_even,
                                              &is_inexact_lt_midpoint,
                                              &is_inexact_gt_midpoint);
                            if incr_exp != 0 {
                                // R64 = 10^(q4-x0), 1 <= q4 - x0 <= q4 - 1, 1 <= q4 - x0 <= 17
                                R64 = bid_ten2k64[q4 - x0];
                            }
                            // res.hi = 0; (from above)
                            res.lo = R64;
                        } else { // if (q4 <= 34)
                            // 19 <= q4 <= 38
                            P128.hi = res.hi;
                            P128.lo = res.lo;
                            bid_round128_19_38 (q4, x0, P128, &res, &incr_exp,
                                                &is_midpoint_lt_even, &is_midpoint_gt_even,
                                                &is_inexact_lt_midpoint,
                                                &is_inexact_gt_midpoint);
                            if incr_exp != 0 {
                                // increase coefficient by a factor of 10; this will be <= 10^33
                                // R128 = 10^(q4-x0), 1 <= q4 - x0 <= q4 - 1, 1 <= q4 - x0 <= 37
                                if (q4 - x0 <= 19) { // 1 <= q4 - x0 <= 19
                                    // res.hi = 0;
                                    res.lo = bid_ten2k64[q4 - x0];
                                } else { // 20 <= q4 - x0 <= 37
                                    res.lo = bid_ten2k128[q4 - x0 - 20].lo;
                                    res.hi = bid_ten2k128[q4 - x0 - 20].hi;
                                }
                            }
                        }
                        e4 = e4 + x0; // expmin
                    } else if (x0 == q4) {
                        // the second rounding is for 0.d(0)d(1)...d(q4-1) * 10^emin
                        // determine relationship with 1/2 ulp
                        if (q4 <= 19) {
                            if (res.lo < bid_midpoint64[q4 - 1]) { // < 1/2 ulp
                                lt_half_ulp = true
                                is_inexact_lt_midpoint = true
                            } else if (res.lo == bid_midpoint64[q4 - 1]) { // = 1/2 ulp
                                eq_half_ulp = true
                                is_midpoint_gt_even = true
                            } else { // > 1/2 ulp
                                // gt_half_ulp = true
                                is_inexact_gt_midpoint = true
                            }
                        } else { // if (q4 <= 34)
                            if (res.hi < bid_midpoint128[q4 - 20].hi ||
                                (res.hi == bid_midpoint128[q4 - 20].hi &&
                                 res.lo < bid_midpoint128[q4 - 20].lo)) { // < 1/2 ulp
                                lt_half_ulp = true
                                is_inexact_lt_midpoint = true
                            } else if (res.hi == bid_midpoint128[q4 - 20].hi &&
                                       res.lo == bid_midpoint128[q4 - 20].lo) { // = 1/2 ulp
                                eq_half_ulp = true
                                is_midpoint_gt_even = true
                            } else { // > 1/2 ulp
                                // gt_half_ulp = true
                                is_inexact_gt_midpoint = true
                            }
                        }
                        if (lt_half_ulp || eq_half_ulp) {
                            // res = +0.0 * 10^expmin
                            res.hi = 0x0000000000000000;
                            res.lo = 0x0000000000000000;
                        } else { // if (gt_half_ulp)
                            // res = +1 * 10^expmin
                            res.hi = 0x0000000000000000;
                            res.lo = 0x0000000000000001;
                        }
                        e4 = expmin;
                    } else { // if (x0 > q4)
                        // the second rounding is for 0.0...d(0)d(1)...d(q4-1) * 10^emin
                        res.hi = 0;
                        res.lo = 0;
                        e4 = expmin;
                        is_inexact_lt_midpoint = true
                    }
                    // avoid a double rounding error
                    if ((is_inexact_gt_midpoint0 || is_midpoint_lt_even0) &&
                        is_midpoint_lt_even) { // double rounding error upward
                        // res = res - 1
                        res.lo-=1
                        if (res.lo == 0xffffffffffffffff) {
                            res.hi-=1
                        }
                        // Note: a double rounding error upward is not possible; for this
                        // the result after the first rounding would have to be 99...95
                        // (35 digits in all), possibly followed by a number of zeros; this
                        // not possible for f * f + 0
                        is_midpoint_lt_even = false
                        is_inexact_lt_midpoint = true
                    } else if ((is_inexact_lt_midpoint0 || is_midpoint_gt_even0) &&
                               is_midpoint_gt_even) { // double rounding error downward
                        // res = res + 1
                        res.lo+=1
                        if (res.lo == 0) {
                            res.hi+=1
                        }
                        is_midpoint_gt_even = false
                        is_inexact_gt_midpoint = true
                    } else if (!is_midpoint_lt_even && !is_midpoint_gt_even &&
                               !is_inexact_lt_midpoint && !is_inexact_gt_midpoint) {
                        // if this second rounding was exact the result may still be
                        // inexact because of the first rounding
                        if (is_inexact_gt_midpoint0 || is_midpoint_lt_even0) {
                            is_inexact_gt_midpoint = true
                        }
                        if (is_inexact_lt_midpoint0 || is_midpoint_gt_even0) {
                            is_inexact_lt_midpoint = true
                        }
                    } else if (is_midpoint_gt_even &&
                               (is_inexact_gt_midpoint0 || is_midpoint_lt_even0)) {
                        // pulled up to a midpoint
                        is_inexact_lt_midpoint = true
                        is_inexact_gt_midpoint = false
                        is_midpoint_lt_even = false
                        is_midpoint_gt_even = false
                    } else if (is_midpoint_lt_even &&
                               (is_inexact_lt_midpoint0 || is_midpoint_gt_even0)) {
                        // pulled down to a midpoint
                        is_inexact_lt_midpoint = false
                        is_inexact_gt_midpoint = true
                        is_midpoint_lt_even = false
                        is_midpoint_gt_even = false
                    } else {
                        // nothing
                    }
                } else { // if e4 >= emin then q4 < P and the result is tiny and exact
                    if (e3 < e4) {
                        // if (e3 < e4) the preferred exponent is e3
                        // return (C4 * 10^scale) * 10^(e4 - scale)
                        // where scale = min (p34-q4, (e4 - e3))
                        scale = p34 - q4;
                        ind = e4 - e3;
                        if (ind < scale) {
                            scale = ind
                        }
                        if (scale == 0) {
                            // res and e4 are unchanged
                        } else if (q4 <= 19) { // C4 fits in 64 bits
                            if (scale <= 19) { // 10^scale fits in 64 bits
                                // 64 x 64 res.lo * bid_ten2k64[scale]
                                __mul_64x64_to_128MACH(&res, res.lo, bid_ten2k64[scale]);
                            } else { // 10^scale fits in 128 bits
                                // 64 x 128 res.lo * bid_ten2k128[scale - 20]
                                __mul_128x64_to_128(&res, res.lo, bid_ten2k128[scale - 20]);
                            }
                        } else { // res fits in 128 bits, but 10^scale must fit in 64 bits
                            // 64 x 128 bid_ten2k64[scale] * C3
                            __mul_128x64_to_128(&res, bid_ten2k64[scale], res);
                        }
                        // subtract scale from the exponent
                        e4 = e4 - scale;
                    }
                }
                
                // check for inexact result
                if (is_inexact_lt_midpoint || is_inexact_gt_midpoint ||
                    is_midpoint_lt_even || is_midpoint_gt_even) {
                    // set the inexact flag and the underflow flag
                    pfpsf.insert(.inexact)
                    pfpsf.insert(.underflow)
                }
                res.hi = p_sign | (UInt64(e4 + 6176) << 49) | res.hi;
                if (rnd_mode != BID_ROUNDING_TO_NEAREST) {
                    bid_rounding_correction (rnd_mode,
                                             is_inexact_lt_midpoint,
                                             is_inexact_gt_midpoint,
                                             is_midpoint_lt_even, is_midpoint_gt_even,
                                             e4, &res, &pfpsf);
                }
                pfpsf.formUnion(save_fpsf)
                //                ptr_is_midpoint_lt_even = is_midpoint_lt_even;
                //                ptr_is_midpoint_gt_even = is_midpoint_gt_even;
                //                ptr_is_inexact_lt_midpoint = is_inexact_lt_midpoint;
                //                ptr_is_inexact_gt_midpoint = is_inexact_gt_midpoint;
                BID_SWAP128(&res)
                return res
            }
            // no overflow, and no underflow for rounding to nearest
            // (although if tininess is detected 'before rounding', we may
            // get here if incr_exp = 1 and then q4 + e4 == expmin + p34)
            res.hi = p_sign | (UInt64(e4 + 6176) << 49) | res.hi;
            
            if (rnd_mode != BID_ROUNDING_TO_NEAREST) {
                bid_rounding_correction (rnd_mode,
                                         is_inexact_lt_midpoint,
                                         is_inexact_gt_midpoint,
                                         is_midpoint_lt_even, is_midpoint_gt_even,
                                         e4, &res, &pfpsf);
                // if e4 = expmin && significand < 10^33 => result is tiny (for RD, RZ)
                if (e4 == expmin) {
                    if ((res.hi & MASK_COEFF) < 0x0000314dc6448d93 ||
                        ((res.hi & MASK_COEFF) == 0x0000314dc6448d93 &&
                         res.lo < 0x38c15b0a00000000)) {
                        is_tiny = true
                    }
                }
            }
            
            if (is_inexact_lt_midpoint || is_inexact_gt_midpoint ||
                is_midpoint_lt_even || is_midpoint_gt_even) {
                // set the inexact flag
                pfpsf.insert(.inexact)
                if (is_tiny) {
                    pfpsf.insert(.underflow)
                }
            }
            
            if !pfpsf.contains(.inexact) { // x * y is exact
                // need to ensure that the result has the preferred exponent
                p_exp = Int(res.hi & MASK_EXP)
                if (z_exp < p_exp) { // the preferred exponent is z_exp
                    // signficand of res in C3
                    C3.hi = res.hi & MASK_COEFF;
                    C3.lo = res.lo;
                    // the number of decimal digits of x * y is q4 <= 34
                    // Note: the coefficient fits in 128 bits
                    
                    // return (C3 * 10^scale) * 10^(p_exp - scale)
                    // where scale = min (p34-q4, (p_exp-z_exp) >> 49)
                    scale = p34 - q4;
                    ind = (p_exp - z_exp) >> 49;
                    if (ind < scale) {
                        scale = ind
                    }
                    // subtract scale from the exponent
                    p_exp = p_exp - Int(UInt64(scale << 49))
                    if (scale == 0) {
                        // leave res unchanged
                    } else if (q4 <= 19) { // x * y fits in 64 bits
                        if (scale <= 19) { // 10^scale fits in 64 bits
                            // 64 x 64 C3.lo * bid_ten2k64[scale]
                            __mul_64x64_to_128MACH(&res, C3.lo, bid_ten2k64[scale]);
                        } else { // 10^scale fits in 128 bits
                            // 64 x 128 C3.lo * bid_ten2k128[scale - 20]
                            __mul_128x64_to_128(&res, C3.lo, bid_ten2k128[scale - 20]);
                        }
                        res.hi = p_sign | (UInt64(p_exp) & MASK_EXP) | res.hi;
                    } else { // x * y fits in 128 bits, but 10^scale must fit in 64 bits
                        // 64 x 128 bid_ten2k64[scale] * C3
                        __mul_128x64_to_128(&res, bid_ten2k64[scale], C3);
                        res.hi = p_sign | (UInt64(p_exp) & MASK_EXP) | res.hi;
                    }
                } // else leave the result as it is, because p_exp <= z_exp
            }
            pfpsf .formUnion(save_fpsf)
            //            ptr_is_midpoint_lt_even = is_midpoint_lt_even;
            //            ptr_is_midpoint_gt_even = is_midpoint_gt_even;
            //            ptr_is_inexact_lt_midpoint = is_inexact_lt_midpoint;
            //            ptr_is_inexact_gt_midpoint = is_inexact_gt_midpoint;
            BID_SWAP128(&res)
            return res
        } // else we have f * f + f
        
        // continue with x = f, y = f, z = f
        
        delta = q3 + e3 - q4 - e4;
        //    delta_ge_zero:
        while true {
            if (delta >= 0) {
                if (p34 <= delta - 1 ||    // Case (1')
                    (p34 == delta && e3 + 6176 < p34 - q3)) { // Case (1''A)
                    // check for overflow, which can occur only in Case (1')
                    if ((q3 + e3) > (p34 + expmax) && p34 <= delta - 1) {
                        // e3 > expmax implies p34 <= delta-1 and e3 > expmax is a necessary
                        // condition for (q3 + e3) > (p34 + expmax)
                        if (rnd_mode == BID_ROUNDING_TO_NEAREST) {
                            res.hi = z_sign | 0x7800000000000000; // +/-inf
                            res.lo = 0x0000000000000000;
                            pfpsf.formUnion([.inexact, .overflow])
                        } else {
                            if (p_sign == z_sign) {
                                is_inexact_lt_midpoint = true
                            } else {
                                is_inexact_gt_midpoint = true
                            }
                            // q3 <= p34; if (q3 < p34) scale C3 up by 10^(p34-q3)
                            scale = p34 - q3;
                            if (scale == 0) {
                                res.hi = z_sign | C3.hi;
                                res.lo = C3.lo;
                            } else {
                                if (q3 <= 19) { // C3 fits in 64 bits
                                    if (scale <= 19) { // 10^scale fits in 64 bits
                                        // 64 x 64 C3.lo * bid_ten2k64[scale]
                                        __mul_64x64_to_128MACH(&res, C3.lo, bid_ten2k64[scale]);
                                    } else { // 10^scale fits in 128 bits
                                        // 64 x 128 C3.lo * bid_ten2k128[scale - 20]
                                        __mul_128x64_to_128(&res, C3.lo,
                                                            bid_ten2k128[scale - 20]);
                                    }
                                } else { // C3 fits in 128 bits, but 10^scale must fit in 64 bits
                                    // 64 x 128 bid_ten2k64[scale] * C3
                                    __mul_128x64_to_128(&res, bid_ten2k64[scale], C3);
                                }
                                // the coefficient in res has q3 + scale = p34 digits
                            }
                            e3 = e3 - scale;
                            res.hi = z_sign | res.hi;
                            bid_rounding_correction (rnd_mode,
                                                     is_inexact_lt_midpoint,
                                                     is_inexact_gt_midpoint,
                                                     is_midpoint_lt_even, is_midpoint_gt_even,
                                                     e3, &res, &pfpsf);
                        }
                        //                    ptr_is_midpoint_lt_even = is_midpoint_lt_even;
                        //                    ptr_is_midpoint_gt_even = is_midpoint_gt_even;
                        //                    ptr_is_inexact_lt_midpoint = is_inexact_lt_midpoint;
                        //                    ptr_is_inexact_gt_midpoint = is_inexact_gt_midpoint;
                        BID_SWAP128(&res)
                        return res
                    }
                    // res = z
                    if (q3 < p34) { // the preferred exponent is z_exp - (p34 - q3)
                        // return (C3 * 10^scale) * 10^(z_exp - scale)
                        // where scale = min (p34-q3, z_exp-EMIN)
                        scale = p34 - q3;
                        ind = e3 + 6176;
                        if (ind < scale) {
                            scale = ind;
                        }
                        if (scale == 0) {
                            res.hi = C3.hi;
                            res.lo = C3.lo;
                        } else if (q3 <= 19) { // z fits in 64 bits
                            if (scale <= 19) { // 10^scale fits in 64 bits
                                // 64 x 64 C3.lo * bid_ten2k64[scale]
                                __mul_64x64_to_128MACH(&res, C3.lo, bid_ten2k64[scale]);
                            } else { // 10^scale fits in 128 bits
                                // 64 x 128 C3.lo * bid_ten2k128[scale - 20]
                                __mul_128x64_to_128(&res, C3.lo, bid_ten2k128[scale - 20]);
                            }
                        } else { // z fits in 128 bits, but 10^scale must fit in 64 bits
                            // 64 x 128 bid_ten2k64[scale] * C3
                            __mul_128x64_to_128(&res, bid_ten2k64[scale], C3);
                        }
                        // the coefficient in res has q3 + scale digits
                        // subtract scale from the exponent
                        z_exp = z_exp - Int(scale << 49)
                        e3 = e3 - scale;
                        res.hi = z_sign | (UInt64(z_exp) & MASK_EXP) | res.hi;
                        if (scale + q3 < p34) {
                            pfpsf.insert(.underflow) // OK for tininess detection
                        }
                        // before or after rounding, because the exponent of the
                        // rounded result with unbounded exponent does not change
                        // due to rounding overflow
                    } else { // if q3 = p34
                        scale = 0;
                        res.hi = z_sign | (UInt64(e3 + 6176) << 49) | C3.hi;
                        res.lo = C3.lo;
                    }
                    
                    // use the following to avoid double rounding errors when operating on
                    // mixed formats in rounding to nearest, and for correcting the result
                    // if not rounding to nearest
                    if ((p_sign != z_sign) && (delta == (q3 + scale + 1))) {
                        // there is a gap of exactly one digit between the scaled C3 and C4
                        // C3 * 10^ scale = 10^(q3+scale-1) <=> C3 = 10^(q3-1) is a special case
                        if ((q3 <= 19 && C3.lo != bid_ten2k64[q3 - 1]) ||
                            (q3 == 20 && (C3.hi != 0 || C3.lo != bid_ten2k64[19])) ||
                            (q3 >= 21 && (C3.hi != bid_ten2k128[q3 - 21].hi ||
                                          C3.lo != bid_ten2k128[q3 - 21].lo))) {
                            // C3 * 10^ scale != 10^(q3-1)
                            // if ((res.hi & MASK_COEFF) != 0x0000314dc6448d93 ||
                            // res.lo != 0x38c15b0a00000000) { // C3 * 10^scale != 10^33
                            is_inexact_gt_midpoint = true // if (z_sign), set as if for abs. value
                        } else { // if C3 * 10^scale = 10^(q3+scale-1)
                            // ok from above e3 = (z_exp >> 49) - 6176;
                            // the result is always inexact
                            if (q4 == 1) {
                                R64 = C4.w[0];
                            } else {
                                // if q4 > 1 then truncate C4 from q4 digits to 1 digit;
                                // x = q4-1, 1 <= x <= 67 and check if this operation is exact
                                if (q4 <= 18) { // 2 <= q4 <= 18
                                    bid_round64_2_18 (q4, q4 - 1, C4.w[0], &R64, &incr_exp,
                                                      &is_midpoint_lt_even, &is_midpoint_gt_even,
                                                      &is_inexact_lt_midpoint,
                                                      &is_inexact_gt_midpoint);
                                } else if (q4 <= 38) {
                                    P128.hi = C4.w[1];
                                    P128.lo = C4.w[0];
                                    bid_round128_19_38 (q4, q4 - 1, P128, &R128, &incr_exp,
                                                        &is_midpoint_lt_even,
                                                        &is_midpoint_gt_even,
                                                        &is_inexact_lt_midpoint,
                                                        &is_inexact_gt_midpoint);
                                    R64 = R128.lo; // one decimal digit
                                } else if (q4 <= 57) {
                                    P192.w[2] = C4.w[2];
                                    P192.w[1] = C4.w[1];
                                    P192.w[0] = C4.w[0];
                                    bid_round192_39_57 (q4, q4 - 1, P192, &R192, &incr_exp,
                                                        &is_midpoint_lt_even,
                                                        &is_midpoint_gt_even,
                                                        &is_inexact_lt_midpoint,
                                                        &is_inexact_gt_midpoint);
                                    R64 = R192.w[0]; // one decimal digit
                                } else { // if (q4 <= 68)
                                    bid_round256_58_76 (q4, q4 - 1, C4, &R256, &incr_exp,
                                                        &is_midpoint_lt_even,
                                                        &is_midpoint_gt_even,
                                                        &is_inexact_lt_midpoint,
                                                        &is_inexact_gt_midpoint);
                                    R64 = R256.w[0]; // one decimal digit
                                }
                                if incr_exp != 0 {
                                    R64 = 10;
                                }
                            }
                            if (R64 == 5 && !is_inexact_lt_midpoint && !is_inexact_gt_midpoint &&
                                !is_midpoint_lt_even && !is_midpoint_gt_even) {
                                is_inexact_lt_midpoint = false
                                is_inexact_gt_midpoint = false
                                is_midpoint_lt_even = true
                                is_midpoint_gt_even = false
                            } else if ((e3 == expmin) ||
                                       R64 < 5 || (R64 == 5 && is_inexact_gt_midpoint)) {
                                // result does not change
                                is_inexact_lt_midpoint = false
                                is_inexact_gt_midpoint = true
                                is_midpoint_lt_even = false
                                is_midpoint_gt_even = false
                            } else {
                                is_inexact_lt_midpoint = true
                                is_inexact_gt_midpoint = false
                                is_midpoint_lt_even = false
                                is_midpoint_gt_even = false
                                // result decremented is 10^(q3+scale) - 1
                                if ((q3 + scale) <= 19) {
                                    res.hi = 0;
                                    res.lo = bid_ten2k64[q3 + scale];
                                } else { // if ((q3 + scale + 1) <= 35)
                                    res.hi = bid_ten2k128[q3 + scale - 20].hi;
                                    res.lo = bid_ten2k128[q3 + scale - 20].lo;
                                }
                                res.lo = res.lo - 1; // borrow never occurs
                                z_exp = z_exp - Int(EXP_P1)
                                e3 = e3 - 1;
                                res.hi = z_sign | (UInt64(e3 + 6176) << 49) | res.hi;
                            }
                            if (e3 == expmin) {
                                if (R64 < 5 || (R64 == 5 && !is_inexact_lt_midpoint)) {
                                    // result not tiny (in round-to-nearest mode)
                                    // rounds to 10^33 * 10^emin
                                } else {
                                    pfpsf.insert(.underflow)
                                }
                            }
                        } // end 10^(q3+scale-1)
                        // set the inexact flag
                        pfpsf.insert(.inexact)
                    } else {
                        if (p_sign == z_sign) {
                            // if (z_sign), set as if for absolute value
                            is_inexact_lt_midpoint = true
                        } else { // if (p_sign != z_sign)
                            // if (z_sign), set as if for absolute value
                            is_inexact_gt_midpoint = true
                        }
                        pfpsf.insert(.inexact)
                    }
                    // the result is always inexact => set the inexact flag
                    // Determine tininess:
                    //    if (exp > expmin)
                    //      the result is not tiny
                    //    else // if exp = emin
                    //      if (q3 + scale < p34)
                    //        the result is tiny
                    //      else // if (q3 + scale = p34)
                    //        if (C3 * 10^scale > 10^33)
                    //          the result is not tiny
                    //        else // if C3 * 10^scale = 10^33
                    //          if (xy * z > 0)
                    //            the result is not tiny
                    //          else // if (xy * z < 0)
                    //            if (rnd_mode = RN || rnd_mode = RA) and (delta = P+1) and
                    //                C4 > 5 * 10^(q4-1)
                    //              the result is tiny
                    //            else
                    //              the result is not tiny
                    //          endif
                    //        endif
                    //      endif
                    //    endif
                    
                    // determine if C4 > 5 * 10^(q4-1)
                    if (q4 <= 19) {
                        C4gt5toq4m1 =
                        C4.w[0] > bid_midpoint64[q4 - 1];
                    } else if (q4 <= 38) {
                        C4gt5toq4m1 =
                        C4.w[1] > bid_midpoint128[q4 - 1].hi ||
                        (C4.w[1] == bid_midpoint128[q4 - 1].hi &&
                         C4.w[0] > bid_midpoint128[q4 - 1].lo);
                    } else if (q4 <= 58) {
                        C4gt5toq4m1 =
                        C4.w[2] > bid_midpoint192[q4 - 1].w[2] ||
                        (C4.w[2] == bid_midpoint192[q4 - 1].w[2] &&
                         C4.w[1] > bid_midpoint192[q4 - 1].w[1]) ||
                        (C4.w[2] == bid_midpoint192[q4 - 1].w[2] &&
                         C4.w[1] == bid_midpoint192[q4 - 1].w[1] &&
                         C4.w[0] > bid_midpoint192[q4 - 1].w[0]);
                    } else { // if (q4 <= 68)
                        C4gt5toq4m1 =
                        C4.w[3] > bid_midpoint256[q4 - 1].w[3] ||
                        (C4.w[3] == bid_midpoint256[q4 - 1].w[3] &&
                         C4.w[2] > bid_midpoint256[q4 - 1].w[2]) ||
                        (C4.w[3] == bid_midpoint256[q4 - 1].w[3] &&
                         C4.w[2] == bid_midpoint256[q4 - 1].w[2] &&
                         C4.w[1] > bid_midpoint256[q4 - 1].w[1]) ||
                        (C4.w[3] == bid_midpoint256[q4 - 1].w[3] &&
                         C4.w[2] == bid_midpoint256[q4 - 1].w[2] &&
                         C4.w[1] == bid_midpoint256[q4 - 1].w[1] &&
                         C4.w[0] > bid_midpoint256[q4 - 1].w[0]);
                    }
                    
                    if ((e3 == expmin && (q3 + scale) < p34) ||
                        (e3 == expmin && (q3 + scale) == p34 &&
                         (res.hi & MASK_COEFF) == 0x0000314dc6448d93 &&    // 10^33_high
                         res.lo == 0x38c15b0a00000000 &&    // 10^33_low
                         z_sign != p_sign &&
                         (rnd_mode == BID_ROUNDING_TO_NEAREST || rnd_mode == BID_ROUNDING_TIES_AWAY) &&
                         (delta == (p34 + 1)) && C4gt5toq4m1)) {
                        pfpsf.insert(.underflow)
                    }
                    if (rnd_mode != BID_ROUNDING_TO_NEAREST) {
                        bid_rounding_correction (rnd_mode,
                                                 is_inexact_lt_midpoint,
                                                 is_inexact_gt_midpoint,
                                                 is_midpoint_lt_even, is_midpoint_gt_even,
                                                 e3, &res, &pfpsf);
                    }
                    //                ptr_is_midpoint_lt_even = is_midpoint_lt_even;
                    //                ptr_is_midpoint_gt_even = is_midpoint_gt_even;
                    //                ptr_is_inexact_lt_midpoint = is_inexact_lt_midpoint;
                    //                ptr_is_inexact_gt_midpoint = is_inexact_gt_midpoint;
                    BID_SWAP128(&res)
                    return res
                    
                } else if (p34 == delta) { // Case (1''B)
                    
                    // because Case (1''A) was treated above, e3 + 6176 >= p34 - q3
                    // and C3 can be scaled up to p34 digits if needed
                    
                    // scale C3 to p34 digits if needed
                    scale = p34 - q3; // 0 <= scale <= p34 - 1
                    if (scale == 0) {
                        res.hi = C3.hi;
                        res.lo = C3.lo;
                    } else if (q3 <= 19) { // z fits in 64 bits
                        if (scale <= 19) { // 10^scale fits in 64 bits
                            // 64 x 64 C3.lo * bid_ten2k64[scale]
                            __mul_64x64_to_128MACH(&res, C3.lo, bid_ten2k64[scale]);
                        } else { // 10^scale fits in 128 bits
                            // 64 x 128 C3.lo * bid_ten2k128[scale - 20]
                            __mul_128x64_to_128(&res, C3.lo, bid_ten2k128[scale - 20]);
                        }
                    } else { // z fits in 128 bits, but 10^scale must fit in 64 bits
                        // 64 x 128 bid_ten2k64[scale] * C3
                        __mul_128x64_to_128(&res, bid_ten2k64[scale], C3);
                    }
                    // subtract scale from the exponent
                    z_exp = z_exp - Int(scale << 49);
                    e3 = e3 - scale;
                    // now z_sign, z_exp, and res correspond to a z scaled to p34 = 34 digits
                    
                    // determine whether x * y is less than, equal to, or greater than
                    // 1/2 ulp (z)
                    if (q4 <= 19) {
                        if (C4.w[0] < bid_midpoint64[q4 - 1]) { // < 1/2 ulp
                            lt_half_ulp = true
                        } else if (C4.w[0] == bid_midpoint64[q4 - 1]) { // = 1/2 ulp
                            eq_half_ulp = true
                        } else { // > 1/2 ulp
                            gt_half_ulp = true
                        }
                    } else if (q4 <= 38) {
                        if (C4.w[2] == 0 && (C4.w[1] < bid_midpoint128[q4 - 20].hi ||
                                             (C4.w[1] == bid_midpoint128[q4 - 20].hi &&
                                              C4.w[0] < bid_midpoint128[q4 - 20].lo))) { // < 1/2 ulp
                            lt_half_ulp = true
                        } else if (C4.w[2] == 0 && C4.w[1] == bid_midpoint128[q4 - 20].hi &&
                                   C4.w[0] == bid_midpoint128[q4 - 20].lo) { // = 1/2 ulp
                            eq_half_ulp = true
                        } else { // > 1/2 ulp
                            gt_half_ulp = true
                        }
                    } else if (q4 <= 58) {
                        if (C4.w[3] == 0 && (C4.w[2] < bid_midpoint192[q4 - 39].w[2] ||
                                             (C4.w[2] == bid_midpoint192[q4 - 39].w[2] &&
                                              C4.w[1] < bid_midpoint192[q4 - 39].w[1]) ||
                                             (C4.w[2] == bid_midpoint192[q4 - 39].w[2] &&
                                              C4.w[1] == bid_midpoint192[q4 - 39].w[1] &&
                                              C4.w[0] < bid_midpoint192[q4 - 39].w[0]))) { // < 1/2 ulp
                            lt_half_ulp = true
                        } else if (C4.w[3] == 0 && C4.w[2] == bid_midpoint192[q4 - 39].w[2] &&
                                   C4.w[1] == bid_midpoint192[q4 - 39].w[1] &&
                                   C4.w[0] == bid_midpoint192[q4 - 39].w[0]) { // = 1/2 ulp
                            eq_half_ulp = true
                        } else { // > 1/2 ulp
                            gt_half_ulp = true
                        }
                    } else {
                        if (C4.w[3] < bid_midpoint256[q4 - 59].w[3] ||
                            (C4.w[3] == bid_midpoint256[q4 - 59].w[3] &&
                             C4.w[2] < bid_midpoint256[q4 - 59].w[2]) ||
                            (C4.w[3] == bid_midpoint256[q4 - 59].w[3] &&
                             C4.w[2] == bid_midpoint256[q4 - 59].w[2] &&
                             C4.w[1] < bid_midpoint256[q4 - 59].w[1]) ||
                            (C4.w[3] == bid_midpoint256[q4 - 59].w[3] &&
                             C4.w[2] == bid_midpoint256[q4 - 59].w[2] &&
                             C4.w[1] == bid_midpoint256[q4 - 59].w[1] &&
                             C4.w[0] < bid_midpoint256[q4 - 59].w[0])) { // < 1/2 ulp
                            lt_half_ulp = true
                        } else if (C4.w[3] == bid_midpoint256[q4 - 59].w[3] &&
                                   C4.w[2] == bid_midpoint256[q4 - 59].w[2] &&
                                   C4.w[1] == bid_midpoint256[q4 - 59].w[1] &&
                                   C4.w[0] == bid_midpoint256[q4 - 59].w[0]) { // = 1/2 ulp
                            eq_half_ulp = true
                        } else { // > 1/2 ulp
                            gt_half_ulp = true
                        }
                    }
                    
                    if (p_sign == z_sign) {
                        if (lt_half_ulp) {
                            res.hi = z_sign | (UInt64(z_exp) & MASK_EXP) | res.hi;
                            // use the following to avoid double rounding errors when operating on
                            // mixed formats in rounding to nearest
                            is_inexact_lt_midpoint = true // if (z_sign), as if for absolute value
                        } else if ((eq_half_ulp && (res.lo & 0x01 != 0)) || gt_half_ulp) {
                            // add 1 ulp to the significand
                            res.lo &+= 1
                            if res.lo == 0x0 { res.hi+=1 }
                            
                            // check for rounding overflow, when coeff == 10^34
                            if ((res.hi & MASK_COEFF) == 0x0001ed09bead87c0 && res.lo == 0x378d8e6400000000) { // coefficient = 10^34
                                e3 = e3 + 1;
                                // coeff = 10^33
                                z_exp = Int((UInt64(e3 + 6176) << 49) & MASK_EXP)
                                res.hi = 0x0000314dc6448d93;
                                res.lo = 0x38c15b0a00000000;
                            }
                            // end add 1 ulp
                            res.hi = z_sign | (UInt64(z_exp) & MASK_EXP) | res.hi
                            if (eq_half_ulp) {
                                is_midpoint_lt_even = true // if (z_sign), as if for absolute value
                            } else {
                                is_inexact_gt_midpoint = true // if (z_sign), as if for absolute value
                            }
                        } else { // if (eq_half_ulp && !(res.lo & 0x01))
                            // leave unchanged
                            res.hi = z_sign | (UInt64(z_exp) & MASK_EXP) | res.hi;
                            is_midpoint_gt_even = true // if (z_sign), as if for absolute value
                        }
                        // the result is always inexact, and never tiny
                        // set the inexact flag
                        pfpsf.insert(.inexact)
                        // check for overflow
                        if (e3 > expmax && rnd_mode == BID_ROUNDING_TO_NEAREST) {
                            res.hi = z_sign | 0x7800000000000000; // +/-inf
                            res.lo = 0x0000000000000000;
                            pfpsf.formUnion([.inexact, .overflow])
                            //                        ptr_is_midpoint_lt_even = is_midpoint_lt_even;
                            //                        ptr_is_midpoint_gt_even = is_midpoint_gt_even;
                            //                        ptr_is_inexact_lt_midpoint = is_inexact_lt_midpoint;
                            //                        ptr_is_inexact_gt_midpoint = is_inexact_gt_midpoint;
                            BID_SWAP128(&res)
                            return res
                        }
                        if (rnd_mode != BID_ROUNDING_TO_NEAREST) {
                            bid_rounding_correction (rnd_mode,
                                                     is_inexact_lt_midpoint,
                                                     is_inexact_gt_midpoint,
                                                     is_midpoint_lt_even, is_midpoint_gt_even,
                                                     e3, &res, &pfpsf);
                            z_exp = Int(res.hi & MASK_EXP)
                        }
                    } else { // if (p_sign != z_sign)
                        // consider two cases, because C3 * 10^scale = 10^33 is a special case
                        if (res.hi != 0x0000314dc6448d93 ||
                            res.lo != 0x38c15b0a00000000) { // C3 * 10^scale != 10^33
                            if (lt_half_ulp) {
                                res.hi = z_sign | (UInt64(z_exp) & MASK_EXP) | res.hi;
                                // use the following to avoid double rounding errors when operating
                                // on mixed formats in rounding to nearest
                                is_inexact_gt_midpoint = true // if (z_sign), as if for absolute value
                            } else if ((eq_half_ulp && (res.lo & 0x01 != 0)) || gt_half_ulp) {
                                // subtract 1 ulp from the significand
                                res.lo-=1
                                if (res.lo == 0xffffffffffffffff) {
                                    res.hi-=1
                                }
                                res.hi = z_sign | (UInt64(z_exp) & MASK_EXP) | res.hi;
                                if (eq_half_ulp) {
                                    is_midpoint_gt_even = true // if (z_sign), as if for absolute value
                                } else {
                                    is_inexact_lt_midpoint = true //if(z_sign), as if for absolute value
                                }
                            } else { // if (eq_half_ulp && !(res.lo & 0x01))
                                // leave unchanged
                                res.hi = z_sign | (UInt64(z_exp) & MASK_EXP) | res.hi;
                                is_midpoint_lt_even = true // if (z_sign), as if for absolute value
                            }
                            // the result is always inexact, and never tiny
                            // check for overflow for RN
                            if (e3 > expmax) {
                                if (rnd_mode == BID_ROUNDING_TO_NEAREST) {
                                    res.hi = z_sign | 0x7800000000000000; // +/-inf
                                    res.lo = 0x0000000000000000;
                                    pfpsf.formUnion([.inexact, .overflow])
                                } else {
                                    bid_rounding_correction (rnd_mode,
                                                             is_inexact_lt_midpoint,
                                                             is_inexact_gt_midpoint,
                                                             is_midpoint_lt_even,
                                                             is_midpoint_gt_even, e3, &res,
                                                             &pfpsf)
                                }
                                //                            ptr_is_midpoint_lt_even = is_midpoint_lt_even;
                                //                            ptr_is_midpoint_gt_even = is_midpoint_gt_even;
                                //                            ptr_is_inexact_lt_midpoint = is_inexact_lt_midpoint;
                                //                            ptr_is_inexact_gt_midpoint = is_inexact_gt_midpoint;
                                BID_SWAP128(&res)
                                return res
                            }
                            // set the inexact flag
                            pfpsf.insert(.inexact)
                            if (rnd_mode != BID_ROUNDING_TO_NEAREST) {
                                bid_rounding_correction (rnd_mode,
                                                         is_inexact_lt_midpoint,
                                                         is_inexact_gt_midpoint,
                                                         is_midpoint_lt_even,
                                                         is_midpoint_gt_even, e3, &res, &pfpsf)
                            }
                            z_exp = Int(res.hi & MASK_EXP)
                        } else { // if C3 * 10^scale = 10^33
                            e3 = (z_exp >> 49) - 6176;
                            if (e3 > expmin) {
                                // the result is exact if exp > expmin and C4 = d*10^(q4-1),
                                // where d = 1, 2, 3, ..., 9; it could be tiny too, but exact
                                if (q4 == 1) {
                                    // if q4 = 1 the result is exact
                                    // result coefficient = 10^34 - C4
                                    res.hi = 0x0001ed09bead87c0;
                                    res.lo = 0x378d8e6400000000 - C4.w[0];
                                    z_exp = z_exp - Int(EXP_P1)
                                    e3 = e3 - 1;
                                    res.hi = z_sign | (UInt64(z_exp) & MASK_EXP) | res.hi;
                                } else {
                                    // if q4 > 1 then truncate C4 from q4 digits to 1 digit;
                                    // x = q4-1, 1 <= x <= 67 and check if this operation is exact
                                    if (q4 <= 18) { // 2 <= q4 <= 18
                                        bid_round64_2_18 (q4, q4 - 1, C4.w[0], &R64, &incr_exp,
                                                          &is_midpoint_lt_even,
                                                          &is_midpoint_gt_even,
                                                          &is_inexact_lt_midpoint,
                                                          &is_inexact_gt_midpoint);
                                    } else if (q4 <= 38) {
                                        P128.hi = C4.w[1];
                                        P128.lo = C4.w[0];
                                        bid_round128_19_38 (q4, q4 - 1, P128, &R128, &incr_exp,
                                                            &is_midpoint_lt_even,
                                                            &is_midpoint_gt_even,
                                                            &is_inexact_lt_midpoint,
                                                            &is_inexact_gt_midpoint);
                                        R64 = R128.lo; // one decimal digit
                                    } else if (q4 <= 57) {
                                        P192.w[2] = C4.w[2];
                                        P192.w[1] = C4.w[1];
                                        P192.w[0] = C4.w[0];
                                        bid_round192_39_57 (q4, q4 - 1, P192, &R192, &incr_exp,
                                                            &is_midpoint_lt_even,
                                                            &is_midpoint_gt_even,
                                                            &is_inexact_lt_midpoint,
                                                            &is_inexact_gt_midpoint);
                                        R64 = R192.w[0]; // one decimal digit
                                    } else { // if (q4 <= 68)
                                        bid_round256_58_76 (q4, q4 - 1, C4, &R256, &incr_exp,
                                                            &is_midpoint_lt_even,
                                                            &is_midpoint_gt_even,
                                                            &is_inexact_lt_midpoint,
                                                            &is_inexact_gt_midpoint);
                                        R64 = R256.w[0]; // one decimal digit
                                    }
                                    if (!is_midpoint_lt_even && !is_midpoint_gt_even &&
                                        !is_inexact_lt_midpoint && !is_inexact_gt_midpoint) {
                                        // the result is exact: 10^34 - R64
                                        // incr_exp = 0 with certainty
                                        z_exp = z_exp - Int(EXP_P1)
                                        e3 = e3 - 1;
                                        res.hi = z_sign | (UInt64(z_exp) & MASK_EXP) | 0x0001ed09bead87c0;
                                        res.lo = 0x378d8e6400000000 - R64;
                                    } else {
                                        // We want R64 to be the top digit of C4, but we actually
                                        // obtained (C4 * 10^(-q4+1))RN; a correction may be needed,
                                        // because the top digit is (C4 * 10^(-q4+1))RZ
                                        // however, if incr_exp = 1 then R64 = 10 with certainty
                                        if incr_exp != 0 {
                                            R64 = 10;
                                        }
                                        // the result is inexact as C4 has more than 1 significant digit
                                        // and C3 * 10^scale = 10^33
                                        // example of case that is treated here:
                                        // 100...0 * 10^e3 - 0.41 * 10^e3 =
                                        // 0999...9.59 * 10^e3 -> rounds to 99...96*10^(e3-1)
                                        // note that (e3 > expmin}
                                        // in order to round, subtract R64 from 10^34 and then compare
                                        // C4 - R64 * 10^(q4-1) with 1/2 ulp
                                        // calculate 10^34 - R64
                                        res.hi = 0x0001ed09bead87c0;
                                        res.lo = 0x378d8e6400000000 - R64;
                                        z_exp = z_exp - Int(EXP_P1) // will be OR-ed with sign & significand
                                        // calculate C4 - R64 * 10^(q4-1); this is a rare case and
                                        // R64 is small, 1 <= R64 <= 9
                                        e3 = e3 - 1;
                                        if (is_inexact_lt_midpoint) {
                                            is_inexact_lt_midpoint = false
                                            is_inexact_gt_midpoint = true
                                        } else if (is_inexact_gt_midpoint) {
                                            is_inexact_gt_midpoint = false
                                            is_inexact_lt_midpoint = true
                                        } else if (is_midpoint_lt_even) {
                                            is_midpoint_lt_even = false
                                            is_midpoint_gt_even = true
                                        } else if (is_midpoint_gt_even) {
                                            is_midpoint_gt_even = false
                                            is_midpoint_lt_even = true
                                        } else {
                                            // nothing
                                        }
                                        // the result is always inexact, and never tiny
                                        // check for overflow for RN
                                        if (e3 > expmax) {
                                            if (rnd_mode == BID_ROUNDING_TO_NEAREST) {
                                                res.hi = z_sign | 0x7800000000000000; // +/-inf
                                                res.lo = 0x0000000000000000;
                                                pfpsf.formUnion([.inexact, .overflow])
                                            } else {
                                                bid_rounding_correction (rnd_mode,
                                                                         is_inexact_lt_midpoint,
                                                                         is_inexact_gt_midpoint,
                                                                         is_midpoint_lt_even,
                                                                         is_midpoint_gt_even, e3, &res,
                                                                         &pfpsf);
                                            }
                                            //                                        ptr_is_midpoint_lt_even = is_midpoint_lt_even;
                                            //                                        ptr_is_midpoint_gt_even = is_midpoint_gt_even;
                                            //                                        ptr_is_inexact_lt_midpoint = is_inexact_lt_midpoint;
                                            //                                        ptr_is_inexact_gt_midpoint = is_inexact_gt_midpoint;
                                            BID_SWAP128(&res)
                                            return res
                                        }
                                        // set the inexact flag
                                        pfpsf.insert(.inexact)
                                        res.hi =
                                        z_sign | (UInt64(e3 + 6176) << 49) | res.hi;
                                        if (rnd_mode != BID_ROUNDING_TO_NEAREST) {
                                            bid_rounding_correction (rnd_mode,
                                                                     is_inexact_lt_midpoint,
                                                                     is_inexact_gt_midpoint,
                                                                     is_midpoint_lt_even,
                                                                     is_midpoint_gt_even, e3, &res,
                                                                     &pfpsf);
                                        }
                                        z_exp = Int(res.hi & MASK_EXP)
                                    } // end result is inexact
                                } // end q4 > 1
                            } else { // if (e3 = emin)
                                // if e3 = expmin the result is also tiny (the condition for
                                // tininess is C4 > 050...0 [q4 digits] which is met because
                                // the msd of C4 is not zero)
                                // the result is tiny and inexact in all rounding modes;
                                // it is either 100...0 or 0999...9 (use lt_half_ulp, eq_half_ulp,
                                // gt_half_ulp to calculate)
                                // if (lt_half_ulp || eq_half_ulp) res = 10^33 stays unchanged
                                
                                // p_sign != z_sign so swap gt_half_ulp and lt_half_ulp
                                if (gt_half_ulp) { // res = 10^33 - 1
                                    res.hi = 0x0000314dc6448d93;
                                    res.lo = 0x38c15b09ffffffff;
                                } else {
                                    res.hi = 0x0000314dc6448d93;
                                    res.lo = 0x38c15b0a00000000;
                                }
                                res.hi = z_sign | (UInt64(z_exp) & MASK_EXP) | res.hi;
                                pfpsf.insert(.underflow) // inexact is set later
                                
                                if (eq_half_ulp) {
                                    is_midpoint_lt_even = true // if (z_sign), as if for absolute value
                                } else if (lt_half_ulp) {
                                    is_inexact_gt_midpoint = true //if(z_sign), as if for absolute value
                                } else { // if (gt_half_ulp)
                                    is_inexact_lt_midpoint = true //if(z_sign), as if for absolute value
                                }
                                
                                if (rnd_mode != BID_ROUNDING_TO_NEAREST) {
                                    bid_rounding_correction (rnd_mode,
                                                             is_inexact_lt_midpoint,
                                                             is_inexact_gt_midpoint,
                                                             is_midpoint_lt_even,
                                                             is_midpoint_gt_even, e3, &res,
                                                             &pfpsf)
                                    z_exp = Int(res.hi & MASK_EXP)
                                }
                            } // end e3 = emin
                            // set the inexact flag (if the result was not exact)
                            if (is_inexact_lt_midpoint || is_inexact_gt_midpoint ||
                                is_midpoint_lt_even || is_midpoint_gt_even) {
                                pfpsf.insert(.inexact)
                            }
                        } // end 10^33
                    } // end if (p_sign != z_sign)
                    res.hi = z_sign | (UInt64(z_exp) & MASK_EXP) | res.hi;
                    //                ptr_is_midpoint_lt_even = is_midpoint_lt_even;
                    //                ptr_is_midpoint_gt_even = is_midpoint_gt_even;
                    //                ptr_is_inexact_lt_midpoint = is_inexact_lt_midpoint;
                    //                ptr_is_inexact_gt_midpoint = is_inexact_gt_midpoint;
                    BID_SWAP128(&res)
                    return res
                    
                } else if (((q3 <= delta && delta < p34 && p34 < delta + q4) || // Case (2)
                            (q3 <= delta && delta + q4 <= p34) || // Case (3)
                            (delta < q3 && p34 < delta + q4) || // Case (4)
                            (delta < q3 && q3 <= delta + q4 && delta + q4 <= p34) || // Case (5)
                            (delta + q4 < q3)) && // Case (6)
                           !(delta <= 1 && p_sign != z_sign)) { // Case (2), (3), (4), (5) or (6)
                    
                    // the result has the sign of z
                    
                    if ((q3 <= delta && delta < p34 && p34 < delta + q4) || // Case (2)
                        (delta < q3 && p34 < delta + q4)) { // Case (4)
                        // round first the sum x * y + z with unbounded exponent
                        // scale C3 up by scale = p34 - q3, 1 <= scale <= p34-1,
                        // 1 <= scale <= 33
                        // calculate res = C3 * 10^scale
                        scale = p34 - q3;
                        x0 = delta + q4 - p34;
                    } else if (delta + q4 < q3) { // Case (6)
                        // make Case (6) look like Case (3) or Case (5) with scale = 0
                        // by scaling up C4 by 10^(q3 - delta - q4)
                        scale = q3 - delta - q4; // 1 <= scale <= 33
                        if (q4 <= 19) { // 1 <= scale <= 19; C4 fits in 64 bits
                            if (scale <= 19) { // 10^scale fits in 64 bits
                                // 64 x 64 C4.w[0] * bid_ten2k64[scale]
                                __mul_64x64_to_128MACH(&P128, C4.w[0], bid_ten2k64[scale]);
                            } else { // 10^scale fits in 128 bits
                                // 64 x 128 C4.w[0] * bid_ten2k128[scale - 20]
                                __mul_128x64_to_128(&P128, C4.w[0], bid_ten2k128[scale - 20]);
                            }
                        } else { // C4 fits in 128 bits, but 10^scale must fit in 64 bits
                            // 64 x 128 bid_ten2k64[scale] * C4
                            C4s.lo = C4.w[0]; C4s.hi = C4.w[1]
                            __mul_128x64_to_128(&P128, bid_ten2k64[scale], C4s)
                        }
                        C4.w[0] = P128.lo
                        C4.w[1] = P128.hi
                        // e4 does not need adjustment, as it is not used from this point on
                        scale = 0;
                        x0 = 0;
                        // now Case (6) looks like Case (3) or Case (5) with scale = 0
                    } else { // if Case (3) or Case (5)
                        // Note: Case (3) is similar to Case (2), but scale differs and the
                        // result is exact, unless it is tiny (so x0 = 0 when calculating the
                        // result with unbounded exponent)
                        
                        // calculate first the sum x * y + z with unbounded exponent (exact)
                        // scale C3 up by scale = delta + q4 - q3, 1 <= scale <= p34-1,
                        // 1 <= scale <= 33
                        // calculate res = C3 * 10^scale
                        scale = delta + q4 - q3;
                        x0 = 0;
                        // Note: the comments which follow refer [mainly] to Case (2)]
                    }
                    
                    // case2_repeat:
                    //    while true {
                    if scale == 0 { // this could happen e.g. if we return to case2_repeat
                        // or in Case (4)
                        res.hi = C3.hi;
                        res.lo = C3.lo;
                    } else if (q3 <= 19) { // 1 <= scale <= 19; z fits in 64 bits
                        if (scale <= 19) { // 10^scale fits in 64 bits
                            // 64 x 64 C3.lo * bid_ten2k64[scale]
                            __mul_64x64_to_128MACH(&res, C3.lo, bid_ten2k64[scale]);
                        } else { // 10^scale fits in 128 bits
                            // 64 x 128 C3.lo * bid_ten2k128[scale - 20]
                            __mul_128x64_to_128(&res, C3.lo, bid_ten2k128[scale - 20]);
                        }
                    } else { // z fits in 128 bits, but 10^scale must fit in 64 bits
                        // 64 x 128 bid_ten2k64[scale] * C3
                        __mul_128x64_to_128(&res, bid_ten2k64[scale], C3);
                    }
                    // e3 is already calculated
                    e3 = e3 - scale;
                    // now res = C3 * 10^scale and e3 = e3 - scale
                    // Note: C3 * 10^scale could be 10^34 if we returned to case2_repeat
                    // because the result was too small
                    
                    // round C4 to nearest to q4 - x0 digits, where x0 = delta + q4 - p34,
                    // 1 <= x0 <= min (q4 - 1, 2 * p34 - 1) <=> 1 <= x0 <= min (q4 - 1, 67)
                    // Also: 1 <= q4 - x0 <= p34 -1 => 1 <= q4 - x0 <= 33 (so the result of
                    // the rounding fits in 128 bits!)
                    // x0 = delta + q4 - p34 (calculated before reaching case2_repeat)
                    // because q3 + q4 - x0 <= P => x0 >= q3 + q4 - p34
                    if (x0 == 0) { // this could happen only if we return to case2_repeat, or
                        // for Case (3) or Case (6)
                        R128.hi = C4.w[1];
                        R128.lo = C4.w[0];
                    } else if (q4 <= 18) {
                        // 2 <= q4 <= 18, max(1, q3+q4-p34) <= x0 <= q4 - 1, 1 <= x0 <= 17
                        bid_round64_2_18 (q4, x0, C4.w[0], &R64, &incr_exp,
                                          &is_midpoint_lt_even, &is_midpoint_gt_even,
                                          &is_inexact_lt_midpoint, &is_inexact_gt_midpoint);
                        if incr_exp != 0 {
                            // R64 = 10^(q4-x0), 1 <= q4 - x0 <= q4 - 1, 1 <= q4 - x0 <= 17
                            R64 = bid_ten2k64[q4 - x0];
                        }
                        R128.hi = 0;
                        R128.lo = R64;
                    } else if (q4 <= 38) {
                        // 19 <= q4 <= 38, max(1, q3+q4-p34) <= x0 <= q4 - 1, 1 <= x0 <= 37
                        P128.hi = C4.w[1];
                        P128.lo = C4.w[0];
                        bid_round128_19_38 (q4, x0, P128, &R128, &incr_exp,
                                            &is_midpoint_lt_even, &is_midpoint_gt_even,
                                            &is_inexact_lt_midpoint,
                                            &is_inexact_gt_midpoint);
                        if incr_exp != 0 {
                            // R128 = 10^(q4-x0), 1 <= q4 - x0 <= q4 - 1, 1 <= q4 - x0 <= 37
                            if (q4 - x0 <= 19) { // 1 <= q4 - x0 <= 19
                                R128.lo = bid_ten2k64[q4 - x0];
                                // R128.hi stays 0
                            } else { // 20 <= q4 - x0 <= 37
                                R128.lo = bid_ten2k128[q4 - x0 - 20].lo;
                                R128.hi = bid_ten2k128[q4 - x0 - 20].hi;
                            }
                        }
                    } else if (q4 <= 57) {
                        // 38 <= q4 <= 57, max(1, q3+q4-p34) <= x0 <= q4 - 1, 5 <= x0 <= 56
                        P192.w[2] = C4.w[2];
                        P192.w[1] = C4.w[1];
                        P192.w[0] = C4.w[0];
                        bid_round192_39_57 (q4, x0, P192, &R192, &incr_exp,
                                            &is_midpoint_lt_even, &is_midpoint_gt_even,
                                            &is_inexact_lt_midpoint,
                                            &is_inexact_gt_midpoint);
                        // R192.w[2] is always 0
                        if incr_exp != 0 {
                            // R192 = 10^(q4-x0), 1 <= q4 - x0 <= q4 - 5, 1 <= q4 - x0 <= 52
                            if (q4 - x0 <= 19) { // 1 <= q4 - x0 <= 19
                                R192.w[0] = bid_ten2k64[q4 - x0];
                                // R192.w[1] stays 0
                                // R192.w[2] stays 0
                            } else { // 20 <= q4 - x0 <= 33
                                R192.w[0] = bid_ten2k128[q4 - x0 - 20].lo;
                                R192.w[1] = bid_ten2k128[q4 - x0 - 20].hi;
                                // R192.w[2] stays 0
                            }
                        }
                        R128.hi = R192.w[1];
                        R128.lo = R192.w[0];
                    } else {
                        // 58 <= q4 <= 68, max(1, q3+q4-p34) <= x0 <= q4 - 1, 25 <= x0 <= 67
                        bid_round256_58_76 (q4, x0, C4, &R256, &incr_exp,
                                            &is_midpoint_lt_even, &is_midpoint_gt_even,
                                            &is_inexact_lt_midpoint,
                                            &is_inexact_gt_midpoint);
                        // R256.w[3] and R256.w[2] are always 0
                        if incr_exp != 0 {
                            // R256 = 10^(q4-x0), 1 <= q4 - x0 <= q4 - 25, 1 <= q4 - x0 <= 43
                            if (q4 - x0 <= 19) { // 1 <= q4 - x0 <= 19
                                R256.w[0] = bid_ten2k64[q4 - x0];
                                // R256.w[1] stays 0
                                // R256.w[2] stays 0
                                // R256.w[3] stays 0
                            } else { // 20 <= q4 - x0 <= 33
                                R256.w[0] = bid_ten2k128[q4 - x0 - 20].lo;
                                R256.w[1] = bid_ten2k128[q4 - x0 - 20].hi;
                                // R256.w[2] stays 0
                                // R256.w[3] stays 0
                            }
                        }
                        R128.hi = R256.w[1];
                        R128.lo = R256.w[0];
                    }
                    // now add C3 * 10^scale in res and the signed top (q4-x0) digits of C4,
                    // rounded to nearest, which were copied into R128
                    if (z_sign == p_sign) {
                        lsb = Int(res.lo & 0x01) // lsb of C3 * 10^scale
                        // the sum can result in [up to] p34 or p34 + 1 digits
                        res.lo = res.lo + R128.lo
                        res.hi = res.hi + R128.hi;
                        if (res.lo < R128.lo) {
                            res.hi+=1 // carry
                        }
                        // if res > 10^34 - 1 need to increase x0 and decrease scale by 1
                        if (res.hi > 0x0001ed09bead87c0 ||
                            (res.hi == 0x0001ed09bead87c0 &&
                             res.lo > 0x378d8e63ffffffff)) {
                            // avoid double rounding error
                            is_inexact_lt_midpoint0 = is_inexact_lt_midpoint;
                            is_inexact_gt_midpoint0 = is_inexact_gt_midpoint;
                            is_midpoint_lt_even0 = is_midpoint_lt_even;
                            is_midpoint_gt_even0 = is_midpoint_gt_even;
                            is_inexact_lt_midpoint = false
                            is_inexact_gt_midpoint = false
                            is_midpoint_lt_even = false
                            is_midpoint_gt_even = false
                            P128.hi = res.hi;
                            P128.lo = res.lo;
                            bid_round128_19_38 (35, 1, P128, &res, &incr_exp,
                                                &is_midpoint_lt_even, &is_midpoint_gt_even,
                                                &is_inexact_lt_midpoint,
                                                &is_inexact_gt_midpoint);
                            // incr_exp is 0 with certainty in this case
                            // avoid a double rounding error
                            if ((is_inexact_gt_midpoint0 || is_midpoint_lt_even0) &&
                                is_midpoint_lt_even) { // double rounding error upward
                                // res = res - 1
                                res.lo-=1
                                if (res.lo == 0xffffffffffffffff) {
                                    res.hi-=1
                                }
                                // Note: a double rounding error upward is not possible; for this
                                // the result after the first rounding would have to be 99...95
                                // (35 digits in all), possibly followed by a number of zeros; this
                                // not possible in Cases (2)-(6) or (15)-(17) which may get here
                                is_midpoint_lt_even = false
                                is_inexact_lt_midpoint = true
                            } else if ((is_inexact_lt_midpoint0 || is_midpoint_gt_even0) &&
                                       is_midpoint_gt_even) { // double rounding error downward
                                // res = res + 1
                                res.lo+=1
                                if (res.lo == 0) {
                                    res.hi+=1
                                }
                                is_midpoint_gt_even = false
                                is_inexact_gt_midpoint = true
                            } else if (!is_midpoint_lt_even && !is_midpoint_gt_even &&
                                       !is_inexact_lt_midpoint
                                       && !is_inexact_gt_midpoint) {
                                // if this second rounding was exact the result may still be
                                // inexact because of the first rounding
                                if (is_inexact_gt_midpoint0 || is_midpoint_lt_even0) {
                                    is_inexact_gt_midpoint = true
                                }
                                if (is_inexact_lt_midpoint0 || is_midpoint_gt_even0) {
                                    is_inexact_lt_midpoint = true
                                }
                            } else if (is_midpoint_gt_even &&
                                       (is_inexact_gt_midpoint0
                                        || is_midpoint_lt_even0)) {
                                // pulled up to a midpoint
                                is_inexact_lt_midpoint = true
                                is_inexact_gt_midpoint = false
                                is_midpoint_lt_even = false
                                is_midpoint_gt_even = false
                            } else if (is_midpoint_lt_even &&
                                       (is_inexact_lt_midpoint0
                                        || is_midpoint_gt_even0)) {
                                // pulled down to a midpoint
                                is_inexact_lt_midpoint = false
                                is_inexact_gt_midpoint = true
                                is_midpoint_lt_even = false
                                is_midpoint_gt_even = false
                            } else {
                                // nothing
                            }
                            // adjust exponent
                            e3 = e3 + 1;
                            if (!is_midpoint_lt_even && !is_midpoint_gt_even &&
                                !is_inexact_lt_midpoint && !is_inexact_gt_midpoint) {
                                if (is_midpoint_lt_even0 || is_midpoint_gt_even0 ||
                                    is_inexact_lt_midpoint0 || is_inexact_gt_midpoint0) {
                                    is_inexact_lt_midpoint = true
                                }
                            }
                        } else {
                            // this is the result rounded with unbounded exponent, unless a
                            // correction is needed
                            res.hi = res.hi & MASK_COEFF;
                            if (lsb == 1) {
                                if (is_midpoint_gt_even) {
                                    // res = res + 1
                                    is_midpoint_gt_even = false
                                    is_midpoint_lt_even = true
                                    res.lo+=1
                                    if (res.lo == 0x0) {
                                        res.hi+=1
                                    }
                                    // check for rounding overflow
                                    if (res.hi == 0x0001ed09bead87c0 &&
                                        res.lo == 0x378d8e6400000000) {
                                        // res = 10^34 => rounding overflow
                                        res.hi = 0x0000314dc6448d93;
                                        res.lo = 0x38c15b0a00000000; // 10^33
                                        e3+=1
                                    }
                                } else if (is_midpoint_lt_even) {
                                    // res = res - 1
                                    is_midpoint_lt_even = false
                                    is_midpoint_gt_even = true
                                    res.lo-=1
                                    if (res.lo == 0xffffffffffffffff) {
                                        res.hi-=1
                                    }
                                    // if the result is pure zero, the sign depends on the rounding
                                    // mode (x*y and z had opposite signs)
                                    if (res.hi == 0x0 && res.lo == 0x0) {
                                        if (rnd_mode != BID_ROUNDING_DOWN) {
                                            z_sign = 0x0000000000000000;
                                        } else {
                                            z_sign = 0x8000000000000000;
                                        }
                                        // the exponent is max (e3, expmin)
                                        res.hi = 0x0;
                                        res.lo = 0x0;
                                        //                                    ptr_is_midpoint_lt_even = is_midpoint_lt_even;
                                        //                                    ptr_is_midpoint_gt_even = is_midpoint_gt_even;
                                        //                                    ptr_is_inexact_lt_midpoint = is_inexact_lt_midpoint;
                                        //                                    ptr_is_inexact_gt_midpoint = is_inexact_gt_midpoint;
                                        BID_SWAP128(&res)
                                        return res
                                    }
                                } else {
                                    // nothing
                                }
                            }
                        }
                    } else { // if (z_sign != p_sign)
                        lsb = Int(res.lo & 0x01) // lsb of C3 * 10^scale; R128 contains rounded C4
                        // used to swap rounding indicators if p_sign != z_sign
                        // the sum can result in [up to] p34 or p34 - 1 digits
                        tmp64 = res.lo;
                        res.lo = res.lo - R128.lo;
                        res.hi = res.hi - R128.hi;
                        if (res.lo > tmp64) {
                            res.hi-=1 // borrow
                        }
                        // if res < 10^33 and exp > expmin need to decrease x0 and
                        // increase scale by 1
                        if (e3 > expmin && ((res.hi < 0x0000314dc6448d93 ||
                                             (res.hi == 0x0000314dc6448d93 &&
                                              res.lo < 0x38c15b0a00000000)) ||
                                            ((is_inexact_lt_midpoint || is_midpoint_gt_even)
                                             && res.hi == 0x0000314dc6448d93
                                             && res.lo == 0x38c15b0a00000000))
                            && x0 >= 1) {
                            x0 = x0 - 1;
                            // first restore e3, otherwise it will be too small
                            e3 = e3 + scale;
                            scale = scale + 1;
                            is_inexact_lt_midpoint = false
                            is_inexact_gt_midpoint = false
                            is_midpoint_lt_even = false
                            is_midpoint_gt_even = false
                            incr_exp = 0
                            //  goto case2_repeat;
                        }
                        //                       break
                        //                   } // end while - case2_repeat
                        
                        // else this is the result rounded with unbounded exponent;
                        // because the result has opposite sign to that of C4 which was
                        // rounded, need to change the rounding indicators
                        if (is_inexact_lt_midpoint) {
                            is_inexact_lt_midpoint = false
                            is_inexact_gt_midpoint = true
                        } else if (is_inexact_gt_midpoint) {
                            is_inexact_gt_midpoint = false
                            is_inexact_lt_midpoint = true
                        } else if (lsb == 0) {
                            if (is_midpoint_lt_even) {
                                is_midpoint_lt_even = false
                                is_midpoint_gt_even = true
                            } else if (is_midpoint_gt_even) {
                                is_midpoint_gt_even = false
                                is_midpoint_lt_even = true
                            } else {
                                // nothing
                            }
                        } else if (lsb == 1) {
                            if (is_midpoint_lt_even) {
                                // res = res + 1
                                res.lo+=1
                                if (res.lo == 0x0) {
                                    res.hi+=1
                                }
                                // check for rounding overflow
                                if (res.hi == 0x0001ed09bead87c0 &&
                                    res.lo == 0x378d8e6400000000) {
                                    // res = 10^34 => rounding overflow
                                    res.hi = 0x0000314dc6448d93;
                                    res.lo = 0x38c15b0a00000000; // 10^33
                                    e3+=1
                                }
                            } else if (is_midpoint_gt_even) {
                                // res = res - 1
                                res.lo-=1
                                if (res.lo == 0xffffffffffffffff) {
                                    res.hi-=1
                                }
                                // if the result is pure zero, the sign depends on the rounding
                                // mode (x*y and z had opposite signs)
                                if (res.hi == 0x0 && res.lo == 0x0) {
                                    if (rnd_mode != BID_ROUNDING_DOWN) {
                                        z_sign = 0x0000000000000000;
                                    } else {
                                        z_sign = 0x8000000000000000;
                                    }
                                    // the exponent is max (e3, expmin)
                                    res.hi = 0x0;
                                    res.lo = 0x0;
                                    //                                ptr_is_midpoint_lt_even = is_midpoint_lt_even;
                                    //                                ptr_is_midpoint_gt_even = is_midpoint_gt_even;
                                    //                                ptr_is_inexact_lt_midpoint = is_inexact_lt_midpoint;
                                    //                                ptr_is_inexact_gt_midpoint = is_inexact_gt_midpoint;
                                    BID_SWAP128(&res)
                                    return res
                                }
                            } else {
                                // nothing
                            }
                        } else {
                            // nothing
                        }
                    }
                    
                    // check for underflow
                    if (e3 == expmin) { // and if significand < 10^33 => result is tiny
                        if ((res.hi & MASK_COEFF) < 0x0000314dc6448d93 ||
                            ((res.hi & MASK_COEFF) == 0x0000314dc6448d93 &&
                             res.lo < 0x38c15b0a00000000)) {
                            is_tiny = true
                        }
                        if (((res.hi & 0x7fffffffffffffff) == 0x0000314dc6448d93) &&
                            (res.lo == 0x38c15b0a00000000) &&  // 10^33*10^-6176
                            (z_sign != p_sign)) { is_tiny = true }
                    } else if (e3 < expmin) {
                        // the result is tiny, so we must truncate more of res
                        is_tiny = true
                        x0 = expmin - e3;
                        is_inexact_lt_midpoint0 = is_inexact_lt_midpoint;
                        is_inexact_gt_midpoint0 = is_inexact_gt_midpoint;
                        is_midpoint_lt_even0 = is_midpoint_lt_even;
                        is_midpoint_gt_even0 = is_midpoint_gt_even;
                        is_inexact_lt_midpoint = false
                        is_inexact_gt_midpoint = false
                        is_midpoint_lt_even = false
                        is_midpoint_gt_even = false
                        // determine the number of decimal digits in res
                        if (res.hi == 0x0) {
                            // between 1 and 19 digits
                            for ind in 1...19 {
                                if (res.lo < bid_ten2k64[ind]) {
                                    break;
                                }
                            }
                            // ind digits
                        } else if (res.hi < bid_ten2k128[0].hi ||
                                   (res.hi == bid_ten2k128[0].hi
                                    && res.lo < bid_ten2k128[0].lo)) {
                            // 20 digits
                            ind = 20;
                        } else { // between 21 and 38 digits
                            for ind in 1...18 {
                                if (res.hi < bid_ten2k128[ind].hi ||
                                    (res.hi == bid_ten2k128[ind].hi &&
                                     res.lo < bid_ten2k128[ind].lo)) {
                                    break;
                                }
                            }
                            // ind + 20 digits
                            ind = ind + 20;
                        }
                        
                        // at this point ind >= x0; because delta >= 2 on this path, the case
                        // ind = x0 can occur only in Case (2) or case (3), when C3 has one
                        // digit (q3 = 1) equal to 1 (C3 = 1), e3 is expmin (e3 = expmin),
                        // the signs of x * y and z are opposite, and through cancellation
                        // the most significant decimal digit in res has the weight
                        // 10^(emin-1); however, it is clear that in this case the most
                        // significant digit is 9, so the result before rounding is
                        // 0.9... * 10^emin
                        // Otherwise, ind > x0 because there are non-zero decimal digits in the
                        // result with weight of at least 10^emin, and correction for underflow
                        //  can be carried out using the round*_*_2_* () routines
                        if (x0 == ind) { // the result before rounding is 0.9... * 10^emin
                            res.hi = 0x0;
                            res.lo = 0x1;
                            is_inexact_gt_midpoint = true
                        } else if (ind <= 18) { // check that 2 <= ind
                            // 2 <= ind <= 18, 1 <= x0 <= 17
                            bid_round64_2_18 (ind, x0, res.lo, &R64, &incr_exp,
                                              &is_midpoint_lt_even, &is_midpoint_gt_even,
                                              &is_inexact_lt_midpoint,
                                              &is_inexact_gt_midpoint);
                            if incr_exp != 0 {
                                // R64 = 10^(ind-x0), 1 <= ind - x0 <= ind - 1, 1 <= ind - x0 <= 17
                                R64 = bid_ten2k64[ind - x0];
                            }
                            res.hi = 0
                            res.lo = R64
                        } else if (ind <= 38) {
                            // 19 <= ind <= 38
                            P128.hi = res.hi;
                            P128.lo = res.lo;
                            bid_round128_19_38 (ind, x0, P128, &res, &incr_exp,
                                                &is_midpoint_lt_even, &is_midpoint_gt_even,
                                                &is_inexact_lt_midpoint,
                                                &is_inexact_gt_midpoint);
                            if incr_exp != 0 {
                                // R128 = 10^(ind-x0), 1 <= ind - x0 <= ind - 1, 1 <= ind - x0 <= 37
                                if (ind - x0 <= 19) { // 1 <= ind - x0 <= 19
                                    res.lo = bid_ten2k64[ind - x0];
                                    // res.hi stays 0
                                } else { // 20 <= ind - x0 <= 37
                                    res.lo = bid_ten2k128[ind - x0 - 20].lo;
                                    res.hi = bid_ten2k128[ind - x0 - 20].hi;
                                }
                            }
                        }
                        // avoid a double rounding error
                        if ((is_inexact_gt_midpoint0 || is_midpoint_lt_even0) &&
                            is_midpoint_lt_even) { // double rounding error upward
                            // res = res - 1
                            res.lo-=1
                            if (res.lo == 0xffffffffffffffff) {
                                res.hi-=1
                            }
                            // Note: a double rounding error upward is not possible; for this
                            // the result after the first rounding would have to be 99...95
                            // (35 digits in all), possibly followed by a number of zeros; this
                            // not possible in Cases (2)-(6) which may get here
                            is_midpoint_lt_even = false
                            is_inexact_lt_midpoint = true
                        } else if ((is_inexact_lt_midpoint0 || is_midpoint_gt_even0) &&
                                   is_midpoint_gt_even) { // double rounding error downward
                            // res = res + 1
                            res.lo+=1
                            if (res.lo == 0) { res.hi+=1 }
                            is_midpoint_gt_even = false
                            is_inexact_gt_midpoint = true
                        } else if (!is_midpoint_lt_even && !is_midpoint_gt_even &&
                                   !is_inexact_lt_midpoint && !is_inexact_gt_midpoint) {
                            // if this second rounding was exact the result may still be
                            // inexact because of the first rounding
                            if (is_inexact_gt_midpoint0 || is_midpoint_lt_even0) {
                                is_inexact_gt_midpoint = true
                            }
                            if (is_inexact_lt_midpoint0 || is_midpoint_gt_even0) {
                                is_inexact_lt_midpoint = true
                            }
                        } else if (is_midpoint_gt_even &&
                                   (is_inexact_gt_midpoint0 || is_midpoint_lt_even0)) {
                            // pulled up to a midpoint
                            is_inexact_lt_midpoint = true
                            is_inexact_gt_midpoint = false
                            is_midpoint_lt_even = false
                            is_midpoint_gt_even = false
                        } else if (is_midpoint_lt_even &&
                                   (is_inexact_lt_midpoint0 || is_midpoint_gt_even0)) {
                            // pulled down to a midpoint
                            is_inexact_lt_midpoint = false
                            is_inexact_gt_midpoint = true
                            is_midpoint_lt_even = false
                            is_midpoint_gt_even = false
                        } else {
                            // nothing
                        }
                        // adjust exponent
                        e3 = e3 + x0;
                        if (!is_midpoint_lt_even && !is_midpoint_gt_even &&
                            !is_inexact_lt_midpoint && !is_inexact_gt_midpoint) {
                            if (is_midpoint_lt_even0 || is_midpoint_gt_even0 ||
                                is_inexact_lt_midpoint0 || is_inexact_gt_midpoint0) {
                                is_inexact_lt_midpoint = true
                            }
                        }
                    } else {
                        // not underflow
                    }
                    // check for inexact result
                    if (is_inexact_lt_midpoint || is_inexact_gt_midpoint ||
                        is_midpoint_lt_even || is_midpoint_gt_even) {
                        // set the inexact flag
                        pfpsf.insert(.inexact)
                        if (is_tiny) {
                            pfpsf.insert(.underflow)
                        }
                    }
                    // now check for significand = 10^34 (may have resulted from going
                    // back to case2_repeat)
                    if (res.hi == 0x0001ed09bead87c0 &&
                        res.lo == 0x378d8e6400000000) { // if  res = 10^34
                        res.hi = 0x0000314dc6448d93; // res = 10^33
                        res.lo = 0x38c15b0a00000000;
                        e3 = e3 + 1;
                    }
                    res.hi = z_sign | (UInt64(e3 + 6176) << 49) | res.hi;
                    // check for overflow
                    if (rnd_mode == BID_ROUNDING_TO_NEAREST && e3 > expmax) {
                        res.hi = z_sign | 0x7800000000000000; // +/-inf
                        res.lo = 0x0000000000000000;
                        pfpsf.formUnion([.inexact, .overflow])
                    }
                    if (rnd_mode != BID_ROUNDING_TO_NEAREST) {
                        bid_rounding_correction (rnd_mode,
                                                 is_inexact_lt_midpoint,
                                                 is_inexact_gt_midpoint,
                                                 is_midpoint_lt_even, is_midpoint_gt_even,
                                                 e3, &res, &pfpsf);
                    }
                    //                ptr_is_midpoint_lt_even = is_midpoint_lt_even;
                    //                ptr_is_midpoint_gt_even = is_midpoint_gt_even;
                    //                ptr_is_inexact_lt_midpoint = is_inexact_lt_midpoint;
                    //                ptr_is_inexact_gt_midpoint = is_inexact_gt_midpoint;
                    BID_SWAP128(&res)
                    return res
                    
                } else {
                    
                    // we get here only if delta <= 1 in Cases (2), (3), (4), (5), or (6) and
                    // the signs of x*y and z are opposite; in these cases massive
                    // cancellation can occur, so it is better to scale either C3 or C4 and
                    // to perform the subtraction before rounding; rounding is performed
                    // next, depending on the number of decimal digits in the result and on
                    // the exponent value
                    // Note: overlow is not possible in this case
                    // this is similar to Cases (15), (16), and (17)
                    
                    if (delta + q4 < q3) { // from Case (6)
                        // Case (6) with 0<= delta <= 1 is similar to Cases (15), (16), and
                        // (17) if we swap (C3, C4), (q3, q4), (e3, e4), (z_sign, p_sign)
                        // and call bid_add_and_round; delta stays positive
                        // C4.w[3] = 0 and C4.w[2] = 0, so swap just the low part of C4 with C3
                        P128.hi = C3.hi;
                        P128.lo = C3.lo;
                        C3.hi = C4.w[1];
                        C3.lo = C4.w[0];
                        C4.w[1] = P128.hi;
                        C4.w[0] = P128.lo;
                        ind = q3;
                        q3 = q4;
                        q4 = ind;
                        ind = e3;
                        e3 = e4;
                        e4 = ind;
                        tmp_sign = z_sign;
                        z_sign = p_sign;
                        p_sign = tmp_sign;
                    } else { // from Cases (2), (3), (4), (5)
                        // In Cases (2), (3), (4), (5) with 0 <= delta <= 1 C3 has to be
                        // scaled up by q4 + delta - q3; this is the same as in Cases (15),
                        // (16), and (17) if we just change the sign of delta
                        delta = -delta;
                    }
                    bid_add_and_round (q3, q4, e4, delta, p34, z_sign, p_sign, C3, C4,
                                       rnd_mode, &is_midpoint_lt_even,
                                       &is_midpoint_gt_even, &is_inexact_lt_midpoint,
                                       &is_inexact_gt_midpoint, &pfpsf, &res);
                    //                ptr_is_midpoint_lt_even = is_midpoint_lt_even;
                    //                ptr_is_midpoint_gt_even = is_midpoint_gt_even;
                    //                ptr_is_inexact_lt_midpoint = is_inexact_lt_midpoint;
                    //                ptr_is_inexact_gt_midpoint = is_inexact_gt_midpoint;
                    BID_SWAP128(&res)
                    return res
                }
                
            } else { // if delta < 0
                
                delta = -delta;
                
                if (p34 < q4 && q4 <= delta) { // Case (7)
                    
                    // truncate C4 to p34 digits into res
                    // x = q4-p34, 1 <= x <= 34 because 35 <= q4 <= 68
                    x0 = q4 - p34;
                    if (q4 <= 38) {
                        P128.hi = C4.w[1];
                        P128.lo = C4.w[0];
                        bid_round128_19_38 (q4, x0, P128, &res, &incr_exp,
                                            &is_midpoint_lt_even, &is_midpoint_gt_even,
                                            &is_inexact_lt_midpoint,
                                            &is_inexact_gt_midpoint);
                    } else if (q4 <= 57) { // 35 <= q4 <= 57
                        P192.w[2] = C4.w[2];
                        P192.w[1] = C4.w[1];
                        P192.w[0] = C4.w[0];
                        bid_round192_39_57 (q4, x0, P192, &R192, &incr_exp,
                                            &is_midpoint_lt_even, &is_midpoint_gt_even,
                                            &is_inexact_lt_midpoint,
                                            &is_inexact_gt_midpoint);
                        res.lo = R192.w[0];
                        res.hi = R192.w[1];
                    } else { // if (q4 <= 68)
                        bid_round256_58_76 (q4, x0, C4, &R256, &incr_exp,
                                            &is_midpoint_lt_even, &is_midpoint_gt_even,
                                            &is_inexact_lt_midpoint,
                                            &is_inexact_gt_midpoint);
                        res.lo = R256.w[0];
                        res.hi = R256.w[1];
                    }
                    e4 = e4 + x0;
                    if incr_exp != 0 {
                        e4 = e4 + 1;
                    }
                    if (!is_midpoint_lt_even && !is_midpoint_gt_even &&
                        !is_inexact_lt_midpoint && !is_inexact_gt_midpoint) {
                        // if C4 rounded to p34 digits is exact then the result is inexact,
                        // in a way that depends on the signs of x * y and z
                        if (p_sign == z_sign) {
                            is_inexact_lt_midpoint = true
                        } else { // if (p_sign != z_sign)
                            if (res.hi != 0x0000314dc6448d93 ||
                                res.lo != 0x38c15b0a00000000) { // res != 10^33
                                is_inexact_gt_midpoint = true
                            } else { // res = 10^33 and exact is a special case
                                // if C3 < 1/2 ulp then res = 10^33 and is_inexact_gt_midpoint = 1
                                // if C3 = 1/2 ulp then res = 10^33 and is_midpoint_lt_even = 1
                                // if C3 > 1/2 ulp then res = 10^34-1 and is_inexact_lt_midpoint = 1
                                // Note: ulp is really ulp/10 (after borrow which propagates to msd)
                                if (delta > p34 + 1) { // C3 < 1/2
                                    // res = 10^33, unchanged
                                    is_inexact_gt_midpoint = true
                                } else { // if (delta == p34 + 1)
                                    if (q3 <= 19) {
                                        if (C3.lo < bid_midpoint64[q3 - 1]) { // C3 < 1/2 ulp
                                            // res = 10^33, unchanged
                                            is_inexact_gt_midpoint = true
                                        } else if (C3.lo == bid_midpoint64[q3 - 1]) { // C3 = 1/2 ulp
                                            // res = 10^33, unchanged
                                            is_midpoint_lt_even = true
                                        } else { // if (C3.lo > bid_midpoint64[q3-1]), C3 > 1/2 ulp
                                            res.hi = 0x0001ed09bead87c0; // 10^34 - 1
                                            res.lo = 0x378d8e63ffffffff;
                                            e4 = e4 - 1;
                                            is_inexact_lt_midpoint = true
                                        }
                                    } else { // if (20 <= q3 <=34)
                                        if (C3.hi < bid_midpoint128[q3 - 20].hi ||
                                            (C3.hi == bid_midpoint128[q3 - 20].hi &&
                                             C3.lo < bid_midpoint128[q3 - 20].lo)) { // C3 < 1/2 ulp
                                            // res = 10^33, unchanged
                                            is_inexact_gt_midpoint = true
                                        } else if (C3.hi == bid_midpoint128[q3 - 20].hi &&
                                                   C3.lo == bid_midpoint128[q3 - 20].lo) { // C3 = 1/2 ulp
                                            // res = 10^33, unchanged
                                            is_midpoint_lt_even = true
                                        } else { // if (C3 > bid_midpoint128[q3-20]), C3 > 1/2 ulp
                                            res.hi = 0x0001ed09bead87c0; // 10^34 - 1
                                            res.lo = 0x378d8e63ffffffff;
                                            e4 = e4 - 1;
                                            is_inexact_lt_midpoint = true
                                        }
                                    }
                                }
                            }
                        }
                    } else if (is_midpoint_lt_even) {
                        if (z_sign != p_sign) {
                            // needs correction: res = res - 1
                            res.lo = res.lo &- 1
                            if (res.lo == 0xffffffffffffffff) { res.hi-=1 }
                            
                            // if it is (10^33-1)*10^e4 then the corect result is
                            // (10^34-1)*10(e4-1)
                            if (res.hi == 0x0000314dc6448d93 &&
                                res.lo == 0x38c15b09ffffffff) {
                                res.hi = 0x0001ed09bead87c0; // 10^34 - 1
                                res.lo = 0x378d8e63ffffffff;
                                e4 = e4 - 1;
                            }
                            is_midpoint_lt_even = false
                            is_inexact_lt_midpoint = true
                        } else { // if (z_sign == p_sign)
                            is_midpoint_lt_even = false
                            is_inexact_gt_midpoint = true
                        }
                    } else if (is_midpoint_gt_even) {
                        if (z_sign == p_sign) {
                            // needs correction: res = res + 1 (cannot cross in the next binade)
                            res.lo = res.lo &+ 1;
                            if (res.lo == 0x0000000000000000) { res.hi+=1 }
                            is_midpoint_gt_even = false
                            is_inexact_gt_midpoint = true
                        } else { // if (z_sign != p_sign)
                            is_midpoint_gt_even = false
                            is_inexact_lt_midpoint = true
                        }
                    } else {
                        // the rounded result is already correct
                    }
                    // check for overflow
                    if (rnd_mode == BID_ROUNDING_TO_NEAREST && e4 > expmax) {
                        res.hi = p_sign | 0x7800000000000000;
                        res.lo = 0x0000000000000000;
                        pfpsf.formUnion([.overflow, .inexact])
                    } else { // no overflow or not RN
                        p_exp = Int(UInt64(e4 + 6176) << 49);
                        res.hi = p_sign | (UInt64(p_exp) & MASK_EXP) | res.hi;
                    }
                    if (rnd_mode != BID_ROUNDING_TO_NEAREST) {
                        bid_rounding_correction (rnd_mode,
                                                 is_inexact_lt_midpoint,
                                                 is_inexact_gt_midpoint,
                                                 is_midpoint_lt_even, is_midpoint_gt_even,
                                                 e4, &res, &pfpsf);
                    }
                    if (is_inexact_lt_midpoint || is_inexact_gt_midpoint || is_midpoint_lt_even || is_midpoint_gt_even) {
                        // set the inexact flag
                        pfpsf.insert(.inexact)
                    }
                    //                ptr_is_midpoint_lt_even = is_midpoint_lt_even;
                    //                ptr_is_midpoint_gt_even = is_midpoint_gt_even;
                    //                ptr_is_inexact_lt_midpoint = is_inexact_lt_midpoint;
                    //                ptr_is_inexact_gt_midpoint = is_inexact_gt_midpoint;
                    BID_SWAP128(&res)
                    return res
                    
                } else if ((q4 <= p34 && p34 <= delta) || // Case (8)
                           (q4 <= delta && delta < p34 && p34 < delta + q3) || // Case (9)
                           (q4 <= delta && delta + q3 <= p34) || // Case (10)
                           (delta < q4 && q4 <= p34 && p34 < delta + q3) || // Case (13)
                           (delta < q4 && q4 <= delta + q3 && delta + q3 <= p34) || // Case (14)
                           (delta + q3 < q4 && q4 <= p34)) { // Case (18)
                    
                    // Case (8) is similar to Case (1), with C3 and C4 swapped
                    // Case (9) is similar to Case (2), with C3 and C4 swapped
                    // Case (10) is similar to Case (3), with C3 and C4 swapped
                    // Case (13) is similar to Case (4), with C3 and C4 swapped
                    // Case (14) is similar to Case (5), with C3 and C4 swapped
                    // Case (18) is similar to Case (6), with C3 and C4 swapped
                    
                    // swap (C3, C4), (q3, q4), (e3, 34), (z_sign, p_sign), (z_exp, p_exp)
                    // and go back to delta_ge_zero
                    // C4.w[3] = 0 and C4.w[2] = 0, so swap just the low part of C4 with C3
                    P128.hi = C3.hi;
                    P128.lo = C3.lo;
                    C3.hi = C4.w[1];
                    C3.lo = C4.w[0];
                    C4.w[1] = P128.hi;
                    C4.w[0] = P128.lo;
                    ind = q3;
                    q3 = q4;
                    q4 = ind;
                    ind = e3;
                    e3 = e4;
                    e4 = ind;
                    tmp_sign = z_sign;
                    z_sign = p_sign;
                    p_sign = tmp_sign;
                    tmp = Double(bitPattern: UInt64(z_exp))
                    z_exp = p_exp;
                    p_exp = Int(tmp.bitPattern)
                    continue // goto delta_ge_zero;
                    
                } else if ((p34 <= delta && delta < q4 && q4 < delta + q3) || // Case (11)
                           (delta < p34 && p34 < q4 && q4 < delta + q3)) { // Case (12)
                    
                    // round C3 to nearest to q3 - x0 digits, where x0 = e4 - e3,
                    // 1 <= x0 <= q3 - 1 <= p34 - 1
                    x0 = e4 - e3; // or x0 = delta + q3 - q4
                    if (q3 <= 18) { // 2 <= q3 <= 18
                        bid_round64_2_18 (q3, x0, C3.lo, &R64, &incr_exp,
                                          &is_midpoint_lt_even, &is_midpoint_gt_even,
                                          &is_inexact_lt_midpoint, &is_inexact_gt_midpoint);
                        // C3.hi = 0;
                        C3.lo = R64;
                    } else if (q3 <= 38) {
                        bid_round128_19_38 (q3, x0, C3, &R128, &incr_exp,
                                            &is_midpoint_lt_even, &is_midpoint_gt_even,
                                            &is_inexact_lt_midpoint,
                                            &is_inexact_gt_midpoint);
                        C3.hi = R128.hi;
                        C3.lo = R128.lo;
                    }
                    // the rounded result has q3 - x0 digits
                    // we want the exponent to be e4, so if incr_exp = 1 then
                    // multiply the rounded result by 10 - it will still fit in 113 bits
                    if incr_exp != 0 {
                        // 64 x 128 -> 128
                        P128.hi = C3.hi
                        P128.lo = C3.lo
                        __mul_64x128_to_128(&C3, bid_ten2k64[1], P128);
                    }
                    e3 = e3 + x0; // this is e4
                    // now add/subtract the 256-bit C4 and the new (and shorter) 128-bit C3;
                    // the result will have the sign of x * y; the exponent is e4
                    R256.w[3] = 0;
                    R256.w[2] = 0;
                    R256.w[1] = C3.hi;
                    R256.w[0] = C3.lo;
                    if (p_sign == z_sign) { // R256 = C4 + R256
                        bid_add256(C4, R256, &R256);
                    } else { // if (p_sign != z_sign) { // R256 = C4 - R256
                        bid_sub256(C4, R256, &R256); // the result cannot be pure zero
                        // because the result has opposite sign to that of R256 which was
                        // rounded, need to change the rounding indicators
                        lsb = Int(C4.w[0]) & 0x01
                        if (is_inexact_lt_midpoint) {
                            is_inexact_lt_midpoint = false
                            is_inexact_gt_midpoint = true
                        } else if (is_inexact_gt_midpoint) {
                            is_inexact_gt_midpoint = false
                            is_inexact_lt_midpoint = true
                        } else if (lsb == 0) {
                            if (is_midpoint_lt_even) {
                                is_midpoint_lt_even = false
                                is_midpoint_gt_even = true
                            } else if (is_midpoint_gt_even) {
                                is_midpoint_gt_even = false
                                is_midpoint_lt_even = true
                            } else {
                                // nothing
                            }
                        } else if (lsb == 1) {
                            if (is_midpoint_lt_even) {
                                // res = res + 1
                                R256.w[0]+=1
                                if (R256.w[0] == 0x0) {
                                    R256.w[1]+=1
                                    if (R256.w[1] == 0x0) {
                                        R256.w[2]+=1
                                        if (R256.w[2] == 0x0) {
                                            R256.w[3]+=1
                                        }
                                    }
                                }
                                // no check for rounding overflow - R256 was a difference
                            } else if (is_midpoint_gt_even) {
                                // res = res - 1
                                R256.w[0]-=1
                                if (R256.w[0] == 0xffffffffffffffff) {
                                    R256.w[1]-=1
                                    if (R256.w[1] == 0xffffffffffffffff) {
                                        R256.w[2]-=1
                                        if (R256.w[2] == 0xffffffffffffffff) {
                                            R256.w[3]-=1
                                        }
                                    }
                                }
                            } else {
                                // nothing
                            }
                        } else {
                            // nothing
                        }
                    }
                    // determine the number of decimal digits in R256
                    ind = bid_bid_nr_digits256 (R256); // ind >= p34
                    // if R256 is sum, then ind > p34; if R256 is a difference, then
                    // ind >= p34; this means that we can calculate the result rounded to
                    // the destination precision, with unbounded exponent, starting from R256
                    // and using the indicators from the rounding of C3 to avoid a double
                    // rounding error
                    
                    if (ind < p34) {
                        // nothing
                    } else if (ind == p34) {
                        // the result rounded to the destination precision with
                        // unbounded exponent
                        // is (-1)^p_sign * R256 * 10^e4
                        res.hi = R256.w[1];
                        res.lo = R256.w[0];
                    } else { // if (ind > p34)
                        // if more than P digits, round to nearest to P digits
                        // round R256 to p34 digits
                        x0 = ind - p34; // 1 <= x0 <= 34 as 35 <= ind <= 68
                        // save C3 rounding indicators to help avoid double rounding error
                        is_inexact_lt_midpoint0 = is_inexact_lt_midpoint;
                        is_inexact_gt_midpoint0 = is_inexact_gt_midpoint;
                        is_midpoint_lt_even0 = is_midpoint_lt_even;
                        is_midpoint_gt_even0 = is_midpoint_gt_even;
                        // initialize rounding indicators
                        is_inexact_lt_midpoint = false
                        is_inexact_gt_midpoint = false
                        is_midpoint_lt_even = false
                        is_midpoint_gt_even = false
                        // round to p34 digits; the result fits in 113 bits
                        if (ind <= 38) {
                            P128.hi = R256.w[1];
                            P128.lo = R256.w[0];
                            bid_round128_19_38 (ind, x0, P128, &R128, &incr_exp,
                                                &is_midpoint_lt_even, &is_midpoint_gt_even,
                                                &is_inexact_lt_midpoint,
                                                &is_inexact_gt_midpoint);
                        } else if (ind <= 57) {
                            P192.w[2] = R256.w[2];
                            P192.w[1] = R256.w[1];
                            P192.w[0] = R256.w[0];
                            bid_round192_39_57 (ind, x0, P192, &R192, &incr_exp,
                                                &is_midpoint_lt_even, &is_midpoint_gt_even,
                                                &is_inexact_lt_midpoint,
                                                &is_inexact_gt_midpoint);
                            R128.hi = R192.w[1];
                            R128.lo = R192.w[0];
                        } else { // if (ind <= 68)
                            bid_round256_58_76 (ind, x0, R256, &R256, &incr_exp,
                                                &is_midpoint_lt_even, &is_midpoint_gt_even,
                                                &is_inexact_lt_midpoint,
                                                &is_inexact_gt_midpoint);
                            R128.hi = R256.w[1];
                            R128.lo = R256.w[0];
                        }
                        // the rounded result has p34 = 34 digits
                        e4 = e4 + x0 + incr_exp;
                        
                        res.hi = R128.hi;
                        res.lo = R128.lo;
                        
                        // avoid a double rounding error
                        if ((is_inexact_gt_midpoint0 || is_midpoint_lt_even0) &&
                            is_midpoint_lt_even) { // double rounding error upward
                            // res = res - 1
                            res.lo-=1
                            if (res.lo == 0xffffffffffffffff) {
                                res.hi-=1
                            }
                            is_midpoint_lt_even = false
                            is_inexact_lt_midpoint = true
                            // Note: a double rounding error upward is not possible; for this
                            // the result after the first rounding would have to be 99...95
                            // (35 digits in all), possibly followed by a number of zeros; this
                            // not possible in Cases (2)-(6) or (15)-(17) which may get here
                            // if this is 10^33 - 1 make it 10^34 - 1 and decrement exponent
                            if (res.hi == 0x0000314dc6448d93 &&
                                res.lo == 0x38c15b09ffffffff) { // 10^33 - 1
                                res.hi = 0x0001ed09bead87c0; // 10^34 - 1
                                res.lo = 0x378d8e63ffffffff;
                                e4-=1
                            }
                        } else if ((is_inexact_lt_midpoint0 || is_midpoint_gt_even0) &&
                                   is_midpoint_gt_even) { // double rounding error downward
                            // res = res + 1
                            res.lo+=1
                            if (res.lo == 0) {
                                res.hi+=1
                            }
                            is_midpoint_gt_even = false
                            is_inexact_gt_midpoint = true
                        } else if (!is_midpoint_lt_even && !is_midpoint_gt_even &&
                                   !is_inexact_lt_midpoint && !is_inexact_gt_midpoint) {
                            // if this second rounding was exact the result may still be
                            // inexact because of the first rounding
                            if (is_inexact_gt_midpoint0 || is_midpoint_lt_even0) {
                                is_inexact_gt_midpoint = true
                            }
                            if (is_inexact_lt_midpoint0 || is_midpoint_gt_even0) {
                                is_inexact_lt_midpoint = true
                            }
                        } else if (is_midpoint_gt_even && (is_inexact_gt_midpoint0 || is_midpoint_lt_even0)) {
                            // pulled up to a midpoint
                            is_inexact_lt_midpoint = true
                            is_inexact_gt_midpoint = false
                            is_midpoint_lt_even = false
                            is_midpoint_gt_even = false
                        } else if (is_midpoint_lt_even && (is_inexact_lt_midpoint0 || is_midpoint_gt_even0)) {
                            // pulled down to a midpoint
                            is_inexact_lt_midpoint = false
                            is_inexact_gt_midpoint = true
                            is_midpoint_lt_even = false
                            is_midpoint_gt_even = false
                        } else {
                            // nothing
                        }
                    }
                    
                    // determine tininess
                    if (rnd_mode == BID_ROUNDING_TO_NEAREST) {
                        if (e4 < expmin) {
                            is_tiny = true // for other rounding modes apply correction
                        }
                    } else {
                        // for RM, RP, RZ, RA apply correction in order to determine tininess
                        // but do not save the result; apply the correction to
                        // (-1)^p_sign * res * 10^0
                        P128.hi = p_sign | 0x3040000000000000 | res.hi;
                        P128.lo = res.lo;
                        bid_rounding_correction (rnd_mode,
                                                 is_inexact_lt_midpoint,
                                                 is_inexact_gt_midpoint,
                                                 is_midpoint_lt_even, is_midpoint_gt_even,
                                                 0, &P128, &pfpsf);
                        scale = (Int(P128.hi & MASK_EXP) >> 49) - 6176; // -1, 0, or +1
                        // the number of digits in the significand is p34 = 34
                        if (e4 + scale < expmin) {
                            is_tiny = true
                        }
                    }
                    
                    // the result rounded to the destination precision with unbounded exponent
                    // is (-1)^p_sign * res * 10^e4
                    res.hi = p_sign | (UInt64(e4 + 6176) << 49) | res.hi; // RN
                    // res.lo unchanged;
                    // Note: res is correct only if expmin <= e4 <= expmax
                    ind = p34; // the number of decimal digits in the signifcand of res
                    
                    // at this point we have the result rounded with unbounded exponent in
                    // res and we know its tininess:
                    // res = (-1)^p_sign * significand * 10^e4,
                    // where q (significand) = ind = p34
                    // Note: res is correct only if expmin <= e4 <= expmax
                    
                    // check for overflow if RN
                    if (rnd_mode == BID_ROUNDING_TO_NEAREST
                        && (ind + e4) > (p34 + expmax)) {
                        res.hi = p_sign | 0x7800000000000000;
                        res.lo = 0x0000000000000000;
                        pfpsf.formUnion([.inexact, .overflow])
                        //                    ptr_is_midpoint_lt_even = is_midpoint_lt_even;
                        //                    ptr_is_midpoint_gt_even = is_midpoint_gt_even;
                        //                    ptr_is_inexact_lt_midpoint = is_inexact_lt_midpoint;
                        //                    ptr_is_inexact_gt_midpoint = is_inexact_gt_midpoint;
                        BID_SWAP128(&res)
                        return res
                    } // else not overflow or not RN, so continue
                    
                    // from this point on this is similar to the last part of the computation
                    // for Cases (15), (16), (17)
                    
                    // if (e4 >= expmin) we have the result rounded with bounded exponent
                    if (e4 < expmin) {
                        x0 = expmin - e4; // x0 >= 1; the number of digits to chop off of res
                        // where the result rounded [at most] once is
                        //   (-1)^p_sign * significand_res * 10^e4
                        
                        // avoid double rounding error
                        is_inexact_lt_midpoint0 = is_inexact_lt_midpoint;
                        is_inexact_gt_midpoint0 = is_inexact_gt_midpoint;
                        is_midpoint_lt_even0 = is_midpoint_lt_even;
                        is_midpoint_gt_even0 = is_midpoint_gt_even;
                        is_inexact_lt_midpoint = false
                        is_inexact_gt_midpoint = false
                        is_midpoint_lt_even = false
                        is_midpoint_gt_even = false
                        
                        if (x0 > ind) {
                            // nothing is left of res when moving the decimal point left x0 digits
                            is_inexact_lt_midpoint = true
                            res.hi = p_sign | 0x0000000000000000;
                            res.lo = 0x0000000000000000;
                            e4 = expmin;
                        } else if (x0 == ind) { // 1 <= x0 = ind <= p34 = 34
                            // this is <, =, or > 1/2 ulp
                            // compare the ind-digit value in the significand of res with
                            // 1/2 ulp = 5*10^(ind-1), i.e. determine whether it is
                            // less than, equal to, or greater than 1/2 ulp (significand of res)
                            R128.hi = res.hi & MASK_COEFF;
                            R128.lo = res.lo;
                            if (ind <= 19) {
                                if (R128.lo < bid_midpoint64[ind - 1]) { // < 1/2 ulp
                                    lt_half_ulp = true
                                    is_inexact_lt_midpoint = true
                                } else if (R128.lo == bid_midpoint64[ind - 1]) { // = 1/2 ulp
                                    eq_half_ulp = true
                                    is_midpoint_gt_even = true
                                } else { // > 1/2 ulp
                                    gt_half_ulp = true
                                    is_inexact_gt_midpoint = true
                                }
                            } else { // if (ind <= 38)
                                if (R128.hi < bid_midpoint128[ind - 20].hi ||
                                    (R128.hi == bid_midpoint128[ind - 20].hi &&
                                     R128.lo < bid_midpoint128[ind - 20].lo)) { // < 1/2 ulp
                                    lt_half_ulp = true
                                    is_inexact_lt_midpoint = true
                                } else if (R128.hi == bid_midpoint128[ind - 20].hi &&
                                           R128.lo == bid_midpoint128[ind - 20].lo) { // = 1/2 ulp
                                    eq_half_ulp = true
                                    is_midpoint_gt_even = true
                                } else { // > 1/2 ulp
                                    gt_half_ulp = true
                                    is_inexact_gt_midpoint = true
                                }
                            }
                            if (lt_half_ulp || eq_half_ulp) {
                                // res = +0.0 * 10^expmin
                                res.hi = 0x0000000000000000;
                                res.lo = 0x0000000000000000;
                            } else { // if (gt_half_ulp)
                                // res = +1 * 10^expmin
                                res.hi = 0x0000000000000000;
                                res.lo = 0x0000000000000001;
                            }
                            res.hi = p_sign | res.hi;
                            e4 = expmin;
                        } else { // if (1 <= x0 <= ind - 1 <= 33)
                            // round the ind-digit result to ind - x0 digits
                            
                            if (ind <= 18) { // 2 <= ind <= 18
                                bid_round64_2_18 (ind, x0, res.lo, &R64, &incr_exp,
                                                  &is_midpoint_lt_even, &is_midpoint_gt_even,
                                                  &is_inexact_lt_midpoint,
                                                  &is_inexact_gt_midpoint);
                                res.hi = 0x0;
                                res.lo = R64;
                            } else if (ind <= 38) {
                                P128.hi = res.hi & MASK_COEFF;
                                P128.lo = res.lo;
                                bid_round128_19_38 (ind, x0, P128, &res, &incr_exp,
                                                    &is_midpoint_lt_even, &is_midpoint_gt_even,
                                                    &is_inexact_lt_midpoint,
                                                    &is_inexact_gt_midpoint);
                            }
                            e4 = e4 + x0; // expmin
                            // we want the exponent to be expmin, so if incr_exp = 1 then
                            // multiply the rounded result by 10 - it will still fit in 113 bits
                            if incr_exp != 0 {
                                // 64 x 128 -> 128
                                P128.hi = res.hi & MASK_COEFF;
                                P128.lo = res.lo;
                                __mul_64x128_to_128(&res, bid_ten2k64[1], P128);
                            }
                            res.hi = p_sign | (UInt64(e4 + 6176) << 49) | (res.hi & MASK_COEFF);
                            // avoid a double rounding error
                            if ((is_inexact_gt_midpoint0 || is_midpoint_lt_even0) &&
                                is_midpoint_lt_even) { // double rounding error upward
                                // res = res - 1
                                res.lo-=1
                                if (res.lo == 0xffffffffffffffff) {
                                    res.hi-=1
                                }
                                // Note: a double rounding error upward is not possible; for this
                                // the result after the first rounding would have to be 99...95
                                // (35 digits in all), possibly followed by a number of zeros; this
                                // not possible in this underflow case
                                is_midpoint_lt_even = false
                                is_inexact_lt_midpoint = true
                            } else if ((is_inexact_lt_midpoint0 || is_midpoint_gt_even0) &&
                                       is_midpoint_gt_even) { // double rounding error downward
                                // res = res + 1
                                res.lo+=1
                                if (res.lo == 0) {
                                    res.hi+=1
                                }
                                is_midpoint_gt_even = false
                                is_inexact_gt_midpoint = true
                            } else if (!is_midpoint_lt_even && !is_midpoint_gt_even &&
                                       !is_inexact_lt_midpoint
                                       && !is_inexact_gt_midpoint) {
                                // if this second rounding was exact the result may still be
                                // inexact because of the first rounding
                                if (is_inexact_gt_midpoint0 || is_midpoint_lt_even0) {
                                    is_inexact_gt_midpoint = true
                                }
                                if (is_inexact_lt_midpoint0 || is_midpoint_gt_even0) {
                                    is_inexact_lt_midpoint = true
                                }
                            } else if (is_midpoint_gt_even &&
                                       (is_inexact_gt_midpoint0
                                        || is_midpoint_lt_even0)) {
                                // pulled up to a midpoint
                                is_inexact_lt_midpoint = true
                                is_inexact_gt_midpoint = false
                                is_midpoint_lt_even = false
                                is_midpoint_gt_even = false
                            } else if (is_midpoint_lt_even &&
                                       (is_inexact_lt_midpoint0
                                        || is_midpoint_gt_even0)) {
                                // pulled down to a midpoint
                                is_inexact_lt_midpoint = false
                                is_inexact_gt_midpoint = true
                                is_midpoint_lt_even = false
                                is_midpoint_gt_even = false
                            } else {
                                // nothing
                            }
                        }
                    }
                    // res contains the correct result
                    // apply correction if not rounding to nearest
                    if (rnd_mode != BID_ROUNDING_TO_NEAREST) {
                        bid_rounding_correction (rnd_mode,
                                                 is_inexact_lt_midpoint,
                                                 is_inexact_gt_midpoint,
                                                 is_midpoint_lt_even, is_midpoint_gt_even,
                                                 e4, &res, &pfpsf)
                    }
                    
                    // correction needed for tininess detection before rounding
                    if ((((res.hi & 0x7fffffffffffffff) == 0x0000314dc6448d93) &&
                         // 10^33*10^-6176_high
                         (res.lo == 0x38c15b0a00000000)) &&  // 10^33*10^-6176_low
                        (((rnd_mode == BID_ROUNDING_TO_NEAREST ||
                           rnd_mode == BID_ROUNDING_TIES_AWAY) &&
                          (is_midpoint_lt_even || is_inexact_gt_midpoint)) ||
                         ((((rnd_mode == BID_ROUNDING_UP) && !(res.hi & MASK_SIGN != 0)) ||
                           ((rnd_mode == BID_ROUNDING_DOWN) && (res.hi & MASK_SIGN != 0)))
                          && (is_midpoint_lt_even || is_midpoint_gt_even ||
                              is_inexact_lt_midpoint || is_inexact_gt_midpoint)))) {
                        is_tiny = true
                    }
                    
                    if (is_midpoint_lt_even || is_midpoint_gt_even ||
                        is_inexact_lt_midpoint || is_inexact_gt_midpoint) {
                        // set the inexact flag
                        pfpsf.insert(.inexact)
                        if (is_tiny) {
                            pfpsf.insert(.underflow)
                        }
                    }
                    //        ptr_is_midpoint_lt_even = is_midpoint_lt_even;
                    //        ptr_is_midpoint_gt_even = is_midpoint_gt_even;
                    //        ptr_is_inexact_lt_midpoint = is_inexact_lt_midpoint;
                    //        ptr_is_inexact_gt_midpoint = is_inexact_gt_midpoint;
                    BID_SWAP128(&res)
                    return res
                    
                } else if ((p34 <= delta && delta + q3 <= q4) || // Case (15)
                           (delta < p34 && p34 < delta + q3 && delta + q3 <= q4) || //Case (16)
                           (delta + q3 <= p34 && p34 < q4)) { // Case (17)
                    
                    // calculate first the result rounded to the destination precision, with
                    // unbounded exponent
                    
                    bid_add_and_round (q3, q4, e4, delta, p34, z_sign, p_sign, C3, C4,
                                       rnd_mode, &is_midpoint_lt_even,
                                       &is_midpoint_gt_even, &is_inexact_lt_midpoint,
                                       &is_inexact_gt_midpoint, &pfpsf, &res);
                    //        ptr_is_midpoint_lt_even = is_midpoint_lt_even;
                    //        ptr_is_midpoint_gt_even = is_midpoint_gt_even;
                    //        ptr_is_inexact_lt_midpoint = is_inexact_lt_midpoint;
                    //        ptr_is_inexact_gt_midpoint = is_inexact_gt_midpoint;
                    BID_SWAP128(&res)
                    return res
                    
                } else {
                    // nothing
                }
                break // while delta_ge_zero
            } // end if delta < 0
        } // end while delta_ge_zero
        
        //    ptr_is_midpoint_lt_even = is_midpoint_lt_even;
        //    ptr_is_midpoint_gt_even = is_midpoint_gt_even;
        //    ptr_is_inexact_lt_midpoint = is_inexact_lt_midpoint;
        //    ptr_is_inexact_gt_midpoint = is_inexact_gt_midpoint;
        BID_SWAP128(&res)
        return res
    }
    
    // add/subtract C4 and C3 * 10^scale; this may follow a previous rounding, so
    // use the rounding information from ptr_is_* to avoid a double rounding error
    static func bid_add_and_round (_ q3:Int, _ q4:Int, _ e4:Int, _ delta:Int, _ p34:Int,
                                   _ z_sign:UInt64, _ p_sign:UInt64, _ C3:UInt128, _ C4:UInt256, _ rnd_mode:Rounding,
                                   _ ptr_is_midpoint_lt_even:inout Bool, _ ptr_is_midpoint_gt_even:inout Bool,
                                   _ ptr_is_inexact_lt_midpoint:inout Bool, _ ptr_is_inexact_gt_midpoint:inout Bool,
                                   _ ptrfpsf:inout Status, _ res:inout UInt128) {
        
        var scale = 0, x0 = 0, ind = 0, R64 = UInt64(), e4 = e4, p_sign = p_sign
        var P128 = UInt128(), R128 = UInt128(), P192 = UInt192(), R192 = UInt192(), R256 = UInt256()
        var is_midpoint_lt_even = false, is_midpoint_gt_even = false, is_inexact_lt_midpoint = false
        var is_inexact_gt_midpoint = false, is_midpoint_lt_even0 = false, is_midpoint_gt_even0 = false
        var is_inexact_lt_midpoint0 = false, is_inexact_gt_midpoint0 = false, incr_exp = 0
        var is_tiny = false, lt_half_ulp = false, eq_half_ulp = false
        
        // scale C3 up by 10^(q4-delta-q3), 0 <= q4-delta-q3 <= 2*P34-2 = 66
        scale = q4 - delta - q3; // 0 <= scale <= 66 (or 0 <= scale <= 68 if this
        // comes from Cases (2), (3), (4), (5), (6), with 0 <= |delta| <= 1
        
        // calculate C3 * 10^scale in R256 (it has at most 67 decimal digits for
        // Cases (15),(16),(17) and at most 69 for Cases (2),(3),(4),(5),(6))
        if (scale == 0) {
            R256.w[3] = 0x0
            R256.w[2] = 0x0
            R256.w[1] = C3.hi;
            R256.w[0] = C3.lo;
        } else if (scale <= 19) { // 10^scale fits in 64 bits
            P128.hi = 0;
            P128.lo = bid_ten2k64[scale];
            __mul_128x128_to_256(&R256, P128, C3);
        } else if (scale <= 38) { // 10^scale fits in 128 bits
            __mul_128x128_to_256(&R256, bid_ten2k128[scale - 20], C3);
        } else if (scale <= 57) { // 39 <= scale <= 57
            // 10^scale fits in 192 bits but C3 * 10^scale fits in 223 or 230 bits
            // (10^67 has 223 bits; 10^69 has 230 bits);
            // must split the computation:
            // 10^scale * C3 = 10*38 * 10^(scale-38) * C3 where 10^38 takes 127
            // bits and so 10^(scale-38) * C3 fits in 128 bits with certainty
            // Note that 1 <= scale - 38 <= 19 => 10^(scale-38) fits in 64 bits
            __mul_64x128_to_128(&R128, bid_ten2k64[scale - 38], C3);
            // now multiply R128 by 10^38
            __mul_128x128_to_256(&R256, R128, bid_ten2k128[18]);
        } else { // 58 <= scale <= 66
            // 10^scale takes between 193 and 220 bits,
            // and C3 * 10^scale fits in 223 bits (10^67/10^69 has 223/230 bits)
            // must split the computation:
            // 10^scale * C3 = 10*38 * 10^(scale-38) * C3 where 10^38 takes 127
            // bits and so 10^(scale-38) * C3 fits in 128 bits with certainty
            // Note that 20 <= scale - 38 <= 30 => 10^(scale-38) fits in 128 bits
            // Calculate first 10^(scale-38) * C3, which fits in 128 bits; because
            // 10^(scale-38) takes more than 64 bits, C3 will take less than 64
            __mul_64x128_to_128(&R128, C3.lo, bid_ten2k128[scale - 58]);
            // now calculate 10*38 * 10^(scale-38) * C3
            __mul_128x128_to_256(&R256, R128, bid_ten2k128[18]);
        }
        // C3 * 10^scale is now in R256
        
        // for Cases (15), (16), (17) C4 > C3 * 10^scale because C4 has at least
        // one extra digit; for Cases (2), (3), (4), (5), or (6) any order is
        // possible
        // add/subtract C4 and C3 * 10^scale; the exponent is e4
        if (p_sign == z_sign) { // R256 = C4 + R256
            // calculate R256 = C4 + C3 * 10^scale = C4 + R256 which is exact,
            // but may require rounding
            bid_add256(C4, R256, &R256);
        } else { // if (p_sign != z_sign) { // R256 = C4 - R256
            // calculate R256 = C4 - C3 * 10^scale = C4 - R256 or
            // R256 = C3 * 10^scale - C4 = R256 - C4 which is exact,
            // but may require rounding
            
            // compare first R256 = C3 * 10^scale and C4
            if (R256.w[3] > C4.w[3] || (R256.w[3] == C4.w[3] && R256.w[2] > C4.w[2]) ||
                (R256.w[3] == C4.w[3] && R256.w[2] == C4.w[2] && R256.w[1] > C4.w[1]) ||
                (R256.w[3] == C4.w[3] && R256.w[2] == C4.w[2] && R256.w[1] == C4.w[1] &&
                 R256.w[0] >= C4.w[0])) { // C3 * 10^scale >= C4
                // calculate R256 = C3 * 10^scale - C4 = R256 - C4, which is exact,
                // but may require rounding
                bid_sub256(R256, C4, &R256);
                // flip p_sign too, because the result has the sign of z
                p_sign = z_sign;
            } else { // if C4 > C3 * 10^scale
                // calculate R256 = C4 - C3 * 10^scale = C4 - R256, which is exact,
                // but may require rounding
                bid_sub256(C4, R256, &R256);
            }
            // if the result is pure zero, the sign depends on the rounding mode
            // (x*y and z had opposite signs)
            if (R256.w[3] == 0x0 && R256.w[2] == 0x0 && R256.w[1] == 0x0 && R256.w[0] == 0x0) {
                if (rnd_mode != BID_ROUNDING_DOWN) {
                    p_sign = 0x0000000000000000
                } else {
                    p_sign = 0x8000000000000000
                }
                // the exponent is max (e4, expmin)
                if (e4 < -6176) {
                    e4 = expmin;
                }
                // assemble result
                res.hi = p_sign | (UInt64(e4 + 6176) << 49);
                res.lo = 0x0;
                return
            }
        }
        
        // determine the number of decimal digits in R256
        ind = bid_bid_nr_digits256(R256);
        
        // the exact result is (-1)^p_sign * R256 * 10^e4 where q (R256) = ind;
        // round to the destination precision, with unbounded exponent
        
        if (ind <= p34) {
            // result rounded to the destination precision with unbounded exponent
            // is exact
            if (ind + e4 < p34 + expmin) {
                is_tiny = true // applies to all rounding modes
                // (regardless of the tininess detection method)
            }
            res.hi = p_sign | (UInt64(e4 + 6176) << 49) | R256.w[1];
            res.lo = R256.w[0];
            // Note: res is correct only if expmin <= e4 <= expmax
        } else { // if (ind > p34)
            // if more than P digits, round to nearest to P digits
            // round R256 to p34 digits
            x0 = ind - p34; // 1 <= x0 <= 34 as 35 <= ind <= 68
            if (ind <= 38) {
                P128.hi = R256.w[1]
                P128.lo = R256.w[0]
                bid_round128_19_38 (ind, x0, P128, &R128, &incr_exp,
                                    &is_midpoint_lt_even, &is_midpoint_gt_even,
                                    &is_inexact_lt_midpoint, &is_inexact_gt_midpoint);
            } else if (ind <= 57) {
                P192.w[2] = R256.w[2];
                P192.w[1] = R256.w[1];
                P192.w[0] = R256.w[0];
                bid_round192_39_57 (ind, x0, P192, &R192, &incr_exp,
                                    &is_midpoint_lt_even, &is_midpoint_gt_even,
                                    &is_inexact_lt_midpoint, &is_inexact_gt_midpoint);
                R128.hi = R192.w[1];
                R128.lo = R192.w[0];
            } else { // if (ind <= 68)
                bid_round256_58_76 (ind, x0, R256, &R256, &incr_exp,
                                    &is_midpoint_lt_even, &is_midpoint_gt_even,
                                    &is_inexact_lt_midpoint, &is_inexact_gt_midpoint);
                R128.hi = R256.w[1];
                R128.lo = R256.w[0];
            }
            
            // the rounded result has p34 = 34 digits
            e4 = e4 + x0 + incr_exp;
            if (rnd_mode == BID_ROUNDING_TO_NEAREST) {
                if (e4 < expmin) {
                    is_tiny = true // for other rounding modes apply correction
                }
            } else {
                // for RM, RP, RZ, RA apply correction in order to determine tininess
                // but do not save the result; apply the correction to
                // (-1)^p_sign * significand * 10^0
                P128.hi = p_sign | 0x3040000000000000 | R128.hi;
                P128.lo = R128.lo;
                bid_rounding_correction (rnd_mode,
                                         is_inexact_lt_midpoint,
                                         is_inexact_gt_midpoint, is_midpoint_lt_even,
                                         is_midpoint_gt_even, 0, &P128, &ptrfpsf);
                scale = Int((P128.hi & MASK_EXP) >> 49) - 6176; // -1, 0, or +1
                // the number of digits in the significand is p34 = 34
                if (e4 + scale < expmin) {
                    is_tiny = true
                }
            }
            ind = p34; // the number of decimal digits in the signifcand of res
            res.hi = p_sign | (UInt64(e4 + 6176) << 49) | R128.hi; // RN
            res.lo = R128.lo;
            // Note: res is correct only if expmin <= e4 <= expmax
            // set the inexact flag after rounding with bounded exponent, if any
        }
        // at this point we have the result rounded with unbounded exponent in
        // res and we know its tininess:
        // res = (-1)^p_sign * significand * 10^e4,
        // where q (significand) = ind <= p34
        // Note: res is correct only if expmin <= e4 <= expmax
        
        // check for overflow if RN
        if (rnd_mode == BID_ROUNDING_TO_NEAREST && (ind + e4) > (p34 + expmax)) {
            res.hi = p_sign | 0x7800000000000000
            res.lo = 0x0000000000000000
            ptrfpsf.formUnion([.inexact, .overflow])
            return // BID_RETURN (res)
        } // else not overflow or not RN, so continue
        
        // if (e4 >= expmin) we have the result rounded with bounded exponent
        if (e4 < expmin) {
            x0 = expmin - e4; // x0 >= 1; the number of digits to chop off of res
            // where the result rounded [at most] once is
            //   (-1)^p_sign * significand_res * 10^e4
            
            // avoid double rounding error
            is_inexact_lt_midpoint0 = is_inexact_lt_midpoint;
            is_inexact_gt_midpoint0 = is_inexact_gt_midpoint;
            is_midpoint_lt_even0 = is_midpoint_lt_even;
            is_midpoint_gt_even0 = is_midpoint_gt_even;
            is_inexact_lt_midpoint = false
            is_inexact_gt_midpoint = false
            is_midpoint_lt_even = false
            is_midpoint_gt_even = false
            
            if (x0 > ind) {
                // nothing is left of res when moving the decimal point left x0 digits
                is_inexact_lt_midpoint = true
                res.hi = p_sign | 0x0000000000000000
                res.lo = 0x0000000000000000
                e4 = expmin;
            } else if (x0 == ind) { // 1 <= x0 = ind <= p34 = 34
                // this is <, =, or > 1/2 ulp
                // compare the ind-digit value in the significand of res with
                // 1/2 ulp = 5*10^(ind-1), i.e. determine whether it is
                // less than, equal to, or greater than 1/2 ulp (significand of res)
                R128.hi = res.hi & MASK_COEFF;
                R128.lo = res.lo;
                if (ind <= 19) {
                    if (R128.lo < bid_midpoint64[ind - 1]) { // < 1/2 ulp
                        lt_half_ulp = true
                        is_inexact_lt_midpoint = true
                    } else if (R128.lo == bid_midpoint64[ind - 1]) { // = 1/2 ulp
                        eq_half_ulp = true
                        is_midpoint_gt_even = true
                    } else { // > 1/2 ulp
                        // gt_half_ulp = true
                        is_inexact_gt_midpoint = true
                    }
                } else { // if (ind <= 38) {
                    if (R128.hi < bid_midpoint128[ind - 20].hi ||
                        (R128.hi == bid_midpoint128[ind - 20].hi &&
                         R128.lo < bid_midpoint128[ind - 20].lo)) { // < 1/2 ulp
                        lt_half_ulp = true
                        is_inexact_lt_midpoint = true
                    } else if (R128.hi == bid_midpoint128[ind - 20].hi &&
                               R128.lo == bid_midpoint128[ind - 20].lo) { // = 1/2 ulp
                        eq_half_ulp = true
                        is_midpoint_gt_even = true
                    } else { // > 1/2 ulp
                        // gt_half_ulp = true
                        is_inexact_gt_midpoint = true
                    }
                }
                if (lt_half_ulp || eq_half_ulp) {
                    // res = +0.0 * 10^expmin
                    res.hi = 0x0000000000000000
                    res.lo = 0x0000000000000000
                } else { // if (gt_half_ulp)
                    // res = +1 * 10^expmin
                    res.hi = 0x0000000000000000
                    res.lo = 0x0000000000000001
                }
                res.hi = p_sign | res.hi;
                e4 = expmin;
            } else { // if (1 <= x0 <= ind - 1 <= 33)
                // round the ind-digit result to ind - x0 digits
                
                if (ind <= 18) { // 2 <= ind <= 18
                    bid_round64_2_18 (ind, x0, res.lo, &R64, &incr_exp,
                                      &is_midpoint_lt_even, &is_midpoint_gt_even,
                                      &is_inexact_lt_midpoint, &is_inexact_gt_midpoint);
                    res.hi = 0x0;
                    res.lo = R64;
                } else if (ind <= 38) {
                    P128.hi = res.hi & MASK_COEFF;
                    P128.lo = res.lo;
                    bid_round128_19_38 (ind, x0, P128, &res, &incr_exp,
                                        &is_midpoint_lt_even, &is_midpoint_gt_even,
                                        &is_inexact_lt_midpoint,
                                        &is_inexact_gt_midpoint);
                }
                e4 = e4 + x0; // expmin
                // we want the exponent to be expmin, so if incr_exp = 1 then
                // multiply the rounded result by 10 - it will still fit in 113 bits
                if incr_exp != 0 {
                    // 64 x 128 -> 128
                    P128.hi = res.hi & MASK_COEFF;
                    P128.lo = res.lo;
                    __mul_64x128_to_128(&res, bid_ten2k64[1], P128);
                }
                res.hi =
                p_sign | (UInt64(e4 + 6176) << 49) | (res.hi & MASK_COEFF);
                // avoid a double rounding error
                if ((is_inexact_gt_midpoint0 || is_midpoint_lt_even0) &&
                    is_midpoint_lt_even) { // double rounding error upward
                    // res = res - 1
                    res.lo-=1
                    if (res.lo == 0xffffffffffffffff) {
                        res.hi-=1
                    }
                    // Note: a double rounding error upward is not possible; for this
                    // the result after the first rounding would have to be 99...95
                    // (35 digits in all), possibly followed by a number of zeros; this
                    // is not possible in Cases (2)-(6) or (15)-(17) which may get here
                    is_midpoint_lt_even = false
                    is_inexact_lt_midpoint = true
                } else if ((is_inexact_lt_midpoint0 || is_midpoint_gt_even0) &&
                           is_midpoint_gt_even) { // double rounding error downward
                    // res = res + 1
                    res.lo+=1
                    if (res.lo == 0) {
                        res.hi+=1
                    }
                    is_midpoint_gt_even = false
                    is_inexact_gt_midpoint = true
                } else if (!is_midpoint_lt_even && !is_midpoint_gt_even &&
                           !is_inexact_lt_midpoint && !is_inexact_gt_midpoint) {
                    // if this second rounding was exact the result may still be
                    // inexact because of the first rounding
                    if (is_inexact_gt_midpoint0 || is_midpoint_lt_even0) {
                        is_inexact_gt_midpoint = true
                    }
                    if (is_inexact_lt_midpoint0 || is_midpoint_gt_even0) {
                        is_inexact_lt_midpoint = true
                    }
                } else if (is_midpoint_gt_even &&
                           (is_inexact_gt_midpoint0 || is_midpoint_lt_even0)) {
                    // pulled up to a midpoint
                    is_inexact_lt_midpoint = true
                    is_inexact_gt_midpoint = false
                    is_midpoint_lt_even = false
                    is_midpoint_gt_even = false
                } else if (is_midpoint_lt_even && (is_inexact_lt_midpoint0 || is_midpoint_gt_even0)) {
                    // pulled down to a midpoint
                    is_inexact_lt_midpoint = false
                    is_inexact_gt_midpoint = true
                    is_midpoint_lt_even = false
                    is_midpoint_gt_even = false
                } else {
                    // nothing
                }
            }
        }
        // res contains the correct result
        // apply correction if not rounding to nearest
        if (rnd_mode != BID_ROUNDING_TO_NEAREST) {
            bid_rounding_correction (rnd_mode,
                                     is_inexact_lt_midpoint, is_inexact_gt_midpoint,
                                     is_midpoint_lt_even, is_midpoint_gt_even,
                                     e4, &res, &ptrfpsf);
        }
        if (is_midpoint_lt_even || is_midpoint_gt_even || is_inexact_lt_midpoint || is_inexact_gt_midpoint) {
            // set the inexact flag
            ptrfpsf.insert(.inexact)
            if (is_tiny) {
                ptrfpsf.insert(.underflow)
            }
        }
    }
    
    static func bid_rounding_correction (_ rnd_mode:Rounding, _ is_inexact_lt_midpoint:Bool, _ is_inexact_gt_midpoint:Bool,
                                         _ is_midpoint_lt_even:Bool, _ is_midpoint_gt_even:Bool, _ unbexp:Int, _ res:inout UInt128,
                                         _ ptrfpsf:inout Status) {
        // unbiased true exponent unbexp may be larger than emax
        var unbexp = unbexp
        
        // general correction from RN to RA, RM, RP, RZ
        // Note: if the result is negative, then is_inexact_lt_midpoint,
        // is_inexact_gt_midpoint, is_midpoint_lt_even, and is_midpoint_gt_even
        // have to be considered as if determined for the absolute value of the
        // result (so they seem to be reversed)
        
        if (is_inexact_lt_midpoint || is_inexact_gt_midpoint || is_midpoint_lt_even || is_midpoint_gt_even) {
            ptrfpsf.insert(.inexact)
        }
        // apply correction to result calculated with unbounded exponent
        let sign = res.hi & MASK_SIGN
        var exp = Int(unbexp + 6176) << 49 // valid only if expmin<=unbexp<=expmax
        var C_hi = res.hi & MASK_COEFF
        var C_lo = res.lo
        if ((sign == 0 && ((rnd_mode == BID_ROUNDING_UP && is_inexact_lt_midpoint) ||
                           ((rnd_mode == BID_ROUNDING_TIES_AWAY || rnd_mode == BID_ROUNDING_UP) &&
                            is_midpoint_gt_even))) ||
            (sign != 0 && ((rnd_mode == BID_ROUNDING_DOWN && is_inexact_lt_midpoint) ||
                           ((rnd_mode == BID_ROUNDING_TIES_AWAY || rnd_mode == BID_ROUNDING_DOWN) &&
                            is_midpoint_gt_even)))) {
            // C = C + 1
            C_lo = C_lo + 1;
            if (C_lo == 0) {
                C_hi = C_hi + 1;
            }
            if (C_hi == 0x0001ed09bead87c0 && C_lo == 0x378d8e6400000000) {
                // C = 10^34 => rounding overflow
                C_hi = 0x0000314dc6448d93;
                C_lo = 0x38c15b0a00000000; // 10^33
                // exp = exp + EXP_P1;
                unbexp = unbexp + 1;
                exp = Int(unbexp + 6176) << 49;
            }
        } else if ((is_midpoint_lt_even || is_inexact_gt_midpoint) &&
                   ((sign != 0 && (rnd_mode == BID_ROUNDING_UP || rnd_mode == BID_ROUNDING_TO_ZERO)) ||
                    (sign == 0 && (rnd_mode == BID_ROUNDING_DOWN || rnd_mode == BID_ROUNDING_TO_ZERO)))) {
            // C = C - 1
            C_lo = C_lo - 1;
            if (C_lo == 0xffffffffffffffff) {
                C_hi-=1
            }
            // check if we crossed into the lower decade
            if (C_hi == 0x0000314dc6448d93 && C_lo == 0x38c15b09ffffffff) {
                // C = 10^33 - 1
                if (exp > 0) {
                    C_hi = 0x0001ed09bead87c0; // 10^34 - 1
                    C_lo = 0x378d8e63ffffffff;
                    // exp = exp - EXP_P1;
                    unbexp = unbexp - 1;
                    exp = Int(unbexp + 6176) << 49;
                } else { // if exp = 0 the result is tiny & inexact
                    ptrfpsf.insert(.underflow)
                }
            }
        } else {
            // the result is already correct
        }
        if (unbexp > expmax) { // 6111
            ptrfpsf.formUnion([.inexact, .overflow])
            exp = 0;
            if sign == 0 { // result is positive
                if (rnd_mode == BID_ROUNDING_UP || rnd_mode == BID_ROUNDING_TIES_AWAY) { // +inf
                    C_hi = 0x7800000000000000;
                    C_lo = 0x0000000000000000;
                } else { // res = +MAXFP = (10^34-1) * 10^emax
                    C_hi = 0x5fffed09bead87c0;
                    C_lo = 0x378d8e63ffffffff;
                }
            } else { // result is negative
                if (rnd_mode == BID_ROUNDING_DOWN || rnd_mode == BID_ROUNDING_TIES_AWAY) { // -inf
                    C_hi = 0xf800000000000000;
                    C_lo = 0x0000000000000000;
                } else { // res = -MAXFP = -(10^34-1) * 10^emax
                    C_hi = 0xdfffed09bead87c0;
                    C_lo = 0x378d8e63ffffffff;
                }
            }
        }
        // assemble the result
        res.hi = sign | UInt64(exp) | C_hi;
        res.lo = C_lo;
    }
    
    static func bid_round64_2_18 (_ q:Int, _ x:Int, _ C:UInt64, _ ptr_Cstar:inout UInt64, _ incr_exp:inout Int,
                                  _ ptr_is_midpoint_lt_even:inout Bool, _ ptr_is_midpoint_gt_even:inout Bool,
                                  _ ptr_is_inexact_lt_midpoint:inout Bool, _ ptr_is_inexact_gt_midpoint:inout Bool) {
        var P128 = UInt128(), fstar = UInt128(), Cstar = UInt64()
        
        // Note:
        //    In round128_2_18() positive numbers with 2 <= q <= 18 will be
        //    rounded to nearest only for 1 <= x <= 3:
        //     x = 1 or x = 2 when q = 17
        //     x = 2 or x = 3 when q = 18
        // However, for generality and possible uses outside the frame of IEEE 754
        // this implementation works for 1 <= x <= q - 1
        
        // assume ptr_is_midpoint_lt_even, ptr_is_midpoint_gt_even,
        // ptr_is_inexact_lt_midpoint, and ptr_is_inexact_gt_midpoint are
        // initialized to 0 by the caller
        
        // round a number C with q decimal digits, 2 <= q <= 18
        // to q - x digits, 1 <= x <= 17
        // C = C + 1/2 * 10^x where the result C fits in 64 bits
        // (because the largest value is 999999999999999999 + 50000000000000000 =
        // 0x0e92596fd628ffff, which fits in 60 bits)
        var ind = x - 1;    // 0 <= ind <= 16
        let C = C + bid_midpoint64[ind];
        // kx ~= 10^(-x), kx = bid_Kx64[ind] * 2^(-Ex), 0 <= ind <= 16
        // P128 = (C + 1/2 * 10^x) * kx * 2^Ex = (C + 1/2 * 10^x) * Kx
        // the approximation kx of 10^(-x) was rounded up to 64 bits
        __mul_64x64_to_128MACH(&P128, C, bid_Kx64[ind]);
        // calculate C* = floor (P128) and f*
        // Cstar = P128 >> Ex
        // fstar = low Ex bits of P128
        let shift = bid_Ex64m64[ind];    // in [3, 56]
        Cstar = P128.hi >> shift;
        fstar.hi = P128.hi & bid_mask64[ind];
        fstar.lo = P128.lo
        // the top Ex bits of 10^(-x) are T* = bid_ten2mxtrunc64[ind], e.g.
        // if x=1, T*=bid_ten2mxtrunc64[0]=0xcccccccccccccccc
        // if (0 < f* < 10^(-x)) then the result is a midpoint
        //   if floor(C*) is even then C* = floor(C*) - logical right
        //       shift; C* has q - x decimal digits, correct by Prop. 1)
        //   else if floor(C*) is odd C* = floor(C*)-1 (logical right
        //       shift; C* has q - x decimal digits, correct by Pr. 1)
        // else
        //   C* = floor(C*) (logical right shift; C has q - x decimal digits,
        //       correct by Property 1)
        // in the caling function n = C* * 10^(e+x)
        
        // determine inexactness of the rounding of C*
        // if (0 < f* - 1/2 < 10^(-x)) then
        //   the result is exact
        // else // if (f* - 1/2 > T*) then
        //   the result is inexact
        if (fstar.hi > bid_half64[ind] ||
            (fstar.hi == bid_half64[ind] && fstar.lo != 0)) {
            // f* > 1/2 and the result may be exact
            // Calculate f* - 1/2
            let tmp64 = fstar.hi - bid_half64[ind];
            if (tmp64 != 0 || fstar.lo > bid_ten2mxtrunc64[ind]) {    // f* - 1/2 > 10^(-x)
                ptr_is_inexact_lt_midpoint = true
            }    // else the result is exact
        } else {    // the result is inexact; f2* <= 1/2
            ptr_is_inexact_gt_midpoint = true
        }
        // check for midpoints (could do this before determining inexactness)
        if (fstar.hi == 0 && fstar.lo <= bid_ten2mxtrunc64[ind]) {
            // the result is a midpoint
            if (Cstar & 0x01 != 0) {    // Cstar is odd; MP in [EVEN, ODD]
                // if floor(C*) is odd C = floor(C*) - 1; the result may be 0
                Cstar-=1    // Cstar is now even
                ptr_is_midpoint_gt_even = true
                ptr_is_inexact_lt_midpoint = false
                ptr_is_inexact_gt_midpoint = false
            } else {    // else MP in [ODD, EVEN]
                ptr_is_midpoint_lt_even = true
                ptr_is_inexact_lt_midpoint = false
                ptr_is_inexact_gt_midpoint = false
            }
        }
        // check for rounding overflow, which occurs if Cstar = 10^(q-x)
        ind = q - x;    // 1 <= ind <= q - 1
        if (Cstar == bid_ten2k64[ind]) {    // if  Cstar = 10^(q-x)
            Cstar = bid_ten2k64[ind - 1];    // Cstar = 10^(q-x-1)
            incr_exp = 1;
        } else {    // 10^33 <= Cstar <= 10^34 - 1
            incr_exp = 0;
        }
        ptr_Cstar = Cstar;
    }
    
    static func bid_round128_19_38 (_ q:Int, _ x:Int, _ C:UInt128, _ ptr_Cstar:inout UInt128, _ incr_exp:inout Int,
                                    _ ptr_is_midpoint_lt_even:inout Bool, _ ptr_is_midpoint_gt_even:inout Bool,
                                    _ ptr_is_inexact_lt_midpoint:inout Bool, _ ptr_is_inexact_gt_midpoint:inout Bool) {
        var P256 = UInt256(), fstar = UInt256(), Cstar = UInt128(), C = C
        // Note:
        //    In bid_round128_19_38() positive numbers with 19 <= q <= 38 will be
        //    rounded to nearest only for 1 <= x <= 23:
        //     x = 3 or x = 4 when q = 19
        //     x = 4 or x = 5 when q = 20
        //     ...
        //     x = 18 or x = 19 when q = 34
        //     x = 1 or x = 2 or x = 19 or x = 20 when q = 35
        //     x = 2 or x = 3 or x = 20 or x = 21 when q = 36
        //     x = 3 or x = 4 or x = 21 or x = 22 when q = 37
        //     x = 4 or x = 5 or x = 22 or x = 23 when q = 38
        // However, for generality and possible uses outside the frame of IEEE 754
        // this implementation works for 1 <= x <= q - 1
        
        // assume ptr_is_midpoint_lt_even, ptr_is_midpoint_gt_even,
        // ptr_is_inexact_lt_midpoint, and ptr_is_inexact_gt_midpoint are
        // initialized to 0 by the caller
        
        // round a number C with q decimal digits, 19 <= q <= 38
        // to q - x digits, 1 <= x <= 37
        // C = C + 1/2 * 10^x where the result C fits in 128 bits
        // (because the largest value is 99999999999999999999999999999999999999 +
        // 5000000000000000000000000000000000000 =
        // 0x4efe43b0c573e7e68a043d8fffffffff, which fits is 127 bits)
        var ind = x - 1;    // 0 <= ind <= 36
        if (ind <= 18) {    // if 0 <= ind <= 18
            let tmp64 = C.lo;
            C.lo = C.lo + bid_midpoint64[ind];
            if (C.lo < tmp64) { C.hi+=1 }
        } else {    // if 19 <= ind <= 37
            let tmp64 = C.lo;
            C.lo = C.lo + bid_midpoint128[ind - 19].lo;
            if (C.lo < tmp64) { C.hi+=1 }
            C.hi = C.hi + bid_midpoint128[ind - 19].hi;
        }
        // kx ~= 10^(-x), kx = bid_Kx128[ind] * 2^(-Ex), 0 <= ind <= 36
        // P256 = (C + 1/2 * 10^x) * kx * 2^Ex = (C + 1/2 * 10^x) * Kx
        // the approximation kx of 10^(-x) was rounded up to 128 bits
        __mul_128x128_to_256(&P256, C, bid_Kx128[ind]);
        // calculate C* = floor (P256) and f*
        // Cstar = P256 >> Ex
        // fstar = low Ex bits of P256
        let shift = bid_Ex128m128[ind];    // in [2, 63] but have to consider two cases
        if (ind <= 18) {    // if 0 <= ind <= 18
            Cstar.lo = (P256.w[2] >> shift) | (P256.w[3] << (64 - shift));
            Cstar.hi = (P256.w[3] >> shift);
            fstar.w[0] = P256.w[0];
            fstar.w[1] = P256.w[1];
            fstar.w[2] = P256.w[2] & bid_mask128[ind];
            fstar.w[3] = 0x0;
        } else {    // if 19 <= ind <= 37
            Cstar.lo = P256.w[3] >> shift;
            Cstar.hi = 0x0;
            fstar.w[0] = P256.w[0];
            fstar.w[1] = P256.w[1];
            fstar.w[2] = P256.w[2];
            fstar.w[3] = P256.w[3] & bid_mask128[ind];
        }
        // the top Ex bits of 10^(-x) are T* = bid_ten2mxtrunc64[ind], e.g.
        // if x=1, T*=bid_ten2mxtrunc128[0]=0xcccccccccccccccccccccccccccccccc
        // if (0 < f* < 10^(-x)) then the result is a midpoint
        //   if floor(C*) is even then C* = floor(C*) - logical right
        //       shift; C* has q - x decimal digits, correct by Prop. 1)
        //   else if floor(C*) is odd C* = floor(C*)-1 (logical right
        //       shift; C* has q - x decimal digits, correct by Pr. 1)
        // else
        //   C* = floor(C*) (logical right shift; C has q - x decimal digits,
        //       correct by Property 1)
        // in the caling function n = C* * 10^(e+x)
        
        // determine inexactness of the rounding of C*
        // if (0 < f* - 1/2 < 10^(-x)) then
        //   the result is exact
        // else // if (f* - 1/2 > T*) then
        //   the result is inexact
        if (ind <= 18) {    // if 0 <= ind <= 18
            if (fstar.w[2] > bid_half128[ind] || (fstar.w[2] == bid_half128[ind] && (fstar.w[1] != 0 || fstar.w[0] != 0))) {
                // f* > 1/2 and the result may be exact
                // Calculate f* - 1/2
                let tmp64 = fstar.w[2] - bid_half128[ind];
                if (tmp64 != 0 || fstar.w[1] > bid_ten2mxtrunc128[ind].hi ||
                    (fstar.w[1] == bid_ten2mxtrunc128[ind].hi && fstar.w[0] > bid_ten2mxtrunc128[ind].lo)) {    // f* - 1/2 > 10^(-x)
                    ptr_is_inexact_lt_midpoint = true
                }    // else the result is exact
            } else {    // the result is inexact; f2* <= 1/2
                ptr_is_inexact_gt_midpoint = true
            }
        } else {    // if 19 <= ind <= 37
            if (fstar.w[3] > bid_half128[ind] || (fstar.w[3] == bid_half128[ind] &&
                                                  (fstar.w[2] != 0 || fstar.w[1] != 0 || fstar.w[0] != 0))) {
                // f* > 1/2 and the result may be exact
                // Calculate f* - 1/2
                let tmp64 = fstar.w[3] - bid_half128[ind];
                if (tmp64 != 0 || fstar.w[2] != 0 || fstar.w[1] > bid_ten2mxtrunc128[ind].hi || (fstar.w[1] == bid_ten2mxtrunc128[ind].hi && fstar.w[0] > bid_ten2mxtrunc128[ind].lo)) {    // f* - 1/2 > 10^(-x)
                    ptr_is_inexact_lt_midpoint = true
                }    // else the result is exact
            } else {    // the result is inexact; f2* <= 1/2
                ptr_is_inexact_gt_midpoint = true
            }
        }
        // check for midpoints (could do this before determining inexactness)
        if (fstar.w[3] == 0 && fstar.w[2] == 0 &&
            (fstar.w[1] < bid_ten2mxtrunc128[ind].hi ||
             (fstar.w[1] == bid_ten2mxtrunc128[ind].hi &&
              fstar.w[0] <= bid_ten2mxtrunc128[ind].lo))) {
            // the result is a midpoint
            if (Cstar.lo & 0x01 != 0) {    // Cstar is odd; MP in [EVEN, ODD]
                // if floor(C*) is odd C = floor(C*) - 1; the result may be 0
                Cstar.lo-=1    // Cstar is now even
                if Cstar.lo == 0xffffffffffffffff { Cstar.hi-=1 }
                ptr_is_midpoint_gt_even = true
                ptr_is_inexact_lt_midpoint = false
                ptr_is_inexact_gt_midpoint = false
            } else {    // else MP in [ODD, EVEN]
                ptr_is_midpoint_lt_even = true
                ptr_is_inexact_lt_midpoint = false
                ptr_is_inexact_gt_midpoint = false
            }
        }
        // check for rounding overflow, which occurs if Cstar = 10^(q-x)
        ind = q - x;    // 1 <= ind <= q - 1
        if (ind <= 19) {
            if (Cstar.hi == 0x0 && Cstar.lo == bid_ten2k64[ind]) {
                // if  Cstar = 10^(q-x)
                Cstar.lo = bid_ten2k64[ind - 1];    // Cstar = 10^(q-x-1)
                incr_exp = 1;
            } else {
                incr_exp = 0;
            }
        } else if (ind == 20) {
            // if ind = 20
            if (Cstar.hi == bid_ten2k128[0].hi && Cstar.lo == bid_ten2k128[0].lo) {
                // if  Cstar = 10^(q-x)
                Cstar.lo = bid_ten2k64[19];    // Cstar = 10^(q-x-1)
                Cstar.hi = 0x0;
                incr_exp = 1;
            } else {
                incr_exp = 0;
            }
        } else {    // if 21 <= ind <= 37
            if (Cstar.hi == bid_ten2k128[ind - 20].hi && Cstar.lo == bid_ten2k128[ind - 20].lo) {
                // if  Cstar = 10^(q-x)
                Cstar.lo = bid_ten2k128[ind - 21].lo;    // Cstar = 10^(q-x-1)
                Cstar.hi = bid_ten2k128[ind - 21].hi;
                incr_exp = 1;
            } else {
                incr_exp = 0;
            }
        }
        ptr_Cstar = Cstar
    }
    
    static func bid_round192_39_57 (_ q:Int, _ x:Int, _ C:UInt192, _ ptr_Cstar:inout UInt192, _ incr_exp:inout Int,
                                    _ ptr_is_midpoint_lt_even:inout Bool, _ ptr_is_midpoint_gt_even:inout Bool,
                                    _ ptr_is_inexact_lt_midpoint:inout Bool, _ ptr_is_inexact_gt_midpoint:inout Bool) {
        var Cstar = UInt192(), P384 = UInt384(), fstar = UInt384()
        var tmp64:UInt64, C = C
        
        // Note:
        //    In bid_round192_39_57() positive numbers with 39 <= q <= 57 will be
        //    rounded to nearest only for 5 <= x <= 42:
        //     x = 23 or x = 24 or x = 5 or x = 6 when q = 39
        //     x = 24 or x = 25 or x = 6 or x = 7 when q = 40
        //     ...
        //     x = 41 or x = 42 or x = 23 or x = 24 when q = 57
        // However, for generality and possible uses outside the frame of IEEE 754
        // this implementation works for 1 <= x <= q - 1
        
        // assume ptr_is_midpoint_lt_even, ptr_is_midpoint_gt_even,
        // ptr_is_inexact_lt_midpoint, and ptr_is_inexact_gt_midpoint are
        // initialized to 0 by the caller
        
        // round a number C with q decimal digits, 39 <= q <= 57
        // to q - x digits, 1 <= x <= 56
        // C = C + 1/2 * 10^x where the result C fits in 192 bits
        // (because the largest value is
        // 999999999999999999999999999999999999999999999999999999999 +
        //  50000000000000000000000000000000000000000000000000000000 =
        // 0x2ad282f212a1da846afdaf18c034ff09da7fffffffffffff, which fits in 190 bits)
        var ind = x - 1;    // 0 <= ind <= 55
        if (ind <= 18) {    // if 0 <= ind <= 18
            tmp64 = C.w[0];
            C.w[0] = C.w[0] + bid_midpoint64[ind];
            if (C.w[0] < tmp64) {
                C.w[1]+=1
                if (C.w[1] == 0x0) {
                    C.w[2]+=1
                }
            }
        } else if (ind <= 37) {    // if 19 <= ind <= 37
            tmp64 = C.w[0];
            C.w[0] = C.w[0] + bid_midpoint128[ind - 19].lo
            if (C.w[0] < tmp64) {
                C.w[1]+=1
                if (C.w[1] == 0x0) {
                    C.w[2]+=1
                }
            }
            tmp64 = C.w[1];
            C.w[1] = C.w[1] + bid_midpoint128[ind - 19].hi
            if (C.w[1] < tmp64) {
                C.w[2]+=1
            }
        } else {    // if 38 <= ind <= 57 (actually ind <= 55)
            tmp64 = C.w[0];
            C.w[0] = C.w[0] + bid_midpoint192[ind - 38].w[0];
            if (C.w[0] < tmp64) {
                C.w[1]+=1
                if (C.w[1] == 0x0) {
                    C.w[2]+=1
                }
            }
            tmp64 = C.w[1];
            C.w[1] = C.w[1] + bid_midpoint192[ind - 38].w[1];
            if (C.w[1] < tmp64) {
                C.w[2]+=1
            }
            C.w[2] = C.w[2] + bid_midpoint192[ind - 38].w[2];
        }
        // kx ~= 10^(-x), kx = bid_Kx192[ind] * 2^(-Ex), 0 <= ind <= 55
        // P384 = (C + 1/2 * 10^x) * kx * 2^Ex = (C + 1/2 * 10^x) * Kx
        // the approximation kx of 10^(-x) was rounded up to 192 bits
        __mul_192x192_to_384(&P384, C, bid_Kx192[ind]);
        // calculate C* = floor (P384) and f*
        // Cstar = P384 >> Ex
        // fstar = low Ex bits of P384
        let shift = bid_Ex192m192[ind];    // in [1, 63] but have to consider three cases
        if (ind <= 18) {    // if 0 <= ind <= 18
            Cstar.w[2] = (P384.w[5] >> shift);
            Cstar.w[1] = (P384.w[5] << (64 - shift)) | (P384.w[4] >> shift);
            Cstar.w[0] = (P384.w[4] << (64 - shift)) | (P384.w[3] >> shift);
            fstar.w[5] = 0x0;
            fstar.w[4] = 0x0;
            fstar.w[3] = P384.w[3] & bid_mask192[ind];
            fstar.w[2] = P384.w[2];
            fstar.w[1] = P384.w[1];
            fstar.w[0] = P384.w[0];
        } else if (ind <= 37) {    // if 19 <= ind <= 37
            Cstar.w[2] = 0x0;
            Cstar.w[1] = P384.w[5] >> shift;
            Cstar.w[0] = (P384.w[5] << (64 - shift)) | (P384.w[4] >> shift);
            fstar.w[5] = 0x0;
            fstar.w[4] = P384.w[4] & bid_mask192[ind];
            fstar.w[3] = P384.w[3];
            fstar.w[2] = P384.w[2];
            fstar.w[1] = P384.w[1];
            fstar.w[0] = P384.w[0];
        } else {    // if 38 <= ind <= 57
            Cstar.w[2] = 0x0;
            Cstar.w[1] = 0x0;
            Cstar.w[0] = P384.w[5] >> shift;
            fstar.w[5] = P384.w[5] & bid_mask192[ind];
            fstar.w[4] = P384.w[4];
            fstar.w[3] = P384.w[3];
            fstar.w[2] = P384.w[2];
            fstar.w[1] = P384.w[1];
            fstar.w[0] = P384.w[0];
        }
        
        // the top Ex bits of 10^(-x) are T* = bid_ten2mxtrunc192[ind], e.g. if x=1,
        // T*=bid_ten2mxtrunc192[0]=0xcccccccccccccccccccccccccccccccccccccccccccccccc
        // if (0 < f* < 10^(-x)) then the result is a midpoint
        //   if floor(C*) is even then C* = floor(C*) - logical right
        //       shift; C* has q - x decimal digits, correct by Prop. 1)
        //   else if floor(C*) is odd C* = floor(C*)-1 (logical right
        //       shift; C* has q - x decimal digits, correct by Pr. 1)
        // else
        //   C* = floor(C*) (logical right shift; C has q - x decimal digits,
        //       correct by Property 1)
        // in the caling function n = C* * 10^(e+x)
        
        // determine inexactness of the rounding of C*
        // if (0 < f* - 1/2 < 10^(-x)) then
        //   the result is exact
        // else // if (f* - 1/2 > T*) then
        //   the result is inexact
        if (ind <= 18) {    // if 0 <= ind <= 18
            if (fstar.w[3] > bid_half192[ind] || (fstar.w[3] == bid_half192[ind] &&
                                                  (fstar.w[2] != 0 || fstar.w[1] != 0 || fstar.w[0] != 0))) {
                // f* > 1/2 and the result may be exact
                // Calculate f* - 1/2
                tmp64 = fstar.w[3] - bid_half192[ind];
                if (tmp64 != 0 || fstar.w[2] > bid_ten2mxtrunc192[ind].w[2] || (fstar.w[2] == bid_ten2mxtrunc192[ind].w[2] && fstar.w[1] > bid_ten2mxtrunc192[ind].w[1]) || (fstar.w[2] == bid_ten2mxtrunc192[ind].w[2] && fstar.w[1] == bid_ten2mxtrunc192[ind].w[1] && fstar.w[0] > bid_ten2mxtrunc192[ind].w[0])) {    // f* - 1/2 > 10^(-x)
                    ptr_is_inexact_lt_midpoint = true
                }    // else the result is exact
            } else {    // the result is inexact; f2* <= 1/2
                ptr_is_inexact_gt_midpoint = true
            }
        } else if (ind <= 37) {    // if 19 <= ind <= 37
            if (fstar.w[4] > bid_half192[ind] || (fstar.w[4] == bid_half192[ind] &&
                                                  (fstar.w[3] != 0 || fstar.w[2] != 0 || fstar.w[1] != 0 || fstar.w[0] != 0))) {
                // f* > 1/2 and the result may be exact
                // Calculate f* - 1/2
                tmp64 = fstar.w[4] - bid_half192[ind];
                if (tmp64 != 0 || fstar.w[3] != 0 || fstar.w[2] > bid_ten2mxtrunc192[ind].w[2] || (fstar.w[2] == bid_ten2mxtrunc192[ind].w[2] && fstar.w[1] > bid_ten2mxtrunc192[ind].w[1]) || (fstar.w[2] == bid_ten2mxtrunc192[ind].w[2] && fstar.w[1] == bid_ten2mxtrunc192[ind].w[1] && fstar.w[0] > bid_ten2mxtrunc192[ind].w[0])) {    // f* - 1/2 > 10^(-x)
                    ptr_is_inexact_lt_midpoint = true
                }    // else the result is exact
            } else {    // the result is inexact; f2* <= 1/2
                ptr_is_inexact_gt_midpoint = true
            }
        } else {    // if 38 <= ind <= 55
            if (fstar.w[5] > bid_half192[ind] || (fstar.w[5] == bid_half192[ind] &&
                                                  (fstar.w[4] != 0 || fstar.w[3] != 0 || fstar.w[2] != 0 || fstar.w[1] != 0 || fstar.w[0] != 0))) {
                // f* > 1/2 and the result may be exact
                // Calculate f* - 1/2
                tmp64 = fstar.w[5] - bid_half192[ind];
                if (tmp64 != 0 || fstar.w[4] != 0 || fstar.w[3] != 0 || fstar.w[2] > bid_ten2mxtrunc192[ind].w[2] || (fstar.w[2] == bid_ten2mxtrunc192[ind].w[2] && fstar.w[1] > bid_ten2mxtrunc192[ind].w[1]) || (fstar.w[2] == bid_ten2mxtrunc192[ind].w[2] && fstar.w[1] == bid_ten2mxtrunc192[ind].w[1] && fstar.w[0] > bid_ten2mxtrunc192[ind].w[0])) {    // f* - 1/2 > 10^(-x)
                    ptr_is_inexact_lt_midpoint = true
                }    // else the result is exact
            } else {    // the result is inexact; f2* <= 1/2
                ptr_is_inexact_gt_midpoint = true
            }
        }
        // check for midpoints (could do this before determining inexactness)
        if (fstar.w[5] == 0 && fstar.w[4] == 0 && fstar.w[3] == 0 &&
            (fstar.w[2] < bid_ten2mxtrunc192[ind].w[2] ||
             (fstar.w[2] == bid_ten2mxtrunc192[ind].w[2] &&
              fstar.w[1] < bid_ten2mxtrunc192[ind].w[1]) ||
             (fstar.w[2] == bid_ten2mxtrunc192[ind].w[2] &&
              fstar.w[1] == bid_ten2mxtrunc192[ind].w[1] &&
              fstar.w[0] <= bid_ten2mxtrunc192[ind].w[0]))) {
            // the result is a midpoint
            if (Cstar.w[0] & 0x01 != 0) {    // Cstar is odd; MP in [EVEN, ODD]
                // if floor(C*) is odd C = floor(C*) - 1; the result may be 0
                Cstar.w[0]-=1    // Cstar is now even
                if (Cstar.w[0] == 0xffffffffffffffff) {
                    Cstar.w[1]-=1
                    if (Cstar.w[1] == 0xffffffffffffffff) {
                        Cstar.w[2]-=1
                    }
                }
                ptr_is_midpoint_gt_even = true
                ptr_is_inexact_lt_midpoint = false
                ptr_is_inexact_gt_midpoint = false
            } else {    // else MP in [ODD, EVEN]
                ptr_is_midpoint_lt_even = true
                ptr_is_inexact_lt_midpoint = false
                ptr_is_inexact_gt_midpoint = false
            }
        }
        // check for rounding overflow, which occurs if Cstar = 10^(q-x)
        ind = q - x;    // 1 <= ind <= q - 1
        if (ind <= 19) {
            if (Cstar.w[2] == 0x0 && Cstar.w[1] == 0x0 &&
                Cstar.w[0] == bid_ten2k64[ind]) {
                // if  Cstar = 10^(q-x)
                Cstar.w[0] = bid_ten2k64[ind - 1];    // Cstar = 10^(q-x-1)
                incr_exp = 1;
            } else {
                incr_exp = 0;
            }
        } else if (ind == 20) {
            // if ind = 20
            if (Cstar.w[2] == 0x0 && Cstar.w[1] == bid_ten2k128[0].hi &&
                Cstar.w[0] == bid_ten2k128[0].lo) {
                // if  Cstar = 10^(q-x)
                Cstar.w[0] = bid_ten2k64[19];    // Cstar = 10^(q-x-1)
                Cstar.w[1] = 0x0;
                incr_exp = 1;
            } else {
                incr_exp = 0;
            }
        } else if (ind <= 38) {    // if 21 <= ind <= 38
            if (Cstar.w[2] == 0x0 && Cstar.w[1] == bid_ten2k128[ind - 20].hi &&
                Cstar.w[0] == bid_ten2k128[ind - 20].lo) {
                // if  Cstar = 10^(q-x)
                Cstar.w[0] = bid_ten2k128[ind - 21].lo;    // Cstar = 10^(q-x-1)
                Cstar.w[1] = bid_ten2k128[ind - 21].hi
                incr_exp = 1;
            } else {
                incr_exp = 0;
            }
        } else if (ind == 39) {
            if (Cstar.w[2] == bid_ten2k256[0].w[2] && Cstar.w[1] == bid_ten2k256[0].w[1]
                && Cstar.w[0] == bid_ten2k256[0].w[0]) {
                // if  Cstar = 10^(q-x)
                Cstar.w[0] = bid_ten2k128[18].lo    // Cstar = 10^(q-x-1)
                Cstar.w[1] = bid_ten2k128[18].hi
                Cstar.w[2] = 0x0;
                incr_exp = 1;
            } else {
                incr_exp = 0;
            }
        } else {    // if 40 <= ind <= 56
            if (Cstar.w[2] == bid_ten2k256[ind - 39].w[2] &&
                Cstar.w[1] == bid_ten2k256[ind - 39].w[1] &&
                Cstar.w[0] == bid_ten2k256[ind - 39].w[0]) {
                // if  Cstar = 10^(q-x)
                Cstar.w[0] = bid_ten2k256[ind - 40].w[0];    // Cstar = 10^(q-x-1)
                Cstar.w[1] = bid_ten2k256[ind - 40].w[1];
                Cstar.w[2] = bid_ten2k256[ind - 40].w[2];
                incr_exp = 1;
            } else {
                incr_exp = 0;
            }
        }
        ptr_Cstar = Cstar
    }
    
    
    static func bid_round256_58_76 (_ q:Int, _ x:Int,_ C:UInt256, _ ptr_Cstar:inout UInt256, _ incr_exp:inout Int,
                                    _ ptr_is_midpoint_lt_even:inout Bool, _ ptr_is_midpoint_gt_even:inout Bool,
                                    _ ptr_is_inexact_lt_midpoint:inout Bool, _ ptr_is_inexact_gt_midpoint:inout Bool) {
        var Cstar = UInt256(), P512 = UInt512(), fstar = UInt512()
        
        // Note:
        //    In bid_round256_58_76() positive numbers with 58 <= q <= 76 will be
        //    rounded to nearest only for 24 <= x <= 61:
        //     x = 42 or x = 43 or x = 24 or x = 25 when q = 58
        //     x = 43 or x = 44 or x = 25 or x = 26 when q = 59
        //     ...
        //     x = 60 or x = 61 or x = 42 or x = 43 when q = 76
        // However, for generality and possible uses outside the frame of IEEE 754
        // this implementation works for 1 <= x <= q - 1
        
        // assume ptr_is_midpoint_lt_even, ptr_is_midpoint_gt_even,
        // ptr_is_inexact_lt_midpoint, and ptr_is_inexact_gt_midpoint are
        // initialized to 0 by the caller
        
        // round a number C with q decimal digits, 58 <= q <= 76
        // to q - x digits, 1 <= x <= 75
        // C = C + 1/2 * 10^x where the result C fits in 256 bits
        // (because the largest value is 9999999999999999999999999999999999999999
        //     999999999999999999999999999999999999 + 500000000000000000000000000
        //     000000000000000000000000000000000000000000000000 =
        //     0x1736ca15d27a56cae15cf0e7b403d1f2bd6ebb0a50dc83ffffffffffffffffff,
        // which fits in 253 bits)
        var tmp64:UInt64, C = C
        var ind = x - 1;    // 0 <= ind <= 74
        if (ind <= 18) {    // if 0 <= ind <= 18
            tmp64 = C.w[0];
            C.w[0] = C.w[0] + bid_midpoint64[ind];
            if (C.w[0] < tmp64) {
                C.w[1]+=1
                if (C.w[1] == 0x0) {
                    C.w[2]+=1
                    if (C.w[2] == 0x0) {
                        C.w[3]+=1
                    }
                }
            }
        } else if (ind <= 37) {    // if 19 <= ind <= 37
            tmp64 = C.w[0];
            C.w[0] = C.w[0] + bid_midpoint128[ind - 19].lo
            if (C.w[0] < tmp64) {
                C.w[1]+=1
                if (C.w[1] == 0x0) {
                    C.w[2]+=1
                    if (C.w[2] == 0x0) {
                        C.w[3]+=1
                    }
                }
            }
            tmp64 = C.w[1];
            C.w[1] = C.w[1] + bid_midpoint128[ind - 19].hi
            if (C.w[1] < tmp64) {
                C.w[2]+=1
                if (C.w[2] == 0x0) {
                    C.w[3]+=1
                }
            }
        } else if (ind <= 57) {    // if 38 <= ind <= 57
            tmp64 = C.w[0];
            C.w[0] = C.w[0] + bid_midpoint192[ind - 38].w[0];
            if (C.w[0] < tmp64) {
                C.w[1]+=1
                if (C.w[1] == 0x0) {
                    C.w[2]+=1
                    if (C.w[2] == 0x0) {
                        C.w[3]+=1
                    }
                }
            }
            tmp64 = C.w[1];
            C.w[1] = C.w[1] + bid_midpoint192[ind - 38].w[1];
            if (C.w[1] < tmp64) {
                C.w[2]+=1
                if (C.w[2] == 0x0) {
                    C.w[3]+=1
                }
            }
            tmp64 = C.w[2];
            C.w[2] = C.w[2] + bid_midpoint192[ind - 38].w[2];
            if (C.w[2] < tmp64) {
                C.w[3]+=1
            }
        } else {    // if 58 <= ind <= 76 (actually 58 <= ind <= 74)
            tmp64 = C.w[0];
            C.w[0] = C.w[0] + bid_midpoint256[ind - 58].w[0];
            if (C.w[0] < tmp64) {
                C.w[1]+=1
                if (C.w[1] == 0x0) {
                    C.w[2]+=1
                    if (C.w[2] == 0x0) {
                        C.w[3]+=1
                    }
                }
            }
            tmp64 = C.w[1];
            C.w[1] = C.w[1] + bid_midpoint256[ind - 58].w[1];
            if (C.w[1] < tmp64) {
                C.w[2]+=1
                if (C.w[2] == 0x0) {
                    C.w[3]+=1
                }
            }
            tmp64 = C.w[2];
            C.w[2] = C.w[2] + bid_midpoint256[ind - 58].w[2];
            if (C.w[2] < tmp64) {
                C.w[3]+=1
            }
            C.w[3] = C.w[3] + bid_midpoint256[ind - 58].w[3];
        }
        // kx ~= 10^(-x), kx = bid_Kx256[ind] * 2^(-Ex), 0 <= ind <= 74
        // P512 = (C + 1/2 * 10^x) * kx * 2^Ex = (C + 1/2 * 10^x) * Kx
        // the approximation kx of 10^(-x) was rounded up to 192 bits
        __mul_256x256_to_512(&P512, C, bid_Kx256[ind]);
        // calculate C* = floor (P512) and f*
        // Cstar = P512 >> Ex
        // fstar = low Ex bits of P512
        let shift = bid_Ex256m256[ind];    // in [0, 63] but have to consider four cases
        if (ind <= 18) {    // if 0 <= ind <= 18
            Cstar.w[3] = (P512.w[7] >> shift);
            Cstar.w[2] = (P512.w[7] << (64 - shift)) | (P512.w[6] >> shift);
            Cstar.w[1] = (P512.w[6] << (64 - shift)) | (P512.w[5] >> shift);
            Cstar.w[0] = (P512.w[5] << (64 - shift)) | (P512.w[4] >> shift);
            fstar.w[7] = 0x0;
            fstar.w[6] = 0x0;
            fstar.w[5] = 0x0;
            fstar.w[4] = P512.w[4] & bid_mask256[ind];
            fstar.w[3] = P512.w[3];
            fstar.w[2] = P512.w[2];
            fstar.w[1] = P512.w[1];
            fstar.w[0] = P512.w[0];
        } else if (ind <= 37) {    // if 19 <= ind <= 37
            Cstar.w[3] = 0x0;
            Cstar.w[2] = P512.w[7] >> shift;
            Cstar.w[1] = (P512.w[7] << (64 - shift)) | (P512.w[6] >> shift);
            Cstar.w[0] = (P512.w[6] << (64 - shift)) | (P512.w[5] >> shift);
            fstar.w[7] = 0x0;
            fstar.w[6] = 0x0;
            fstar.w[5] = P512.w[5] & bid_mask256[ind];
            fstar.w[4] = P512.w[4];
            fstar.w[3] = P512.w[3];
            fstar.w[2] = P512.w[2];
            fstar.w[1] = P512.w[1];
            fstar.w[0] = P512.w[0];
        } else if (ind <= 56) {    // if 38 <= ind <= 56
            Cstar.w[3] = 0x0;
            Cstar.w[2] = 0x0;
            Cstar.w[1] = P512.w[7] >> shift;
            Cstar.w[0] = (P512.w[7] << (64 - shift)) | (P512.w[6] >> shift);
            fstar.w[7] = 0x0;
            fstar.w[6] = P512.w[6] & bid_mask256[ind];
            fstar.w[5] = P512.w[5];
            fstar.w[4] = P512.w[4];
            fstar.w[3] = P512.w[3];
            fstar.w[2] = P512.w[2];
            fstar.w[1] = P512.w[1];
            fstar.w[0] = P512.w[0];
        } else if (ind == 57) {
            Cstar.w[3] = 0x0;
            Cstar.w[2] = 0x0;
            Cstar.w[1] = 0x0;
            Cstar.w[0] = P512.w[7];
            fstar.w[7] = 0x0;
            fstar.w[6] = P512.w[6];
            fstar.w[5] = P512.w[5];
            fstar.w[4] = P512.w[4];
            fstar.w[3] = P512.w[3];
            fstar.w[2] = P512.w[2];
            fstar.w[1] = P512.w[1];
            fstar.w[0] = P512.w[0];
        } else {    // if 58 <= ind <= 74
            Cstar.w[3] = 0x0;
            Cstar.w[2] = 0x0;
            Cstar.w[1] = 0x0;
            Cstar.w[0] = P512.w[7] >> shift;
            fstar.w[7] = P512.w[7] & bid_mask256[ind];
            fstar.w[6] = P512.w[6];
            fstar.w[5] = P512.w[5];
            fstar.w[4] = P512.w[4];
            fstar.w[3] = P512.w[3];
            fstar.w[2] = P512.w[2];
            fstar.w[1] = P512.w[1];
            fstar.w[0] = P512.w[0];
        }
        
        // the top Ex bits of 10^(-x) are T* = bid_ten2mxtrunc256[ind], e.g. if x=1,
        // T*=bid_ten2mxtrunc256[0]=
        //     0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
        // if (0 < f* < 10^(-x)) then the result is a midpoint
        //   if floor(C*) is even then C* = floor(C*) - logical right
        //       shift; C* has q - x decimal digits, correct by Prop. 1)
        //   else if floor(C*) is odd C* = floor(C*)-1 (logical right
        //       shift; C* has q - x decimal digits, correct by Pr. 1)
        // else
        //   C* = floor(C*) (logical right shift; C has q - x decimal digits,
        //       correct by Property 1)
        // in the caling function n = C* * 10^(e+x)
        
        // determine inexactness of the rounding of C*
        // if (0 < f* - 1/2 < 10^(-x)) then
        //   the result is exact
        // else // if (f* - 1/2 > T*) then
        //   the result is inexact
        if (ind <= 18) {    // if 0 <= ind <= 18
            if (fstar.w[4] > bid_half256[ind] || (fstar.w[4] == bid_half256[ind] &&
                                                  (fstar.w[3] != 0 || fstar.w[2] != 0
                                                   || fstar.w[1] != 0 || fstar.w[0] != 0))) {
                // f* > 1/2 and the result may be exact
                // Calculate f* - 1/2
                tmp64 = fstar.w[4] - bid_half256[ind];
                if (tmp64 != 0 || fstar.w[3] > bid_ten2mxtrunc256[ind].w[2] || (fstar.w[3] == bid_ten2mxtrunc256[ind].w[3] && fstar.w[2] > bid_ten2mxtrunc256[ind].w[2]) || (fstar.w[3] == bid_ten2mxtrunc256[ind].w[3] && fstar.w[2] == bid_ten2mxtrunc256[ind].w[2] && fstar.w[1] > bid_ten2mxtrunc256[ind].w[1]) || (fstar.w[3] == bid_ten2mxtrunc256[ind].w[3] && fstar.w[2] == bid_ten2mxtrunc256[ind].w[2] && fstar.w[1] == bid_ten2mxtrunc256[ind].w[1] && fstar.w[0] > bid_ten2mxtrunc256[ind].w[0])) {    // f* - 1/2 > 10^(-x)
                    ptr_is_inexact_lt_midpoint = true
                }    // else the result is exact
            } else {    // the result is inexact; f2* <= 1/2
                ptr_is_inexact_gt_midpoint = true
            }
        } else if (ind <= 37) {    // if 19 <= ind <= 37
            if (fstar.w[5] > bid_half256[ind] || (fstar.w[5] == bid_half256[ind] &&
                                                  (fstar.w[4] != 0 || fstar.w[3] != 0
                                                   || fstar.w[2] != 0 || fstar.w[1] != 0
                                                   || fstar.w[0] != 0))) {
                // f* > 1/2 and the result may be exact
                // Calculate f* - 1/2
                tmp64 = fstar.w[5] - bid_half256[ind];
                if (tmp64 != 0 || fstar.w[4] != 0 || fstar.w[3] > bid_ten2mxtrunc256[ind].w[3] || (fstar.w[3] == bid_ten2mxtrunc256[ind].w[3] && fstar.w[2] > bid_ten2mxtrunc256[ind].w[2]) || (fstar.w[3] == bid_ten2mxtrunc256[ind].w[3] && fstar.w[2] == bid_ten2mxtrunc256[ind].w[2] && fstar.w[1] > bid_ten2mxtrunc256[ind].w[1]) || (fstar.w[3] == bid_ten2mxtrunc256[ind].w[3] && fstar.w[2] == bid_ten2mxtrunc256[ind].w[2] && fstar.w[1] == bid_ten2mxtrunc256[ind].w[1] && fstar.w[0] > bid_ten2mxtrunc256[ind].w[0])) {    // f* - 1/2 > 10^(-x)
                    ptr_is_inexact_lt_midpoint = true
                }    // else the result is exact
            } else {    // the result is inexact; f2* <= 1/2
                ptr_is_inexact_gt_midpoint = true
            }
        } else if (ind <= 57) {    // if 38 <= ind <= 57
            if (fstar.w[6] > bid_half256[ind] || (fstar.w[6] == bid_half256[ind] &&
                                                  (fstar.w[5] != 0 || fstar.w[4] != 0
                                                   || fstar.w[3] != 0 || fstar.w[2] != 0
                                                   || fstar.w[1] != 0 || fstar.w[0] != 0))) {
                // f* > 1/2 and the result may be exact
                // Calculate f* - 1/2
                tmp64 = fstar.w[6] - bid_half256[ind];
                if (tmp64 != 0 || fstar.w[5] != 0 || fstar.w[4] != 0 || fstar.w[3] > bid_ten2mxtrunc256[ind].w[3] || (fstar.w[3] == bid_ten2mxtrunc256[ind].w[3] && fstar.w[2] > bid_ten2mxtrunc256[ind].w[2]) || (fstar.w[3] == bid_ten2mxtrunc256[ind].w[3] && fstar.w[2] == bid_ten2mxtrunc256[ind].w[2] && fstar.w[1] > bid_ten2mxtrunc256[ind].w[1]) || (fstar.w[3] == bid_ten2mxtrunc256[ind].w[3] && fstar.w[2] == bid_ten2mxtrunc256[ind].w[2] && fstar.w[1] == bid_ten2mxtrunc256[ind].w[1] && fstar.w[0] > bid_ten2mxtrunc256[ind].w[0])) {    // f* - 1/2 > 10^(-x)
                    ptr_is_inexact_lt_midpoint = true
                }    // else the result is exact
            } else {    // the result is inexact; f2* <= 1/2
                ptr_is_inexact_gt_midpoint = true
            }
        } else {    // if 58 <= ind <= 74
            if (fstar.w[7] > bid_half256[ind] || (fstar.w[7] == bid_half256[ind] &&
                                                  (fstar.w[6] != 0 || fstar.w[5] != 0
                                                   || fstar.w[4] != 0 || fstar.w[3] != 0
                                                   || fstar.w[2] != 0 || fstar.w[1] != 0
                                                   || fstar.w[0] != 0))) {
                // f* > 1/2 and the result may be exact
                // Calculate f* - 1/2
                tmp64 = fstar.w[7] - bid_half256[ind];
                if (tmp64 != 0 || fstar.w[6] != 0 || fstar.w[5] != 0 || fstar.w[4] != 0 || fstar.w[3] > bid_ten2mxtrunc256[ind].w[3] || (fstar.w[3] == bid_ten2mxtrunc256[ind].w[3] && fstar.w[2] > bid_ten2mxtrunc256[ind].w[2]) || (fstar.w[3] == bid_ten2mxtrunc256[ind].w[3] && fstar.w[2] == bid_ten2mxtrunc256[ind].w[2] && fstar.w[1] > bid_ten2mxtrunc256[ind].w[1]) || (fstar.w[3] == bid_ten2mxtrunc256[ind].w[3] && fstar.w[2] == bid_ten2mxtrunc256[ind].w[2] && fstar.w[1] == bid_ten2mxtrunc256[ind].w[1] && fstar.w[0] > bid_ten2mxtrunc256[ind].w[0])) {    // f* - 1/2 > 10^(-x)
                    ptr_is_inexact_lt_midpoint = true
                }    // else the result is exact
            } else {    // the result is inexact; f2* <= 1/2
                ptr_is_inexact_gt_midpoint = true
            }
        }
        // check for midpoints (could do this before determining inexactness)
        if (fstar.w[7] == 0 && fstar.w[6] == 0 &&
            fstar.w[5] == 0 && fstar.w[4] == 0 &&
            (fstar.w[3] < bid_ten2mxtrunc256[ind].w[3] ||
             (fstar.w[3] == bid_ten2mxtrunc256[ind].w[3] &&
              fstar.w[2] < bid_ten2mxtrunc256[ind].w[2]) ||
             (fstar.w[3] == bid_ten2mxtrunc256[ind].w[3] &&
              fstar.w[2] == bid_ten2mxtrunc256[ind].w[2] &&
              fstar.w[1] < bid_ten2mxtrunc256[ind].w[1]) ||
             (fstar.w[3] == bid_ten2mxtrunc256[ind].w[3] &&
              fstar.w[2] == bid_ten2mxtrunc256[ind].w[2] &&
              fstar.w[1] == bid_ten2mxtrunc256[ind].w[1] &&
              fstar.w[0] <= bid_ten2mxtrunc256[ind].w[0]))) {
            // the result is a midpoint
            if (Cstar.w[0] & 0x01) != 0 {    // Cstar is odd; MP in [EVEN, ODD]
                // if floor(C*) is odd C = floor(C*) - 1; the result may be 0
                Cstar.w[0]-=1    // Cstar is now even
                if (Cstar.w[0] == 0xffffffffffffffff) {
                    Cstar.w[1]-=1
                    if (Cstar.w[1] == 0xffffffffffffffff) {
                        Cstar.w[2]-=1
                        if (Cstar.w[2] == 0xffffffffffffffff) {
                            Cstar.w[3]-=1
                        }
                    }
                }
                ptr_is_midpoint_gt_even = true
                ptr_is_inexact_lt_midpoint = false
                ptr_is_inexact_gt_midpoint = false
            } else {    // else MP in [ODD, EVEN]
                ptr_is_midpoint_lt_even = true
                ptr_is_inexact_lt_midpoint = false
                ptr_is_inexact_gt_midpoint = false
            }
        }
        // check for rounding overflow, which occurs if Cstar = 10^(q-x)
        ind = q - x;    // 1 <= ind <= q - 1
        if (ind <= 19) {
            if (Cstar.w[3] == 0x0 && Cstar.w[2] == 0x0 &&
                Cstar.w[1] == 0x0 && Cstar.w[0] == bid_ten2k64[ind]) {
                // if  Cstar = 10^(q-x)
                Cstar.w[0] = bid_ten2k64[ind - 1];    // Cstar = 10^(q-x-1)
                incr_exp = 1
            } else {
                incr_exp = 0
            }
        } else if (ind == 20) {
            // if ind = 20
            if (Cstar.w[3] == 0x0 && Cstar.w[2] == 0x0 &&
                Cstar.w[1] == bid_ten2k128[0].hi
                && Cstar.w[0] == bid_ten2k128[0].lo) {
                // if  Cstar = 10^(q-x)
                Cstar.w[0] = bid_ten2k64[19];    // Cstar = 10^(q-x-1)
                Cstar.w[1] = 0x0;
                incr_exp = 1;
            } else {
                incr_exp = 0;
            }
        } else if (ind <= 38) {    // if 21 <= ind <= 38
            if (Cstar.w[3] == 0x0 && Cstar.w[2] == 0x0 &&
                Cstar.w[1] == bid_ten2k128[ind - 20].hi &&
                Cstar.w[0] == bid_ten2k128[ind - 20].lo) {
                // if  Cstar = 10^(q-x)
                Cstar.w[0] = bid_ten2k128[ind - 21].lo;    // Cstar = 10^(q-x-1)
                Cstar.w[1] = bid_ten2k128[ind - 21].hi;
                incr_exp = 1;
            } else {
                incr_exp = 0;
            }
        } else if (ind == 39) {
            if (Cstar.w[3] == 0x0 && Cstar.w[2] == bid_ten2k256[0].w[2] &&
                Cstar.w[1] == bid_ten2k256[0].w[1]
                && Cstar.w[0] == bid_ten2k256[0].w[0]) {
                // if  Cstar = 10^(q-x)
                Cstar.w[0] = bid_ten2k128[18].lo;    // Cstar = 10^(q-x-1)
                Cstar.w[1] = bid_ten2k128[18].hi;
                Cstar.w[2] = 0x0;
                incr_exp = 1;
            } else {
                incr_exp = 0;
            }
        } else if (ind <= 57) {    // if 40 <= ind <= 57
            if (Cstar.w[3] == 0x0 && Cstar.w[2] == bid_ten2k256[ind - 39].w[2] &&
                Cstar.w[1] == bid_ten2k256[ind - 39].w[1] &&
                Cstar.w[0] == bid_ten2k256[ind - 39].w[0]) {
                // if  Cstar = 10^(q-x)
                Cstar.w[0] = bid_ten2k256[ind - 40].w[0];    // Cstar = 10^(q-x-1)
                Cstar.w[1] = bid_ten2k256[ind - 40].w[1];
                Cstar.w[2] = bid_ten2k256[ind - 40].w[2];
                incr_exp = 1;
            } else {
                incr_exp = 0;
            }
            // else if (ind == 58) is not needed becauae we do not have ten2k192[] yet
        } else {    // if 58 <= ind <= 77 (actually 58 <= ind <= 74)
            if (Cstar.w[3] == bid_ten2k256[ind - 39].w[3] &&
                Cstar.w[2] == bid_ten2k256[ind - 39].w[2] &&
                Cstar.w[1] == bid_ten2k256[ind - 39].w[1] &&
                Cstar.w[0] == bid_ten2k256[ind - 39].w[0]) {
                // if  Cstar = 10^(q-x)
                Cstar.w[0] = bid_ten2k256[ind - 40].w[0];    // Cstar = 10^(q-x-1)
                Cstar.w[1] = bid_ten2k256[ind - 40].w[1];
                Cstar.w[2] = bid_ten2k256[ind - 40].w[2];
                Cstar.w[3] = bid_ten2k256[ind - 40].w[3];
                incr_exp = 1;
            } else {
                incr_exp = 0;
            }
        }
        ptr_Cstar = Cstar
    }
    
    static func bid_add256(_ x:UInt256, _ y:UInt256, _ z:inout UInt256) {
        // *z = x + yl assume the sum fits in 256 bits
        var x = x
        z.w[0] = x.w[0] + y.w[0];
        if (z.w[0] < x.w[0]) {
            x.w[1]+=1
            if (x.w[1] == 0x0000000000000000) {
                x.w[2]+=1
                if (x.w[2] == 0x0000000000000000) {
                    x.w[3]+=1
                }
            }
        }
        z.w[1] = x.w[1] + y.w[1];
        if (z.w[1] < x.w[1]) {
            x.w[2]+=1
            if (x.w[2] == 0x0000000000000000) {
                x.w[3]+=1
            }
        }
        z.w[2] = x.w[2] + y.w[2];
        if (z.w[2] < x.w[2]) {
            x.w[3]+=1
        }
        z.w[3] = x.w[3] + y.w[3]; // it was assumed that no carry is possible
    }
    
    static func bid_sub256(_ x:UInt256, _ y:UInt256, _ z:inout UInt256) {
        // *z = x - y; assume x >= y
        var x = x
        z.w[0] = x.w[0] - y.w[0];
        if (z.w[0] > x.w[0]) {
            x.w[1]-=1
            if (x.w[1] == 0xffffffffffffffff) {
                x.w[2]-=1
                if (x.w[2] == 0xffffffffffffffff) {
                    x.w[3]-=1
                }
            }
        }
        z.w[1] = x.w[1] - y.w[1];
        if (z.w[1] > x.w[1]) {
            x.w[2]-=1
            if (x.w[2] == 0xffffffffffffffff) {
                x.w[3]-=1
            }
        }
        z.w[2] = x.w[2] - y.w[2];
        if (z.w[2] > x.w[2]) {
            x.w[3]-=1
        }
        z.w[3] = x.w[3] - y.w[3]; // no borrow possible, because x >= y
    }
    
    
    static func bid_bid_nr_digits256(_ R256:UInt256) -> Int {
        var ind = 0
        // determine the number of decimal digits in R256
        if (R256.w[3] == 0x0 && R256.w[2] == 0x0 && R256.w[1] == 0x0) {
            // between 1 and 19 digits
            for i in 1...19 {
                if (R256.w[0] < bid_ten2k64[ind]) {
                    ind = i; break
                }
            }
            // ind digits
        } else if (R256.w[3] == 0x0 && R256.w[2] == 0x0 &&
                   (R256.w[1] < bid_ten2k128[0].hi ||
                    (R256.w[1] == bid_ten2k128[0].hi
                     && R256.w[0] < bid_ten2k128[0].hi))) {
            // 20 digits
            ind = 20;
        } else if (R256.w[3] == 0x0 && R256.w[2] == 0x0) {
            // between 21 and 38 digits
            for i in 1...18 {
                if (R256.w[1] < bid_ten2k128[ind].hi ||
                    (R256.w[1] == bid_ten2k128[ind].hi &&
                     R256.w[0] < bid_ten2k128[ind].hi)) {
                    ind = i; break
                }
            }
            // ind + 20 digits
            ind = ind + 20
        } else if (R256.w[3] == 0x0 &&
                   (R256.w[2] < bid_ten2k256[0].w[2] ||
                    (R256.w[2] == bid_ten2k256[0].w[2] &&
                     R256.w[1] < bid_ten2k256[0].w[1]) ||
                    (R256.w[2] == bid_ten2k256[0].w[2] &&
                     R256.w[1] == bid_ten2k256[0].w[1] &&
                     R256.w[0] < bid_ten2k256[0].w[0]))) {
            // 39 digits
            ind = 39;
        } else {
            // between 40 and 68 digits
            for i in 1...29 {
                if (R256.w[3] < bid_ten2k256[ind].w[3] ||
                    (R256.w[3] == bid_ten2k256[ind].w[3] &&
                     R256.w[2] < bid_ten2k256[ind].w[2]) ||
                    (R256.w[3] == bid_ten2k256[ind].w[3] &&
                     R256.w[2] == bid_ten2k256[ind].w[2] &&
                     R256.w[1] < bid_ten2k256[ind].w[1]) ||
                    (R256.w[3] == bid_ten2k256[ind].w[3] &&
                     R256.w[2] == bid_ten2k256[ind].w[2] &&
                     R256.w[1] == bid_ten2k256[ind].w[1] &&
                     R256.w[0] < bid_ten2k256[ind].w[0])) {
                    ind = i; break
                }
            }
            // ind + 39 digits
            ind = ind + 39
        }
        return ind
    }
    

}
