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
        var ARS = UInt256(), ARS0 = UInt256(), AE0 = UInt256(), AE = UInt256(), S = UInt256()
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
        var exp_x = 0, exp_y = 0, sig_n_prime192 = UInt256(), sig_n_prime256 = UInt256()
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
        var exp_x = 0, exp_y = 0, sig_n_prime192 = UInt256(), sig_n_prime256 = UInt256()
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
    
    static func fma(_ x: UInt128, _ y: UInt128, _ z: UInt128, _ rnd_mode: Rounding, _ pfpsf: inout Status) -> UInt128 {
        return 0
    }
    
    static func mul(_ x:UInt128, _ y:UInt128, _ rnd_mode: Rounding, _ pfpsf: inout Status) -> UInt128 {
        return x
    }
    
    static func nextup(_ x: UInt128, _ pfpsf: inout Status) -> UInt128 {
        return 0
    }
    
}
