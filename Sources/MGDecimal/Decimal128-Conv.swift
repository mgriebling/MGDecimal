//
//  File.swift
//  
//
//  Created by Mike Griebling on 2022-03-20.
//

import Foundation

extension Decimal128 {
    
    /////////////////////////////////////////
    // BID128 definitions
    ////////////////////////////////////////
    static let MAX_EXPON                 = 12287
    static let EXPONENT_BIAS             = 6176
    static let MAX_FORMAT_DIGITS_128     = 34
    static let P34                       = MAX_FORMAT_DIGITS_128
    static let MAX_STRING_DIGITS_128     = 100
    static let MAX_SEARCH                = MAX_STRING_DIGITS_128-MAX_FORMAT_DIGITS_128-1
    
    ////////////////////////////////////////
    // Constant Definitions
    ///////////////////////////////////////
    static let EXP_P1                   = UInt64(0x0002_0000_0000_0000)
    static let EXP_MIN                  = Decimal64.EXP_MIN
    static let EXP_MAX_P1               = UInt64(0x6000_0000_0000_0000)
    static let SMALL_COEFF_MASK128      = UInt64(0x0001_ffff_ffff_ffff)
    static let LARGE_COEFF_MASK128      = UInt64(0x0000_7fff_ffff_ffff)
    static let QUIET_MASK64             = UInt64(0xfdff_ffff_ffff_ffff)
    static let EXPONENT_MASK128         = 0x3fff
    static let LARGEST_BID128_HIGH      = UInt64(0x5fff_ed09_bead_87c0)
    static let LARGEST_BID128_LOW       = UInt64(0x378d_8e63_ffff_ffff)
    static let MASK_SPECIAL             = Decimal64.MASK_INF
    static let MASK_INF                 = Decimal64.MASK_INF
    static let MASK_ANY_INF             = Decimal64.MASK_ANY_INF
    static let INFINITY_MASK64          = Decimal64.MASK_INF
    static let MASK_EXP2                = UInt64(0x1fff_8000_0000_0000)
    static let MASK_NAN                 = Decimal64.MASK_NAN
    static let MASK_SNAN                = Decimal64.MASK_SNAN
    static let MASK_SIGN                = Decimal64.MASK_SIGN
    static let MASK_COEFF               = UInt64(0x0001_ffff_ffff_ffff)
    static let SPECIAL_ENCODING_MASK64  = Decimal64.SPECIAL_ENCODING_MASK64
    static let LARGE_COEFF_HIGH_BIT64   = Decimal64.LARGE_COEFF_HIGH_BIT64
    static let MASK_STEERING_BITS       = Decimal64.MASK_STEERING_BITS
    static let MASK_EXP                 = UInt64(0x7ffe_0000_0000_0000)
    static let BINARY_EXPONENT_BIAS     = Decimal64.BINARY_EXPONENT_BIAS
    
    // 10^33 - 1 = 0x0000314dc6448d93_38c15b09ffffffff
    // 10^34 - 1 = 0x0001ed09bead87c0_378d8e63ffffffff
    static let Ten33M1 = UInt128(upper: 0x0000_314d_c644_8d93, lower: 0x38c1_5b09_ffff_ffff)
    static let Ten34M1 = UInt128(upper: 0x0001_ed09_bead_87c0, lower: 0x378d_8e63_ffff_ffff)

    /*
     * Takes a BID32 as input and converts it to a BID128 and returns it.
     */
    static func bid32_to_bid128(_ x:UInt32, _ pfpsf: inout Status) -> UInt128 {
        var sign_x = UInt32(), coefficient_x = UInt32(), exponent_x = 0, res = UInt128()
        if !Decimal32.unpack_BID32(&sign_x, &exponent_x, &coefficient_x, x) {
            if (x & 0x7800_0000) == 0x7800_0000 {
                if (x & 0x7e00_0000) == 0x7e00_0000 {   // sNaN
                    pfpsf.insert(.invalidOperation)
                }
                res.lo = UInt64((coefficient_x & 0x000fffff))
                __mul_64x128_low(&res, res.lo, bid_power10_table_128[27])
                res.hi |= (UInt64(coefficient_x) << 32) & 0xfc00000000000000
                return res
            }
        }
        
        let new_coeff = UInt128.init(upper: 0, lower: UInt64(coefficient_x))
        return bid_get_BID128_very_fast(UInt64(sign_x) << 32, exponent_x + EXPONENT_BIAS - Decimal32.EXPONENT_BIAS, new_coeff)
    }    // convert_bid32_to_bid128
    
    /*
     * Takes a BID128 as input and converts it to a BID32 and returns it.
     */
    static func bid128_to_bid32 (_ x: UInt128, _ rmode: Rounding, _ pfpsf: inout Status) -> UInt32 {
        var x = x
        BID_SWAP128(&x)
        // unpack arguments, check for NaN or Infinity or 0
        var sign_x = UInt64(0), exponent_x = 0, CX = UInt128()
        if !unpack_BID128_value (&sign_x, &exponent_x, &CX, x) {
            if (((x.hi) & Decimal64.INFINITY_MASK64) == Decimal64.INFINITY_MASK64) {
                var Tmp = UInt128()
                Tmp.hi = CX.hi & 0x0000_3fff_ffff_ffff
                Tmp.lo = CX.lo
                let TP128 = bid_reciprocals10_128[27]
                var Qh = UInt128(), Ql = UInt128()
                __mul_128x128_full(&Qh, &Ql, Tmp, TP128)
                let amount = bid_recip_scale[27] - 64
                let res = ((CX.hi >> 32) & 0xfc00_0000) | (Qh.hi >> amount)
                if ((x.hi & Decimal64.SNAN_MASK64) == Decimal64.SNAN_MASK64) {   // sNaN
                    pfpsf.insert(.invalidOperation)
                    // __set_status_flags (pfpsf, BID_INVALID_EXCEPTION);
                }
                return UInt32(res)
            }
            // x is 0
            exponent_x -= EXPONENT_BIAS + Decimal32.EXPONENT_BIAS;
            if exponent_x < 0 {
                exponent_x = 0
            }
            if exponent_x > Decimal32.MAX_EXPON {
                exponent_x = Decimal32.MAX_EXPON
            }
            let res = (sign_x >> 32) | UInt64(exponent_x << 23)
            return UInt32(res)
        }
        
        if CX.hi != 0 || CX.lo > Decimal32.MAX_NUMBER {
            // find number of digits in coefficient
            // 2^64
            let f64 = Float(bitPattern: 0x5f800000)
            
            // fx ~ CX
            let fx = Float(CX.hi) * f64 + Float(CX.lo)
            let bin_expon_cx = Int((fx.bitPattern >> 23) & 0xff) - 0x7f
            var extra_digits = Int(bid_estimate_decimal_digits[bin_expon_cx]) - 7
            // scale = 38-estimate_decimal_digits[bin_expon_cx];
            let D = CX.hi - bid_power10_index_binexp_128[bin_expon_cx].hi;
            if (D > 0 || ((D == 0) && CX.lo >= bid_power10_index_binexp_128[bin_expon_cx].lo)) {
                extra_digits+=1
            }
            
            exponent_x += extra_digits
            
            var rmode1 = roundboundIndex(rmode, sign_x != 0, 0)
            if (sign_x != 0 && UInt(rmode1 - 1) < 2) {
                rmode1 = 3 - rmode1
            }
            
            var uf_check = false
            var carry = UInt64(), CX1 = UInt128(), T128 = UInt128()
            if (exponent_x < EXPONENT_BIAS - Decimal32.EXPONENT_BIAS) {
                uf_check = true
                if (-extra_digits + exponent_x - EXPONENT_BIAS + Decimal32.EXPONENT_BIAS + 35 >= 0) {
                    if (exponent_x == EXPONENT_BIAS - Decimal32.EXPONENT_BIAS - 1) {
                        T128 = bid_round_const_table_128[rmode1][extra_digits]
                        __add_carry_out (&CX1.lo, &carry, T128.lo, CX.lo);
                        CX1.hi = CX.hi + T128.hi + carry;
                        if __unsigned_compare_ge_128(CX1, bid_power10_table_128[extra_digits + 7]) {
                            uf_check = false
                        }
                    }
                    extra_digits +=  EXPONENT_BIAS - Decimal32.EXPONENT_BIAS - exponent_x;
                    exponent_x = EXPONENT_BIAS - Decimal32.EXPONENT_BIAS;
                } else {
                    rmode1 = roundboundIndex(BID_ROUNDING_TO_ZERO) >> 2
                }
            }
            
            T128 = bid_round_const_table_128[rmode1][extra_digits];
            __add_carry_out(&CX.lo, &carry, T128.lo, CX.lo);
            CX.hi = CX.hi + T128.hi + carry;
            
            let TP128 = bid_reciprocals10_128[extra_digits]
            var Qh = UInt128(), Ql = UInt128()
            __mul_128x128_full(&Qh, &Ql, CX, TP128);
            let amount = bid_recip_scale[extra_digits];
            
            if (amount >= 64) {
                CX.lo = Qh.hi >> (amount - 64);
                CX.hi = 0;
            } else {
                __shr_128(&CX, Qh, amount);
            }
            
            var Qh1 = UInt128()
            if (rmode == BID_ROUNDING_TO_NEAREST) {
                if (CX.lo & 1) != 0 {
                    // check whether fractional part of initial_P/10^ed1 is exactly .5
                    
                    // get remainder
                    __shl_128_long(&Qh1, Qh, (128 - amount));
                    
                    if ((Qh1.hi == 0) && (Qh1.lo == 0)
                        && (Ql.hi < bid_reciprocals10_128[extra_digits].hi
                            || (Ql.hi == bid_reciprocals10_128[extra_digits].hi
                                && Ql.lo < bid_reciprocals10_128[extra_digits].lo))) {
                        CX.lo-=1
                    }
                }
            }
            
            var status = Status.inexact // BID_INEXACT_EXCEPTION;
            // get remainder
            __shl_128_long (&Qh1, Qh, (128 - amount));
            
            switch (rmode) {
                case BID_ROUNDING_TO_NEAREST, BID_ROUNDING_TIES_AWAY:
                    // test whether fractional part is 0
                    if (Qh1.hi == Decimal64.SIGN_MASK64 && (Qh1.lo == 0)
                        && (Ql.hi < bid_reciprocals10_128[extra_digits].hi
                            || (Ql.hi == bid_reciprocals10_128[extra_digits].hi
                                && Ql.lo < bid_reciprocals10_128[extra_digits].lo))) {
                        status = []
                    }
                case BID_ROUNDING_DOWN, BID_ROUNDING_TO_ZERO:
                    if ((Qh1.hi == 0) && (Qh1.lo == 0)
                        && (Ql.hi < bid_reciprocals10_128[extra_digits].hi
                            || (Ql.hi == bid_reciprocals10_128[extra_digits].hi
                                && Ql.lo < bid_reciprocals10_128[extra_digits].lo))) {
                        status = []
                    }
                default:
                    // round up
                    var cy = UInt64(), Stemp = UInt128(), Tmp = UInt128(), Tmp1 = UInt128()
                    __add_carry_out (&Stemp.lo, &cy, Ql.lo, bid_reciprocals10_128[extra_digits].lo);
                    __add_carry_in_out (&Stemp.hi, &carry, Ql.hi, bid_reciprocals10_128[extra_digits].hi, cy);
                    __shr_128_long (&Qh, Qh1, (128 - amount));
                    Tmp.lo = 1;
                    Tmp.hi = 0;
                    __shl_128_long(&Tmp1, Tmp, amount);
                    Qh.lo += carry;
                    if (Qh.lo < carry) {
                        Qh.hi+=1
                    }
                    if __unsigned_compare_ge_128 (Qh, Tmp1) {
                        status = []
                    }
            }
            
            if !status.isEmpty {
                if uf_check {
                    status.insert(.underflow)
                }
                pfpsf.formUnion(status)
            }
        }
        
        return Decimal32.get_BID32 (UInt32(sign_x >> 32), exponent_x - EXPONENT_BIAS +
                                    Decimal32.EXPONENT_BIAS, UInt32(CX.lo), rmode, &pfpsf)
    }
    
    //
    //  BID128 unpack, input passed by value
    //
    static func unpack_BID128_value (_ psign_x:inout UInt64, _ pexponent_x:inout Int, _ pcoefficient_x:inout UInt128, _ x:UInt128) -> Bool {
        psign_x = x.hi & Decimal64.SIGN_MASK64
        
        // special encodings
        if (x.hi & Decimal64.INFINITY_MASK64) >= Decimal64.SPECIAL_ENCODING_MASK64 {
            if (x.hi & Decimal64.INFINITY_MASK64) < Decimal64.INFINITY_MASK64 {
                // non-canonical input
                pcoefficient_x.lo = 0
                pcoefficient_x.hi = 0
                let ex = x.hi >> 47
                pexponent_x = Int(ex) & EXPONENT_MASK128
                return false
            }
            // 10^33
            let T33 = bid_power10_table_128[33];
            /*coeff.lo = x.lo;
             coeff.hi = (x.hi) & LARGE_COEFF_MASK128;
             pcoefficient_x->w[0] = x.lo;
             pcoefficient_x->w[1] = x.hi;
             if (__unsigned_compare_ge_128 (coeff, T33)) // non-canonical
             pcoefficient_x->w[1] &= (~LARGE_COEFF_MASK128); */
            
            pcoefficient_x.lo = x.lo;
            pcoefficient_x.hi = (x.hi) & 0x00003fffffffffff
            if (__unsigned_compare_ge_128 (pcoefficient_x, T33)) {   // non-canonical
                pcoefficient_x.hi = (x.hi) & 0xfe00000000000000
                pcoefficient_x.lo = 0;
            } else {
                pcoefficient_x.hi = (x.hi) & 0xfe003fffffffffff
            }
            if ((x.hi & Decimal64.NAN_MASK64) == Decimal64.INFINITY_MASK64) {
                pcoefficient_x.lo = 0;
                pcoefficient_x.hi = x.hi & Decimal64.SINFINITY_MASK64;
            }
            pexponent_x = 0
            return false   // NaN or Infinity
        }
        
        var coeff = UInt128()
        coeff.lo = x.lo
        coeff.hi = x.hi & SMALL_COEFF_MASK128
        
        // 10^34
        let T34 = bid_power10_table_128[34];
        // check for non-canonical values
        if __unsigned_compare_ge_128(coeff, T34) {
            coeff.lo = 0; coeff.hi = 0
        }
        
        pcoefficient_x = coeff
        
        let ex = x.hi >> 49
        pexponent_x = Int(ex) & EXPONENT_MASK128
        
        return (coeff.lo | coeff.hi) != 0
    }
    
    //
    //   Macro for handling BID128 underflow
    //
    static func handle_UF_128 (_ sgn:UInt64, _ expon:Int, _ CQ:UInt128, _ prounding_mode:Rounding, _ fpsc: inout Status) -> UInt128 {
        var pres = UInt128()
        var expon = expon
        var CQ = CQ
        
        // UF occurs
        if expon + MAX_FORMAT_DIGITS_128 < 0 {
            fpsc.formUnion([.underflow, .inexact])
            pres.hi = sgn
            pres.lo = 0
            if ((sgn != 0 && prounding_mode == BID_ROUNDING_DOWN)
                || (sgn == 0 && prounding_mode == BID_ROUNDING_UP)) {
                pres.lo = 1
            }
            return pres;
        }
        
        let ed2 = 0 - expon
        // add rounding constant to CQ
        let rmode = roundboundIndex(prounding_mode, sgn != 0, 0)
        //        if (sgn && (unsigned) (rmode - 1) < 2) {
        //        rmode = 3 - rmode;
        //    }
        var carry = UInt64()
        let T128 = bid_round_const_table_128[rmode][ed2]
        __add_carry_out(&CQ.lo, &carry, T128.lo, CQ.lo)
        CQ.hi = CQ.hi + T128.hi + carry
        
        let TP128 = bid_reciprocals10_128[ed2]
        var Qh = UInt128(), Ql = UInt128()
        __mul_128x128_full(&Qh, &Ql, CQ, TP128)
        let amount = bid_recip_scale[ed2]
        
        if amount >= 64 {
            CQ.lo = Qh.hi >> (amount - 64)
            CQ.hi = 0
        } else {
            __shr_128(&CQ, Qh, amount)
        }
        
        expon = 0
        var Qh1 = UInt128()
        if prounding_mode != BID_ROUNDING_TO_NEAREST {
            if (CQ.lo & 1) != 0 {
                // check whether fractional part of initial_P/10^ed1 is exactly .5
                
                // get remainder
                
                __shl_128_long(&Qh1, Qh, (128 - amount))
                
                if (Qh1.hi == 0 && Qh1.lo == 0 && (Ql.hi < bid_reciprocals10_128[ed2].hi ||
                   (Ql.hi == bid_reciprocals10_128[ed2].hi && Ql.lo < bid_reciprocals10_128[ed2].lo))) {
                    CQ.lo-=1
                }
            }
        }
        
        if fpsc.contains(.inexact) {
            fpsc.insert(.underflow)
        } else {
            var status = Status.inexact
            // get remainder
            __shl_128_long(&Qh1, Qh, (128 - amount))
            
            switch prounding_mode {
                case BID_ROUNDING_TO_NEAREST, BID_ROUNDING_TIES_AWAY:
                    // test whether fractional part is 0
                    if (Qh1.hi == 0x8000000000000000 && (Qh1.lo == 0)
                        && (Ql.hi < bid_reciprocals10_128[ed2].hi
                            || (Ql.hi == bid_reciprocals10_128[ed2].hi
                                && Ql.lo < bid_reciprocals10_128[ed2].lo))) {
                        status = []
                    }
                case BID_ROUNDING_DOWN, BID_ROUNDING_TO_ZERO:
                    if ((Qh1.hi == 0) && (Qh1.lo == 0)
                        && (Ql.hi < bid_reciprocals10_128[ed2].hi
                            || (Ql.hi == bid_reciprocals10_128[ed2].hi
                                && Ql.lo < bid_reciprocals10_128[ed2].lo))) {
                        status = []
                    }
                default:
                    // round up
                    var Stemp = UInt128(), carry = UInt64(), CY = UInt64(), Tmp = UInt128(), Tmp1 = UInt128()
                    __add_carry_out(&Stemp.lo, &CY, Ql.lo, bid_reciprocals10_128[ed2].lo);
                    __add_carry_in_out(&Stemp.hi, &carry, Ql.hi, bid_reciprocals10_128[ed2].hi, CY)
                    __shr_128_long(&Qh, Qh1, (128 - amount))
                    Tmp.lo = 1
                    Tmp.hi = 0
                    __shl_128_long(&Tmp1, Tmp, amount)
                    Qh.lo += carry
                    if Qh.lo < carry {
                        Qh.hi+=1
                    }
                    if __unsigned_compare_ge_128 (Qh, Tmp1) {
                        status = []
                    }
            }
            
            if !status.isEmpty {
                fpsc.formUnion(status); fpsc.insert(.underflow)
            }
        }
        
        pres.hi = sgn | CQ.hi
        pres.lo = CQ.lo
        return pres
    }

    
    //
    //   General BID128 pack macro
    //
    static func bid_get_BID128(_ sgn:UInt64, _ expon:Int, _ coeff:UInt128, _ prounding_mode:Rounding, _ fpsc: inout Status) -> UInt128 {
        var pres = UInt128()
        var expon = expon
        var coeff = coeff
        
        // coeff==10^34?
        if coeff.hi == Ten34M1.hi && coeff.lo == 0x378d8e6400000000 {
            expon+=1
            // set coefficient to 10^33
            coeff.hi = 0x0000314dc6448d93
            coeff.lo = 0x38c15b0a00000000
        }
        // check OF, UF
        if expon < 0 || expon > MAX_EXPON {
            // check UF
            if expon < 0 {
                return handle_UF_128(sgn, expon, coeff, prounding_mode, &fpsc)
            }
            
            if expon - MAX_FORMAT_DIGITS_128 <= MAX_EXPON {
                let T = bid_power10_table_128[MAX_FORMAT_DIGITS_128 - 1];
                while __unsigned_compare_gt_128(T, coeff) && expon > MAX_EXPON {
                    coeff.hi = (coeff.hi << 3) + (coeff.hi << 1) + (coeff.lo >> 61) + (coeff.lo >> 63)
                    let tmp2 = coeff.lo << 3
                    coeff.lo = (coeff.lo << 1) + tmp2
                    if coeff.lo < tmp2 {
                        coeff.hi+=1
                    }
                    expon-=1
                }
            }
            if expon > MAX_EXPON {
                if (coeff.hi | coeff.lo) == 0 {
                    pres.hi = sgn | (UInt64(MAX_EXPON) << 49)
                    pres.lo = 0
                    return pres
                }
                // OF
                fpsc.formUnion([.overflow, .inexact])
                if (prounding_mode == BID_ROUNDING_TO_ZERO ||
                    (sgn != 0 && prounding_mode == BID_ROUNDING_UP) ||
                    (sgn == 0 && prounding_mode == BID_ROUNDING_DOWN))
                {
                    pres.hi = sgn | LARGEST_BID128_HIGH
                    pres.lo = LARGEST_BID128_LOW
                } else {
                    pres.hi = sgn | INFINITY_MASK64
                    pres.lo = 0
                }
                return pres
            }
        }
        
        pres.lo = coeff.lo
        let tmp = UInt64(expon) << 49
        pres.hi = sgn | tmp | coeff.hi
        return pres
    }
    
    //
    //   No overflow/underflow checks
    //
    static func bid_get_BID128_fast(_ sgn:UInt64, _ expon:Int, _ coeff:UInt128) -> UInt128 {
        var tmp:UInt64, expon = expon, coeff = coeff, pres = UInt128()
        
        // coeff==10^34?
        if (coeff.hi == Ten34M1.hi && coeff.lo == 0x378d8e6400000000) {
            expon+=1
            // set coefficient to 10^33
            coeff.hi = 0x0000314dc6448d93
            coeff.lo = 0x38c15b0a00000000
        }
        
        pres.lo = coeff.lo
        tmp = UInt64(expon)
        tmp <<= 49
        pres.hi = sgn | tmp | coeff.hi
        
        return pres
    }
    
    ///////////////////////////////////////////////////////////////////
    // return number of decimal digits in 128-bit value X
    ///////////////////////////////////////////////////////////////////
    static func __get_dec_digits64(_ X: UInt128) -> Int {
        if X.hi == 0 {
            if X.lo == 0 { return 0 }
            //--- get number of bits in the coefficients of x and y ---
            let tempx = Double(X.lo)
            let bin_expon_cx = Int((tempx.bitPattern & Decimal64.MASK_BINARY_EXPONENT) >> 52) - 0x3ff
            // get number of decimal digits in the coeff_x
            var digits_x = Int(bid_estimate_decimal_digits[bin_expon_cx])
            if X.lo >= bid_power10_table_128[digits_x].lo {
                digits_x+=1
            }
            return digits_x
        }
        let tempx = Double(X.hi)
        let bin_expon_cx = Int((tempx.bitPattern & Decimal64.MASK_BINARY_EXPONENT) >> 52) - 0x3ff
        // get number of decimal digits in the coeff_x
        var digits_x = Int(bid_estimate_decimal_digits[bin_expon_cx + 64])
        if __unsigned_compare_ge_128(X, bid_power10_table_128[digits_x]) {
            digits_x+=1
        }
        return digits_x
    }
    
    // **********************************************************************

    static func double_to_bid128 (_ x: Double, _ rnd_mode:Rounding, _ fpsc: inout Status) -> UInt128 {
        // Unpack the input
        var e = 0, s = 0, t = 0
        var c = UInt128()
        if let res = unpack_binary64 (x, &s, &e, &c.hi, &t, &fpsc) { return UInt128(w: [0, res]) }
        // Now -1126<=e<=971 (971 for max normal, -1074 for min normal, -1126 for min denormal)
        
        // Shift up to the top: like a pure quad coefficient with a shift of 15.
        // In our case, this is 2^{113-53+15} times the core, so unpack at the
        // high end shifted by 11.
        
        c.lo = 0;
        c.hi = c.hi << 11;
        
        t += (113 - 53);
        e -= (113 - 53); // Now e belongs [-1186;911].
        
        // (We never need to check for overflow: this format is the biggest of all!)
        
        // Now filter out all the exact cases where we need to specially force
        // the exponent to 0. We can let through inexact cases and those where the
        // main path will do the right thing anyway, e.g. integers outside coeff range.
        //
        // First check that e <= 0, because if e > 0, the input must be >= 2^113,
        // which is too large for the coefficient of any target decimal format.
        // We write a = -(e + t)
        //
        // (1) If e + t >= 0 <=> a <= 0 the input is an integer; treat it specially
        //     iff it fits in the coefficient range. Shift c' = c >> -e, and
        //     compare with the coefficient range; if it's in range then c' is
        //     our coefficient, exponent is 0. Otherwise we pass through.
        //
        // (2) If a > 0 then we have a non-integer input. The special case would
        //     arise as c' / 2^a where c' = c >> t, i.e. 10^-a * (5^a c'). Now
        //     if a > 48 we can immediately forget this, since 5^49 > 10^34.
        //     Otherwise we determine whether we're in range by a table based on
        //     a, and if so get the multiplier also from a table based on a.
        //
        // Note that when we shift, we need to take into account the fact that
        // c is already 15 places to the left in preparation for the reciprocal
        // multiplication; thus we add 15 to all the shift counts
        
        if e <= 0 {
            var cint = UInt128()
            let a = -(e + t)
            cint.hi = c.hi; cint.lo = c.lo;
            if (a <= 0) {
                cint = srl128(cint.hi, cint.lo, 15 - e)
                if (lt128 (cint.hi, cint.lo, 542101086242752, 4003012203950112768)) {
                    return return_bid128(s, 6176, cint.hi, cint.lo)
                }
            } else if (a <= 48) {
                var pow5 = bid_coefflimits_bid128[a];
                cint = srl128(cint.hi, cint.lo, 15 + t)
                if le128(cint.hi, cint.lo, pow5.hi, pow5.lo) {
                    var cc = UInt128()
                    cc.hi = cint.hi
                    cc.lo = cint.lo
                    pow5 = bid_power_five[a]
                    __mul_128x128_low(&cc, cc, pow5)
                    return return_bid128(s, 6176 - a, cc.hi, cc.lo)
                }
            }
        }
        // Input exponent can stretch between the maximal and minimal
        // exponents (remembering we force normalization): -16607 <= e <= 16271
        
        // Compute the estimated decimal exponent e_out; the provisional exponent
        // will be either "e_out" or "e_out-1" depending on later significand check
        // NB: this is the *biased* exponent
        
        let e_plus = e + 42152;
        var e_out = (((19728 * e_plus) + ((19779 * e_plus) >> 16)) >> 16) - 6512;
        
        // Set up pointers into the bipartite table
        
        var e_hi = 11232 - e_out;
        let e_lo = e_hi & 127;
        e_hi = e_hi >> 7;
        
        // Look up the inner entry first
        var r = bid_innertable_sig[e_lo], f = bid_innertable_exp[e_lo]
        
        // If we need the other entry, multiply significands and add exponents
        if e_hi != 39 {
            let s_prime = bid_outertable_sig[e_hi]
            var t_prime = UInt512()
            f = f + 256 + bid_outertable_exp[e_hi];
            __mul_256x256_to_512(&t_prime, r, s_prime);
            r.w[0] = t_prime.w[4] + 1; r.w[1] = t_prime.w[5]
            r.w[2] = t_prime.w[6]; r.w[3] = t_prime.w[7]
        }
        var z = UInt384()
        __mul_128x256_to_384(&z, c, r)
        
        // Make adjustive shift, ignoring the lower 128 bits
        e = -(241 + e + f)
        z = srl384_short(z.w[5], z.w[4], z.w[3], z.w[2], z.w[1], z.w[0], e)
        
        // Now test against 10^33 and so decide on adjustment
        // I feel there ought to be a smarter way of doing the multiplication
        if (lt128 (z.w[5], z.w[4], 54210108624275, 4089650035136921600)) {
            z = __mul_10x384_to_384(z.w[5], z.w[4], z.w[3], z.w[2], z.w[1], z.w[0])
            e_out = e_out - 1;
        }
        
        // Set up provisional results
        var c_prov_hi = z.w[5];
        var c_prov_lo = z.w[4];
        
        // Round using round-sticky words
        // If we spill over into the next decade, correct
        let rmode = roundboundIndex(rnd_mode, s != 0, Int(c_prov_lo))
        if lt128(bid_roundbound_128[rmode].hi, bid_roundbound_128[rmode].lo, z.w[3], z.w[2]) {
            c_prov_lo = c_prov_lo + 1;
            if c_prov_lo == 0 {
                c_prov_hi = c_prov_hi + 1;
            } else if (c_prov_lo == 4003012203950112768) && (c_prov_hi == 542101086242752) {
                c_prov_hi = 54210108624275;
                c_prov_lo = 4089650035136921600;
                e_out = e_out + 1;
            }
        }
        // Don't need to check overflow or underflow; however set inexact flag
        
        if (z.w[3] != 0) || (z.w[2] != 0) {
            fpsc.insert(.inexact)
        }
        
        // Package up the result
        return return_bid128(s, e_out, c_prov_hi, c_prov_lo)
    }
    
    // **********************************************************************
    
    static func bid128_to_double (_ px: UInt128, _ rnd_mode:Rounding, _ pfpsf: inout Status) -> Double {
        var s = 0, e = 0, k = 0, c = UInt128()
        if let res = unpack_bid128(px, &s, &e, &k, &c, &pfpsf) { return res }
        
        // Shift 6 more places left ready for reciprocal multiplication
        c = sll128_short(c.hi, c.lo, 6)
        
        // Check for "trivial" overflow, when 10^e * 1 > 2^{sci_emax+1}, just to
        // keep tables smaller (it would be intercepted later otherwise).
        //
        // (Note that we may have normalized the coefficient, but we have a
        //  corresponding exponent postcorrection to account for; this can
        //  afford to be conservative anyway.)
        //
        // We actually check if e >= ceil((sci_emax + 1) * log_10(2))
        // which in this case is 2 >= ceil(1024 * log_10(2)) = ceil(308.25) = 309
        if e >= 309 {
            pfpsf.insert(.inexact)
            return return_double_ovf(s, rnd_mode)
        }
        
        // Also check for "trivial" underflow, when 10^e * 2^113 <= 2^emin * 1/4,
        // so test e <= floor((emin - 115) * log_10(2))
        // In this case just fix ourselves at that value for uniformity.
        //
        // This is important not only to keep the tables small but to maintain the
        // testing of the round/sticky words as a correct rounding method
        if e <= -358 {
            e = -358
        }
        
        // Look up the breakpoint and approximate exponent
        let m_min = bid_breakpoints_binary64[e+358]
        var e_out = bid_exponents_binary64[e+358] - k;
        
        // Choose provisional exponent and reciprocal multiplier based on breakpoint
        var r = UInt256()
        if le128(c.hi, c.lo, m_min.hi, m_min.lo) {
            r = bid_multipliers1_binary64[e+358]
        } else {
            r = bid_multipliers2_binary64[e+358]
            e_out = e_out + 1
        }
        
        // Do the reciprocal multiplication
        var z = UInt384()
        __mul_128x256_to_384(&z, c, r)
        // Check for exponent underflow and compensate by shifting the product
        // Cut off the process at precision+2, since we can't really shift further
        if e_out < 1 {
            var d = 1 - e_out
            if (d > 55) {
                d = 55
            }
            e_out = 1
            let t = srl256_short(z.w[5], z.w[4], z.w[3], z.w[2], d)
            z.w[2...5] = t.w[0...]
        }
        var c_prov = z.w[5]
        
        // Round using round-sticky words
        // If we spill into the next binade, correct
        // Flag underflow where it may be needed even for |result| = SNN
        let rmode = roundboundIndex(rnd_mode, s != 0, Int(c_prov))
        if lt128(bid_roundbound_128[rmode].hi, bid_roundbound_128[rmode].lo, z.w[4], z.w[3]) {
            c_prov = c_prov + 1;
            if (c_prov == (1 << 53)) {
                c_prov = 1 << 52;
                e_out = e_out + 1;
            } else if ((c_prov == (1 << 52)) && (e_out == 1)) {
                if (((rmode & 3) == 0) && (z.w[4] < (3 << 62))) || ((rmode + (s & 1) == 2) && (z.w[4] < (1 << 63))) {
                    pfpsf.insert(.underflow)
                }
            }
        }
        
        // Check for overflow
        if e_out >= 2047 {
            pfpsf.insert(.inexact)
            return return_double_ovf(s, rnd_mode)
        }
        
        // Modify exponent for a tiny result, otherwise lop the implicit bit
        if c_prov < (1 << 52) {
            e_out = 0
        } else {
            c_prov = c_prov & ((1 << 52) - 1)
        }
        
        // Set the inexact and underflow flag as appropriate
        if (z.w[4] != 0) || (z.w[3] != 0) {
            pfpsf.insert(.inexact)
            if (e_out == 0) {
                pfpsf.insert(.underflow)
            }
        }
        
        // Package up the result as a binary floating-point number
        return return_double(s, e_out, c_prov)
    }

    static func unpack_bid128(_ x:UInt128, _ s:inout Int, _ e:inout Int, _ k:inout Int, _ c:inout UInt128, _ pfpsf: inout Status) -> Double? {
        s = Int(x.hi >> 63)
        if x.hi & (3<<61) == (3<<61) {
            if x.hi & (0xF<<59) == (0xF<<59) {
                if x.hi & (0x1F<<58) != (0x1F<<58) { return return_double_inf(s) /*inf*/ }
                if x.hi & (1<<57) != 0 {
                    pfpsf.insert(.invalidOperation)
                }
                if lt128(54210108624275,4089650035136921599,x.hi & 0x3FFFFFFFFFFF,x.lo) {
                    return return_double_nan(s, 0, 0) /* nan(s,0,0) */
                }
                return return_double_nan(s, (x.hi<<18)+(x.lo>>46), (x.lo<<18))
            }
            return return_double_zero(s) /* zero; */
        } else {
            e = Int((x.hi >> 49) & ((1<<14)-1)) - 6176;
            c.hi = x.hi & ((1<<49)-1);
            c.lo = x.lo;
            if (lt128(542101086242752,4003012203950112767, c.hi,c.lo)) {
                c.hi = 0; c.lo = 0
            }
            if (c.hi == 0) && (c.lo == 0) { return return_double_zero(s) /* zero */ }
            let k = clz128_nz(c.hi,c.lo) - 15
            c = sll128(c.hi,c.lo,k)
            return nil
        }
    }
    
    static func bid128_from_int64(_ x: Int64) -> UInt128 {
        var res = UInt128()
        
        // if integer is negative, use the absolute value
        if x < 0 {
            res.hi = 0xb040000000000000
        } else {
            res.hi = 0x3040000000000000
        }
        res.lo = x.magnitude
        return res
    }
    
    //
    //   No overflow/underflow checks
    //   No checking for coefficient == 10^34 (rounding artifact)
    //
    static func bid_get_BID128_very_fast(_ sgn:UInt64, _ expon:Int, _ coeff:UInt128) -> UInt128 {
        var pres = UInt128()
        pres.lo = coeff.lo
        let tmp = UInt64(expon << 49)
        pres.hi = sgn | tmp | coeff.hi
        return pres
    }
    

    
    /*
     * Takes a BID128 as input and converts it to a BID64 and returns it.
     */
    static func bid128_to_bid64(_ x: UInt128, _ rnd_mode:Rounding, _ pfpsf: inout Status) -> UInt64 {
        var x = x
        var res = UInt64(), uf_check = false, carry = UInt64()
        BID_SWAP128(&x)
        
        // unpack arguments, check for NaN or Infinity or 0
        var sign_x = UInt64(), exponent_x = 0, CX = UInt128(), Tmp = UInt128(), Tmp1 = UInt128()
        var TP128 = UInt128(), Qh = UInt128(), Ql = UInt128(), Qh1 = UInt128(), T128 = UInt128()
        var CX1 = UInt128()
        if !unpack_BID128_value (&sign_x, &exponent_x, &CX, x) {
            if (x.hi << 1) >= 0xf000000000000000 {
                Tmp.hi = CX.hi & 0x00003fffffffffff
                Tmp.lo = CX.lo
                TP128 = bid_reciprocals10_128[18]
                __mul_128x128_full(&Qh, &Ql, Tmp, TP128)
                let amount = bid_recip_scale[18]
                __shr_128(&Tmp, Qh, amount)
                res = (CX.hi & 0xfc00000000000000) | Tmp.lo
                if (x.hi & Decimal64.SNAN_MASK64) == Decimal64.SNAN_MASK64 {   // sNaN
                    pfpsf.insert(.invalidOperation)
                }
                return res
            }
            exponent_x = exponent_x - EXPONENT_BIAS + Decimal64.EXPONENT_BIAS
            if exponent_x < 0 {
                return sign_x
            }
            if exponent_x > Decimal64.MAX_EXPON {
                exponent_x = Decimal64.MAX_EXPON
            }
            return sign_x | (UInt64(exponent_x) << 53)
        }
        
        if CX.hi != 0 || (CX.lo >= 10000000000000000) {
            // find number of digits in coefficient
            // 2^64
            let f64 = Float(bitPattern: 0x5f800000)
            
            // fx ~ CX
            let fx = Float(CX.hi) * f64 + Float(CX.lo)
            let bin_expon_cx = Int((fx.bitPattern >> 23) & 0xff) - 0x7f
            var extra_digits = Int(bid_estimate_decimal_digits[bin_expon_cx]) - 16
            
            // scale = 38-estimate_decimal_digits[bin_expon_cx];
            let D = CX.hi - bid_power10_index_binexp_128[bin_expon_cx].hi
            if D > 0 || (D == 0 && CX.lo >= bid_power10_index_binexp_128[bin_expon_cx].lo) {
                extra_digits+=1
            }
            
            exponent_x += extra_digits
            
            var rmode = roundboundIndex(rnd_mode) >> 2
            if sign_x != 0 && UInt(rmode - 1) < 2 {
                rmode = 3 - rmode
            }
            
            if exponent_x < EXPONENT_BIAS - Decimal64.EXPONENT_BIAS {
                uf_check = true
                if -extra_digits + exponent_x - EXPONENT_BIAS + Decimal64.EXPONENT_BIAS + 35 >= 0 {
                    if (exponent_x == EXPONENT_BIAS - Decimal64.EXPONENT_BIAS - 1) {
                        T128 = bid_round_const_table_128[rmode][extra_digits];
                        __add_carry_out(&CX1.lo, &carry, T128.lo, CX.lo);
                        CX1.hi = CX.hi + T128.hi + carry;
                        if __unsigned_compare_ge_128(CX1, bid_power10_table_128[extra_digits + 16]) {
                            uf_check = false
                        }
                    }
                    extra_digits += EXPONENT_BIAS - Decimal64.EXPONENT_BIAS - exponent_x
                    exponent_x = EXPONENT_BIAS - Decimal64.EXPONENT_BIAS;
                    //uf_check = 2;
                } else {
                    rmode = roundboundIndex(BID_ROUNDING_TO_ZERO) >> 2
                }
            }
            
            T128 = bid_round_const_table_128[rmode][extra_digits]
            __add_carry_out(&CX.lo, &carry, T128.lo, CX.lo)
            CX.hi = CX.hi + T128.hi + carry
            
            TP128 = bid_reciprocals10_128[extra_digits]
            __mul_128x128_full(&Qh, &Ql, CX, TP128)
            let amount = bid_recip_scale[extra_digits]
            
            if (amount >= 64) {
                CX.lo = Qh.hi >> (amount - 64);
                CX.hi = 0;
            } else {
                __shr_128(&CX, Qh, amount)
            }
            
            if rnd_mode != BID_ROUNDING_TO_NEAREST {
                if (CX.lo & 1) != 0 {
                    // check whether fractional part of initial_P/10^ed1 is exactly .5
                    
                    // get remainder
                    __shl_128_long(&Qh1, Qh, (128 - amount))
                    
                    if (Qh1.hi == 0 && Qh1.lo == 0
                        && (Ql.hi < bid_reciprocals10_128[extra_digits].hi
                            || (Ql.hi == bid_reciprocals10_128[extra_digits].hi
                                && Ql.lo < bid_reciprocals10_128[extra_digits].lo))) {
                        CX.lo-=1
                    }
                }
            }
            
            var status = Status.inexact
            // get remainder
            __shl_128_long(&Qh1, Qh, (128 - amount))
            
            switch rnd_mode {
                case BID_ROUNDING_TO_NEAREST, BID_ROUNDING_TIES_AWAY:
                    // test whether fractional part is 0
                    if (Qh1.hi == 0x8000000000000000 && (Qh1.lo == 0)
                        && (Ql.hi < bid_reciprocals10_128[extra_digits].hi
                            || (Ql.hi == bid_reciprocals10_128[extra_digits].hi
                                && Ql.lo < bid_reciprocals10_128[extra_digits].lo))) {
                        status = []
                    }
                case BID_ROUNDING_DOWN, BID_ROUNDING_TO_ZERO:
                    if ((Qh1.hi == 0) && (Qh1.lo == 0)
                        && (Ql.hi < bid_reciprocals10_128[extra_digits].hi
                            || (Ql.hi == bid_reciprocals10_128[extra_digits].hi
                                && Ql.lo < bid_reciprocals10_128[extra_digits].lo))) {
                        status = []
                    }
                default:
                    // round up
                    var Stemp = UInt128(), cy = UInt64()
                    __add_carry_out(&Stemp.lo, &cy, Ql.lo, bid_reciprocals10_128[extra_digits].lo);
                    __add_carry_in_out(&Stemp.hi, &carry, Ql.hi, bid_reciprocals10_128[extra_digits].hi, cy);
                    __shr_128_long(&Qh, Qh1, (128 - amount))
                    Tmp.lo = 1
                    Tmp.hi = 0
                    __shl_128_long(&Tmp1, Tmp, amount)
                    Qh.lo += carry
                    if Qh.lo < carry {
                        Qh.hi+=1
                    }
                    if __unsigned_compare_ge_128 (Qh, Tmp1) {
                        status = []
                    }
            }
            
            if !status.isEmpty {
                if uf_check {
                    status.insert(.underflow)
                }
                pfpsf.formUnion(status)
            }
        }
        return Decimal64.get_BID64 (sign_x, exponent_x - EXPONENT_BIAS + Decimal64.EXPONENT_BIAS,
                                    CX.lo, rnd_mode, &pfpsf);
    }
    
    static func bid_to_dpd128 (_ ba:UInt128) -> UInt128 {
        var nanb = UInt64(), res = UInt128(), sign = UInt128(), comb = UInt32(), exp = UInt32(), trailing = UInt128()
        var bcoeff = UInt128(), dcoeff = UInt128()
        
        sign.hi = ba.hi & MASK_SIGN
        sign.lo = 0
        comb = UInt32((ba.hi & 0x7fffc00000000000) >> 46)
        trailing.hi = ba.hi & 0x00003fffffffffff
        trailing.lo = ba.lo
        exp = 0
        
        if (comb & 0x1f000) == 0x1e000 {    // G0..G4 = 11110 -> Inf
            res.hi = ba.hi & 0xf800000000000000
            res.lo = 0
            return res
            // Detect NaN, and canonicalize trailing
        } else if (comb & 0x1f000) == 0x1f000 {
            if (trailing.hi > 0x0000314dc6448d93) || ((trailing.hi == 0x0000314dc6448d93) && (trailing.lo >= 0x38c15b0a00000000)) {
                // significand is non-canonical
                trailing.hi = 0; trailing.lo = 0
            }
            bcoeff = trailing
            nanb = ba.hi & 0xfe00000000000000
            exp = 0
        } else {    // Normal number
            if (comb & 0x18000) == 0x18000 {    // G0..G1 = 11 -> exp is G2..G11
                exp = (comb >> 1) & 0x3fff
                bcoeff.hi = (UInt64(8 + (comb & 1)) << 46) | trailing.hi
                bcoeff.lo = trailing.lo
            } else {
                exp = (comb >> 3) & 0x3fff
                bcoeff.hi = (UInt64(comb & 7) << 46) | trailing.hi
                bcoeff.lo = trailing.lo
            }
            // Zero the coefficient if non-canonical (>= 10^34)
            if bcoeff.hi > 0x1ed09bead87c0 || (bcoeff.hi == 0x1ed09bead87c0 && bcoeff.lo >= 0x378D8E6400000000) {
                bcoeff.lo = 0; bcoeff.hi = 0
            }
        }
        
        // Constant 2^128 / 1000 + 1
        var d1000 = UInt128(), b11 = UInt128(), b10 = UInt128(), b9 = UInt128(), b8 = UInt128()
        var b7 = UInt128(), b6 = UInt128(), b5 = UInt128(), b4 = UInt128(), b3 = UInt128()
        var b2 = UInt128(), b1 = UInt128(), t2 = UInt64(), t = UInt128()
        var d0 = UInt128(), d1 = UInt128(), d2 = UInt128(), d3 = UInt128(), d4 = UInt128()
        var d5 = UInt128(), d6 = UInt128(), d7 = UInt128(), d8 = UInt128(), d9 = UInt128()
        var d10 = UInt128(), d11 = UInt128()
        d1000.hi = 0x4189374BC6A7EF
        d1000.lo = 0x9DB22D0E56041894
        __mul_128x128_high (&b11, bcoeff, d1000);
        __mul_128x128_high (&b10, b11, d1000);
        __mul_128x128_high (&b9, b10, d1000);
        __mul_128x128_high (&b8, b9, d1000);
        __mul_128x128_high (&b7, b8, d1000);
        __mul_128x128_high (&b6, b7, d1000);
        __mul_128x128_high (&b5, b6, d1000);
        __mul_128x128_high (&b4, b5, d1000);
        __mul_128x128_high (&b3, b4, d1000);
        __mul_128x128_high (&b2, b3, d1000);
        __mul_128x128_high (&b1, b2, d1000);
        
        __mul_64x128_full (&t2, &t, 1000, b11);
        __sub_128_128 (&d11, bcoeff, t);
        __mul_64x128_full (&t2, &t, 1000, b10);
        __sub_128_128 (&d10, b11, t);
        __mul_64x128_full (&t2, &t, 1000, b9);
        __sub_128_128 (&d9, b10, t);
        __mul_64x128_full (&t2, &t, 1000, b8);
        __sub_128_128 (&d8, b9, t);
        __mul_64x128_full (&t2, &t, 1000, b7);
        __sub_128_128 (&d7, b8, t);
        __mul_64x128_full (&t2, &t, 1000, b6);
        __sub_128_128 (&d6, b7, t);
        __mul_64x128_full (&t2, &t, 1000, b5);
        __sub_128_128 (&d5, b6, t);
        __mul_64x128_full (&t2, &t, 1000, b4);
        __sub_128_128 (&d4, b5, t);
        __mul_64x128_full (&t2, &t, 1000, b3);
        __sub_128_128 (&d3, b4, t);
        __mul_64x128_full (&t2, &t, 1000, b2);
        __sub_128_128 (&d2, b3, t);
        __mul_64x128_full (&t2, &t, 1000, b1);
        __sub_128_128 (&d1, b2, t);
        d0 = b1
        
        dcoeff.lo = bid_b2d[Int(d11.lo)] | (bid_b2d[Int(d10.lo)] << 10) |
            (bid_b2d[Int(d9.lo)] << 20) | (bid_b2d[Int(d8.lo)] << 30) | (bid_b2d[Int(d7.lo)] << 40) |
            (bid_b2d[Int(d6.lo)] << 50) | (bid_b2d[Int(d5.lo)] << 60);
        dcoeff.hi = (bid_b2d[Int(d5.lo)] >> 4) | (bid_b2d[Int(d4.lo)] << 6) | (bid_b2d[Int(d3.lo)] << 16) |
            (bid_b2d[Int(d2.lo)] << 26) | (bid_b2d[Int(d1.lo)] << 36);
        
        res.lo = dcoeff.lo
        if d0.lo >= 8 {
            res.hi = sign.hi | ((UInt64(0x18000) | (UInt64(exp >> 12) << 13) | ((d0.lo & 1) << 12) | UInt64(exp & 0xfff)) << 46) | dcoeff.hi;
        } else {
            res.hi = sign.hi | (((UInt64(exp >> 12) << 15) | (d0.lo << 12) | UInt64(exp & 0xfff)) << 46) | dcoeff.hi;
        }
        
        res.hi |= nanb
        BID_SWAP128 (&res)
        return res
    }


    static func dpd_to_bid128 (_ da:UInt128) -> UInt128 {
        var sign = UInt128(), exp = UInt64(), comb = UInt64(), res = UInt128()
        var trailing = UInt128(), nanb = UInt64(), d0 = UInt64(), bcoeff = UInt128()
        sign.hi = da.hi & 0x8000000000000000
        sign.lo = 0
        comb = (da.hi & 0x7fffc00000000000) >> 46;
        trailing.hi = da.hi & 0x00003fffffffffff
        trailing.lo = da.lo
        exp = 0
        
        if ((comb & 0x1f000) == 0x1e000) {    // G0..G4 = 11110 -> Inf
            res.hi = da.hi & 0xf800000000000000;
            res.lo = 0;
            return res
        } else if ((comb & 0x1f000) == 0x1f000) {    // G0..G4 = 11111 -> NaN
            nanb = da.hi & 0xfe00000000000000;
            exp = 0;
            d0 = 0;
        } else {    // Normal number
            if ((comb & 0x18000) == 0x18000) {    // G0..G1 = 11 -> d0 = 8 + G4
                d0 = 8 + (comb & 0x01000 != 0 ? 1 : 0);
                exp = (comb & 0x04000 != 0 ? 1 : 0) * 0x2000 + (comb & 0x02000 != 0 ? 1 : 0) * 0x1000;
                // exp leading bits are G2..G3
            } else {
                d0 = 4 * (comb & 0x04000 != 0 ? 1 : 0) + 2 * (comb & 0x2000 != 0 ? 1 : 0) + (comb & 0x1000 != 0 ? 1 : 0);
                exp = (comb & 0x10000 != 0 ? 1 : 0) * 0x2000 + (comb & 0x08000 != 0 ? 1 : 0) * 0x1000;
                // exp loading bits are G0..G1
            }
        }
        
        let d11 = bid_d2b[Int(trailing.lo & 0x3ff)]
        let d10 = bid_d2b[Int(trailing.lo >> 10 & 0x3ff)]
        let d9 =  bid_d2b[Int(trailing.lo >> 20) & 0x3ff]
        let d8 =  bid_d2b[Int(trailing.lo >> 30) & 0x3ff]
        let d7 =  bid_d2b[Int(trailing.lo >> 40) & 0x3ff]
        let d6 =  bid_d2b[Int(trailing.lo >> 50) & 0x3ff]
        let d5 =  bid_d2b[Int(trailing.lo >> 60) | ((Int(trailing.hi) & 0x3f) << 4)]
        let d4 =  bid_d2b[Int(trailing.hi >> 6) & 0x3ff]
        let d3 =  bid_d2b[Int(trailing.hi >> 16) & 0x3ff]
        let d2 =  bid_d2b[Int(trailing.hi >> 26) & 0x3ff]
        let d1 =  bid_d2b[Int(trailing.hi >> 36) & 0x3ff]
        
        let tl = d11 + (d10 * 1000) + (d9 * 1000000) + (d8 * 1000000000) + (d7 * 1000000000000) + (d6 * 1000000000000000)
        let th = d5 + (d4 * 1000) + (d3 * 1000000) + (d2 * 1000000000) + (d1 * 1000000000000) + (d0 * 1000000000000000)
        __mul_64x64_to_128 (&bcoeff, th, 1000000000000000000)
        __add_128_64 (&bcoeff, bcoeff, tl)
        
        if nanb == 0 {
            exp += comb & 0xfff
        }
        
        res.lo = bcoeff.lo
        res.hi = (exp << 49) | sign.hi | bcoeff.hi
        res.hi |= nanb
        
        BID_SWAP128(&res)
        return res
    }
    
    /*****************************************************************************
     *  BID128_to_int64_int
     ****************************************************************************/
    
    static func bid128_to_int( _ x:UInt128, _ pfpsf: inout Status) -> Int {
        // unpack x
        let x_sign = x.hi & MASK_SIGN;    // 0 for positive, MASK_SIGN for negative
        let x_exp = x.hi & MASK_EXP;    // biased and shifted left 49 bit positions
        var C1 = UInt128(), C = UInt128(), res = 0, Cstar = UInt128(), P256 = UInt256()
        C1.hi = x.hi & MASK_COEFF
        C1.lo = x.lo
        
        // check for NaN or Infinity
        if (x.hi & MASK_SPECIAL) == MASK_SPECIAL {
            // x is special
            if (x.hi & MASK_NAN) == MASK_NAN {    // x is NAN
                if (x.hi & MASK_SNAN) == MASK_SNAN {    // x is SNAN
                    // set invalid flag
                    pfpsf.insert(.invalidOperation)
                    // return Integer Indefinite
                    res = Int(bitPattern: UInt(0x8000000000000000))
                } else {    // x is QNaN
                    // set invalid flag
                    pfpsf.insert(.invalidOperation)
                    // return Integer Indefinite
                    res = Int(bitPattern: UInt(0x8000000000000000))
                }
                return res
            } else {    // x is not a NaN, so it must be infinity
                if x_sign == 0 {    // x is +inf
                    // set invalid flag
                    pfpsf.insert(.invalidOperation)
                    // return Integer Indefinite
                    res = Int(bitPattern: UInt(0x8000000000000000))
                } else {    // x is -inf
                    // set invalid flag
                    pfpsf.insert(.invalidOperation)
                    // return Integer Indefinite
                    res = Int(bitPattern: UInt(0x8000000000000000))
                }
                return res
            }
        }
        // check for non-canonical values (after the check for special values)
        if ((C1.hi > Ten34M1.hi) || (C1.hi == Ten34M1.hi && (C1.lo > Ten34M1.lo))
            || ((x.hi & MASK_STEERING_BITS) == MASK_STEERING_BITS)) {
            return 0x0
        } else if (C1.hi == 0) && (C1.lo == 0) {
            // x is 0
            return 0x0
        } else {    // x is not special and is not zero
            
            // q = nr. of decimal digits in x
            //  determine first the nr. of bits in x
            let q = digitsIn(C1.hi, lo: C1.lo)
//            var x_nr_bits = 0, tmp1:Double
//            if (C1.hi == 0) {
//                if (C1.lo >= 0x0020000000000000) {    // x >= 2^53
//                    // split the 64-bit value in two 32-bit halves to avoid rounding errors
//                    tmp1 = Double(C1.lo >> 32)    // exact conversion
//                    x_nr_bits = 33 + ((Int(tmp1.bitPattern >> 52)) & 0x7ff) - 0x3ff
//                } else {    // if x < 2^53
//                    tmp1 = Double(C1.lo)    // exact conversion
//                    x_nr_bits = 1 + ((Int(tmp1.bitPattern >> 52)) & 0x7ff) - 0x3ff
//                }
//            } else {    // C1.hi != 0 => nr. bits = 64 + nr_bits (C1.hi)
//                tmp1 = Double(C1.hi)    // exact conversion
//                x_nr_bits = 65 + ((Int(tmp1.bitPattern >> 52)) & 0x7ff) - 0x3ff
//            }
//            var q = Int(bid_nr_digits[x_nr_bits - 1].digits)
//            if q == 0 {
//                q = Int(bid_nr_digits[x_nr_bits - 1].digits1)
//                if (C1.hi > bid_nr_digits[x_nr_bits - 1].threshold_hi
//                    || (C1.hi == bid_nr_digits[x_nr_bits - 1].threshold_hi
//                        && C1.lo >= bid_nr_digits[x_nr_bits - 1].threshold_lo)) {
//                    q+=1
//                }
//            }
            let exp = Int(x_exp >> 49) - 6176
            if (q + exp) > 19 {    // x >= 10^19 ~= 2^63.11... (cannot fit in BID_SINT64)
                // set invalid flag
                pfpsf.insert(.invalidOperation)
                // return Integer Indefinite
                res = Int(bitPattern: UInt(0x8000000000000000))
            } else if (q + exp) == 19 {    // x = c(0)c(1)...c(18).c(19)...c(q-1)
                // in this case 2^63.11... ~= 10^19 <= x < 10^20 ~= 2^66.43...
                // so x rounded to an integer may or may not fit in a signed 64-bit int
                // the cases that do not fit are identified here; the ones that fit
                // fall through and will be handled with other cases further,
                // under '1 <= q + exp <= 19'
                if x_sign != 0 {    // if n < 0 and q + exp = 19
                    // if n <= -2^63 - 1 then n is too large
                    // too large if c(0)c(1)...c(18).c(19)...c(q-1) >= 2^63+1
                    // <=> 0.c(0)c(1)...c(q-1) * 10^20 >= 5*(2^64+2), 1<=q<=34
                    // <=> 0.c(0)c(1)...c(q-1) * 10^20 >= 0x5000000000000000a, 1<=q<=34
                    C.hi = 0x0000000000000005
                    C.lo = 0x000000000000000a
                    if q <= 19 {    // 1 <= q <= 19 => 1 <= 20-q <= 19 =>
                        // 10^(20-q) is 64-bit, and so is C1
                        __mul_64x64_to_128MACH(&C1, C1.lo, bid_ten2k64[20 - q]);
                    } else if q == 20 {
                        // C1 * 10^0 = C1
                    } else {    // if 21 <= q <= 34
                        __mul_128x64_to_128(&C, bid_ten2k64[q - 20], C);    // max 47-bit x 67-bit
                    }
                    if C1.hi > C.hi || (C1.hi == C.hi && C1.lo >= C.lo) {
                        // set invalid flag
                        pfpsf.insert(.invalidOperation)
                        // return Integer Indefinite
                        res = Int(bitPattern: UInt(0x8000000000000000))
                    }
                    // else cases that can be rounded to a 64-bit int fall through
                    // to '1 <= q + exp <= 19'
                } else {    // if n > 0 and q + exp = 19
                    // if n >= 2^63 then n is too large
                    // too large if c(0)c(1)...c(18).c(19)...c(q-1) >= 2^63
                    // <=> if 0.c(0)c(1)...c(q-1) * 10^20 >= 5*2^64, 1<=q<=34
                    // <=> if 0.c(0)c(1)...c(q-1) * 10^20 >= 0x50000000000000000, 1<=q<=34
                    C.hi = 0x5
                    C.lo = 0x0
                    if (q <= 19) {    // 1 <= q <= 19 => 1 <= 20-q <= 19 =>
                        // 10^(20-q) is 64-bit, and so is C1
                        __mul_64x64_to_128MACH(&C1, C1.lo, bid_ten2k64[20 - q]);
                    } else if (q == 20) {
                        // C1 * 10^0 = C1
                    } else {    // if 21 <= q <= 34
                        __mul_128x64_to_128(&C, bid_ten2k64[q - 20], C);    // max 47-bit x 67-bit
                    }
                    if (C1.hi > C.hi || (C1.hi == C.hi && C1.lo >= C.lo)) {
                        // set invalid flag
                        pfpsf.insert(.invalidOperation)
                        // return Integer Indefinite
                        res = Int(bitPattern: UInt(0x8000000000000000))
                    }
                    // else cases that can be rounded to a 64-bit int fall through
                    // to '1 <= q + exp <= 19'
                }
            }
            // n is not too large to be converted to int64: -2^63-1 < n < 2^63
            // Note: some of the cases tested for above fall through to this point
            // Restore C1 which may have been modified above
            C1.hi = x.hi & MASK_COEFF
            C1.lo = x.lo
            if (q + exp) <= 0 {    // n = +/-0.[0...0]c(0)c(1)...c(q-1)
                // return 0
                return 0
            } else {    // if (1 <= q + exp <= 19, 1 <= q <= 34, -33 <= exp <= 18)
                // -2^63-1 < x <= -1 or 1 <= x < 2^63 so x can be rounded
                // toward zero to a 64-bit signed integer
                if exp < 0 {    // 2 <= q <= 34, -33 <= exp <= -1, 1 <= q + exp <= 19
                    let ind = -exp    // 1 <= ind <= 33; ind is a synonym for 'x'
                    // chop off ind digits from the lower part of C1
                    // C1 fits in 127 bits
                    // calculate C* and f*
                    // C* is actually floor(C*) in this case
                    // C* and f* need shifting and masking, as shown by
                    // bid_shiftright128[] and bid_maskhigh128[]
                    // 1 <= x <= 33
                    // kx = 10^(-x) = bid_ten2mk128[ind - 1]
                    // C* = C1 * 10^(-x)
                    // the approximation of 10^(-x) was rounded up to 118 bits
                    __mul_128x128_to_256 (&P256, C1, bid_ten2mk128[ind - 1]);
                    if (ind - 1 <= 21) {    // 0 <= ind - 1 <= 21
                        Cstar.hi = P256.w[3];
                        Cstar.lo = P256.w[2];
                    } else {    // 22 <= ind - 1 <= 33
                        Cstar.hi = 0;
                        Cstar.lo = P256.w[3];
                    }
                    // the top Ex bits of 10^(-x) are T* = bid_ten2mk128trunc[ind], e.g.
                    // if x=1, T*=bid_ten2mk128trunc[0]=0x19999999999999999999999999999999
                    // C* = floor(C*) (logical right shift; C has p decimal digits,
                    //     correct by Property 1)
                    // n = C* * 10^(e+x)
                    
                    // shift right C* by Ex-128 = bid_shiftright128[ind]
                    let shift = bid_shiftright128[ind - 1];    // 0 <= shift <= 102
                    if (ind - 1 <= 21) {    // 0 <= ind - 1 <= 21
                        Cstar.lo = (Cstar.lo >> shift) | (Cstar.hi << (64 - shift));
                        // redundant, it will be 0! Cstar.hi = (Cstar.hi >> shift);
                    } else {    // 22 <= ind - 1 <= 33
                        Cstar.lo = (Cstar.lo >> (shift - 64));    // 2 <= shift - 64 <= 38
                    }
                    if x_sign != 0 {
                        res = -Int(Cstar.lo)
                    } else {
                        res = Int(Cstar.lo)
                    }
                } else if exp == 0 {
                    // 1 <= q <= 19
                    // res = +/-C (exact)
                    if x_sign != 0 {
                        res = -Int(C1.lo)
                    } else {
                        res = Int(C1.lo)
                    }
                } else {    // if (exp>0) => 1 <= exp <= 18, 1 <= q < 18, 2 <= q + exp <= 19
                    // res = +/-C * 10^exp (exact) where this fits in 64-bit integer
                    if x_sign != 0 {
                        res = -Int(C1.lo * bid_ten2k64[exp])
                    } else {
                        res = Int(C1.lo * bid_ten2k64[exp])
                    }
                }
            }
        }
        return res
    }
    
    //
    //  BID128 unpack, input pased by reference
    //
    static func unpack_BID128(_ psign_x:inout UInt64, _ pexponent_x:inout Int, _ pcoefficient_x:inout UInt128, _ px:UInt128) -> Bool {
        psign_x = px.hi & MASK_SIGN // 0x8000000000000000
        
        // special encodings
        var ex:UInt64, coeff=UInt128()
        if (px.hi & INFINITY_MASK64) >= SPECIAL_ENCODING_MASK64 {
            if (px.hi & INFINITY_MASK64) < INFINITY_MASK64 {
                // non-canonical input
                pcoefficient_x.lo = 0
                pcoefficient_x.hi = 0
                ex = px.hi >> 47
                pexponent_x = Int(ex) & EXPONENT_MASK128
                return false
            }
            
            // 10^33
            let T33 = bid_power10_table_128[33]
            coeff.lo = px.lo
            coeff.hi = px.hi & LARGE_COEFF_MASK128
            pcoefficient_x = px
            if __unsigned_compare_ge_128 (coeff, T33) {    // non-canonical
                pcoefficient_x.hi &= (~LARGE_COEFF_MASK128)
                pcoefficient_x.lo = 0
            }
            pexponent_x = 0
            return false    // NaN or Infinity
        }
        
        coeff.lo = px.lo
        coeff.hi = px.hi & SMALL_COEFF_MASK128
        
        // 10^34
        let T34 = bid_power10_table_128[34]
        
        // check for non-canonical values
        if __unsigned_compare_ge_128(coeff, T34) {
            coeff.lo = 0; coeff.hi = 0
        }
        
        pcoefficient_x = coeff
        ex = px.hi >> 49
        pexponent_x = Int(ex) & EXPONENT_MASK128
        return (coeff.lo | coeff.hi) != 0
    }

}
