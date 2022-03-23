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
    static let DECIMAL_MAX_EXPON_128     = 12287
    static let DECIMAL_EXPONENT_BIAS_128 = 6176
    static let MAX_FORMAT_DIGITS_128     = 34
    static let MAX_STRING_DIGITS_128     = 100
    static let MAX_SEARCH                = MAX_STRING_DIGITS_128-MAX_FORMAT_DIGITS_128-1
    
    ////////////////////////////////////////
    // Constant Definitions
    ///////////////////////////////////////
    static let SMALL_COEFF_MASK128      = UInt64(0x0001_ffff_ffff_ffff)
    static let LARGE_COEFF_MASK128      = UInt64(0x0000_7fff_ffff_ffff)
    static let EXPONENT_MASK128         = 0x3fff
    static let LARGEST_BID128_HIGH      = UInt64(0x5fff_ed09_bead_87c0)
    static let LARGEST_BID128_LOW       = UInt64(0x378d_8e63_ffff_ffff)
    static let MASK_SPECIAL             = Decimal64.MASK_INF
    static let MASK_INF                 = Decimal64.MASK_INF
    static let INFINITY_MASK64          = Decimal64.MASK_INF
    static let MASK_NAN                 = Decimal64.MASK_NAN
    static let MASK_SNAN                = Decimal64.MASK_SNAN
    static let MASK_SIGN                = Decimal64.MASK_SIGN
    static let MASK_COEFF               = UInt64(0x0001_ffff_ffff_ffff)
    static let SPECIAL_ENCODING_MASK64  = Decimal64.SPECIAL_ENCODING_MASK64
    static let MASK_STEERING_BITS       = Decimal64.MASK_STEERING_BITS
    static let MASK_EXP                 = UInt64(0x7ffe000000000000)
    
    /*
     * Takes a BID128 as input and converts it to a BID32 and returns it.
     */
    static func BID128_to_BID32 (_ x: UInt128, _ rmode: Rounding, _ pfpsf: inout Status) -> UInt32 {
        var x = x
        BID_SWAP128(&x)
        // unpack arguments, check for NaN or Infinity or 0
        var sign_x = UInt64(0), exponent_x = 0, CX = UInt128()
        if !unpack_BID128_value (&sign_x, &exponent_x, &CX, x) {
            if (((x.w[1]) & Decimal64.INFINITY_MASK64) == Decimal64.INFINITY_MASK64) {
                var Tmp = UInt128()
                Tmp.w[1] = CX.w[1] & 0x0000_3fff_ffff_ffff
                Tmp.w[0] = CX.w[0]
                let TP128 = bid_reciprocals10_128[27]
                var Qh = UInt128(), Ql = UInt128()
                __mul_128x128_full(&Qh, &Ql, Tmp, TP128)
                let amount = bid_recip_scale[27] - 64
                let res = ((CX.w[1] >> 32) & 0xfc00_0000) | (Qh.w[1] >> amount)
                if ((x.w[1] & Decimal64.SNAN_MASK64) == Decimal64.SNAN_MASK64) {   // sNaN
                    pfpsf.insert(.invalidOperation)
                    // __set_status_flags (pfpsf, BID_INVALID_EXCEPTION);
                }
                return UInt32(res)
            }
            // x is 0
            exponent_x -= DECIMAL_EXPONENT_BIAS_128 + Decimal32.EXPONENT_BIAS;
            if exponent_x < 0 {
                exponent_x = 0
            }
            if exponent_x > Decimal32.MAX_EXPON {
                exponent_x = Decimal32.MAX_EXPON
            }
            let res = (sign_x >> 32) | UInt64(exponent_x << 23)
            return UInt32(res)
        }
        
        if CX.w[1] != 0 || CX.w[0] > Decimal32.MAX_NUMBER {
            // find number of digits in coefficient
            // 2^64
            let f64 = Float(bitPattern: 0x5f800000)
            
            // fx ~ CX
            let fx = Float(CX.w[1]) * f64 + Float(CX.w[0])
            let bin_expon_cx = Int((fx.bitPattern >> 23) & 0xff) - 0x7f
            var extra_digits = Int(bid_estimate_decimal_digits[bin_expon_cx]) - 7
            // scale = 38-estimate_decimal_digits[bin_expon_cx];
            let D = CX.w[1] - bid_power10_index_binexp_128[bin_expon_cx].w[1];
            if (D > 0 || ((D == 0) && CX.w[0] >= bid_power10_index_binexp_128[bin_expon_cx].w[0])) {
                extra_digits+=1
            }
            
            exponent_x += extra_digits
            
            var rmode1 = roundboundIndex(rmode, sign_x != 0, 0)
//            if (sign_x && (unsigned) (rmode - 1) < 2) {
//                rmode = 3 - rmode;
//            }
            
            var uf_check = false
            var carry = UInt64(), CX1 = UInt128(), T128 = UInt128()
            if (exponent_x < DECIMAL_EXPONENT_BIAS_128 - Decimal32.EXPONENT_BIAS) {
                uf_check = true
                if (-extra_digits + exponent_x - DECIMAL_EXPONENT_BIAS_128 + Decimal32.EXPONENT_BIAS + 35 >= 0) {
                    if (exponent_x == DECIMAL_EXPONENT_BIAS_128 - Decimal32.EXPONENT_BIAS - 1) {
                        T128 = bid_round_const_table_128[rmode1][extra_digits]
                        __add_carry_out (&CX1.w[0], &carry, T128.w[0], CX.w[0]);
                        CX1.w[1] = CX.w[1] + T128.w[1] + carry;
                        if __unsigned_compare_ge_128(CX1, bid_power10_table_128[extra_digits + 7]) {
                            uf_check = false
                        }
                    }
                    extra_digits +=  DECIMAL_EXPONENT_BIAS_128 - Decimal32.EXPONENT_BIAS - exponent_x;
                    exponent_x = DECIMAL_EXPONENT_BIAS_128 - Decimal32.EXPONENT_BIAS;
                } else {
                    rmode1 = roundboundIndex(BID_ROUNDING_TO_ZERO) >> 2
                }
            }
            
            T128 = bid_round_const_table_128[rmode1][extra_digits];
            __add_carry_out(&CX.w[0], &carry, T128.w[0], CX.w[0]);
            CX.w[1] = CX.w[1] + T128.w[1] + carry;
            
            let TP128 = bid_reciprocals10_128[extra_digits]
            var Qh = UInt128(), Ql = UInt128()
            __mul_128x128_full(&Qh, &Ql, CX, TP128);
            let amount = bid_recip_scale[extra_digits];
            
            if (amount >= 64) {
                CX.w[0] = Qh.w[1] >> (amount - 64);
                CX.w[1] = 0;
            } else {
                __shr_128(&CX, &Qh, amount);
            }
            
            var Qh1 = UInt128()
            if (rmode == BID_ROUNDING_TO_NEAREST) {
                if (CX.w[0] & 1) != 0 {
                    // check whether fractional part of initial_P/10^ed1 is exactly .5
                    
                    // get remainder
                    __shl_128_long(&Qh1, Qh, (128 - amount));
                    
                    if ((Qh1.w[1] == 0) && (Qh1.w[0] == 0)
                        && (Ql.w[1] < bid_reciprocals10_128[extra_digits].w[1]
                            || (Ql.w[1] == bid_reciprocals10_128[extra_digits].w[1]
                                && Ql.w[0] < bid_reciprocals10_128[extra_digits].w[0]))) {
                        CX.w[0]-=1
                    }
                }
            }
            
            var status = Status.inexact // BID_INEXACT_EXCEPTION;
            // get remainder
            __shl_128_long (&Qh1, Qh, (128 - amount));
            
            switch (rmode) {
                case BID_ROUNDING_TO_NEAREST, BID_ROUNDING_TIES_AWAY:
                    // test whether fractional part is 0
                    if (Qh1.w[1] == Decimal64.SIGN_MASK64 && (Qh1.w[0] == 0)
                        && (Ql.w[1] < bid_reciprocals10_128[extra_digits].w[1]
                            || (Ql.w[1] == bid_reciprocals10_128[extra_digits].w[1]
                                && Ql.w[0] < bid_reciprocals10_128[extra_digits].w[0]))) {
                        status = []
                    }
                case BID_ROUNDING_DOWN, BID_ROUNDING_TO_ZERO:
                    if ((Qh1.w[1] == 0) && (Qh1.w[0] == 0)
                        && (Ql.w[1] < bid_reciprocals10_128[extra_digits].w[1]
                            || (Ql.w[1] == bid_reciprocals10_128[extra_digits].w[1]
                                && Ql.w[0] < bid_reciprocals10_128[extra_digits].w[0]))) {
                        status = []
                    }
                default:
                    // round up
                    var cy = UInt64(), Stemp = UInt128(), Tmp = UInt128(), Tmp1 = UInt128()
                    __add_carry_out (&Stemp.w[0], &cy, Ql.w[0], bid_reciprocals10_128[extra_digits].w[0]);
                    __add_carry_in_out (&Stemp.w[1], &carry, Ql.w[1], bid_reciprocals10_128[extra_digits].w[1], cy);
                    __shr_128_long (&Qh, Qh1, (128 - amount));
                    Tmp.w[0] = 1;
                    Tmp.w[1] = 0;
                    __shl_128_long(&Tmp1, Tmp, amount);
                    Qh.w[0] += carry;
                    if (Qh.w[0] < carry) {
                        Qh.w[1]+=1
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
        
        return Decimal32.get_BID32 (UInt32(sign_x >> 32), exponent_x - DECIMAL_EXPONENT_BIAS_128 +
                                    Decimal32.EXPONENT_BIAS, UInt32(CX.w[0]), rmode, &pfpsf)
    }
    
    //
    //  BID128 unpack, input passed by value
    //
    static func unpack_BID128_value (_ psign_x:inout UInt64, _ pexponent_x:inout Int, _ pcoefficient_x:inout UInt128, _ x:UInt128) -> Bool {
        psign_x = x.w[1] & Decimal64.SIGN_MASK64
        
        // special encodings
        if ((x.w[1] & Decimal64.INFINITY_MASK64) >= Decimal64.SPECIAL_ENCODING_MASK64) {
            if ((x.w[1] & Decimal64.INFINITY_MASK64) < Decimal64.INFINITY_MASK64) {
                // non-canonical input
                pcoefficient_x.w[0] = 0;
                pcoefficient_x.w[1] = 0;
                let ex = (x.w[1]) >> 47;
                pexponent_x = Int(ex) & EXPONENT_MASK128;
                return false
            }
            // 10^33
            let T33 = bid_power10_table_128[33];
            /*coeff.w[0] = x.w[0];
             coeff.w[1] = (x.w[1]) & LARGE_COEFF_MASK128;
             pcoefficient_x->w[0] = x.w[0];
             pcoefficient_x->w[1] = x.w[1];
             if (__unsigned_compare_ge_128 (coeff, T33)) // non-canonical
             pcoefficient_x->w[1] &= (~LARGE_COEFF_MASK128); */
            
            pcoefficient_x.w[0] = x.w[0];
            pcoefficient_x.w[1] = (x.w[1]) & 0x00003fffffffffff
            if (__unsigned_compare_ge_128 (pcoefficient_x, T33)) {   // non-canonical
                pcoefficient_x.w[1] = (x.w[1]) & 0xfe00000000000000
                pcoefficient_x.w[0] = 0;
            } else {
                pcoefficient_x.w[1] = (x.w[1]) & 0xfe003fffffffffff
            }
            if ((x.w[1] & Decimal64.NAN_MASK64) == Decimal64.INFINITY_MASK64) {
                pcoefficient_x.w[0] = 0;
                pcoefficient_x.w[1] = x.w[1] & Decimal64.SINFINITY_MASK64;
            }
            pexponent_x = 0
            return false   // NaN or Infinity
        }
        
        var coeff = UInt128()
        coeff.w[0] = x.w[0]
        coeff.w[1] = x.w[1] & SMALL_COEFF_MASK128
        
        // 10^34
        let T34 = bid_power10_table_128[34];
        // check for non-canonical values
        if __unsigned_compare_ge_128(coeff, T34) {
            coeff.w[0] = 0; coeff.w[1] = 0
        }
        
        pcoefficient_x = coeff
        
        let ex = x.w[1] >> 49
        pexponent_x = Int(ex) & EXPONENT_MASK128
        
        return (coeff.w[0] | coeff.w[1]) != 0
    }
    
    //
    //   Macro for handling BID128 underflow
    //
    static func handle_UF_128 (_ sgn:UInt64, _ expon:Int, _ CQ:UInt128, _ prounding_mode:Rounding, _ fpsc: inout Status) -> UInt128 {
        //      BID_UINT128 T128, TP128, Qh, Ql, Qh1, Stemp, Tmp, Tmp1;
        //      BID_UINT64 carry, CY;
        //      int ed2, amount;
        //      unsigned rmode, status;
        var pres = UInt128()
        var expon = expon
        var CQ = CQ
        
        // UF occurs
        if expon + MAX_FORMAT_DIGITS_128 < 0 {
            fpsc.formUnion([.underflow, .inexact])
            pres.w[1] = sgn
            pres.w[0] = 0
            if ((sgn != 0 && prounding_mode == BID_ROUNDING_DOWN)
                || (sgn == 0 && prounding_mode == BID_ROUNDING_UP)) {
                pres.w[0] = 1
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
        __add_carry_out(&CQ.w[0], &carry, T128.w[0], CQ.w[0])
        CQ.w[1] = CQ.w[1] + T128.w[1] + carry
        
        let TP128 = bid_reciprocals10_128[ed2]
        var Qh = UInt128(), Ql = UInt128()
        __mul_128x128_full(&Qh, &Ql, CQ, TP128)
        let amount = bid_recip_scale[ed2]
        
        if amount >= 64 {
            CQ.w[0] = Qh.w[1] >> (amount - 64)
            CQ.w[1] = 0
        } else {
            __shr_128(&CQ, &Qh, amount)
        }
        
        expon = 0
        var Qh1 = UInt128()
        if prounding_mode != BID_ROUNDING_TO_NEAREST {
            if (CQ.w[0] & 1) != 0 {
                // check whether fractional part of initial_P/10^ed1 is exactly .5
                
                // get remainder
                
                __shl_128_long(&Qh1, Qh, (128 - amount))
                
                if (Qh1.w[1] == 0 && Qh1.w[0] == 0 && (Ql.w[1] < bid_reciprocals10_128[ed2].w[1] ||
                   (Ql.w[1] == bid_reciprocals10_128[ed2].w[1] && Ql.w[0] < bid_reciprocals10_128[ed2].w[0]))) {
                    CQ.w[0]-=1
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
                    if (Qh1.w[1] == 0x8000000000000000 && (Qh1.w[0] == 0)
                        && (Ql.w[1] < bid_reciprocals10_128[ed2].w[1]
                            || (Ql.w[1] == bid_reciprocals10_128[ed2].w[1]
                                && Ql.w[0] < bid_reciprocals10_128[ed2].w[0]))) {
                        status = []
                    }
                case BID_ROUNDING_DOWN, BID_ROUNDING_TO_ZERO:
                    if ((Qh1.w[1] == 0) && (Qh1.w[0] == 0)
                        && (Ql.w[1] < bid_reciprocals10_128[ed2].w[1]
                            || (Ql.w[1] == bid_reciprocals10_128[ed2].w[1]
                                && Ql.w[0] < bid_reciprocals10_128[ed2].w[0]))) {
                        status = []
                    }
                default:
                    // round up
                    var Stemp = UInt128(), carry = UInt64(), CY = UInt64(), Tmp = UInt128(), Tmp1 = UInt128()
                    __add_carry_out(&Stemp.w[0], &CY, Ql.w[0], bid_reciprocals10_128[ed2].w[0]);
                    __add_carry_in_out(&Stemp.w[1], &carry, Ql.w[1], bid_reciprocals10_128[ed2].w[1], CY)
                    __shr_128_long(&Qh, Qh1, (128 - amount))
                    Tmp.w[0] = 1
                    Tmp.w[1] = 0
                    __shl_128_long(&Tmp1, Tmp, amount)
                    Qh.w[0] += carry
                    if Qh.w[0] < carry {
                        Qh.w[1]+=1
                    }
                    if __unsigned_compare_ge_128 (Qh, Tmp1) {
                        status = []
                    }
            }
            
            if !status.isEmpty {
                fpsc.formUnion(status); fpsc.insert(.underflow)
            }
        }
        
        pres.w[1] = sgn | CQ.w[1]
        pres.w[0] = CQ.w[0]
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
        if coeff.w[1] == 0x0001ed09bead87c0 && coeff.w[0] == 0x378d8e6400000000 {
            expon+=1
            // set coefficient to 10^33
            coeff.w[1] = 0x0000314dc6448d93
            coeff.w[0] = 0x38c15b0a00000000
        }
        // check OF, UF
        if expon < 0 || expon > DECIMAL_MAX_EXPON_128 {
            // check UF
            if expon < 0 {
                return handle_UF_128(sgn, expon, coeff, prounding_mode, &fpsc)
            }
            
            if expon - MAX_FORMAT_DIGITS_128 <= DECIMAL_MAX_EXPON_128 {
                let T = bid_power10_table_128[MAX_FORMAT_DIGITS_128 - 1];
                while __unsigned_compare_gt_128(T, coeff) && expon > DECIMAL_MAX_EXPON_128 {
                    coeff.w[1] = (coeff.w[1] << 3) + (coeff.w[1] << 1) + (coeff.w[0] >> 61) + (coeff.w[0] >> 63)
                    let tmp2 = coeff.w[0] << 3
                    coeff.w[0] = (coeff.w[0] << 1) + tmp2
                    if coeff.w[0] < tmp2 {
                        coeff.w[1]+=1
                    }
                    expon-=1
                }
            }
            if expon > DECIMAL_MAX_EXPON_128 {
                if (coeff.w[1] | coeff.w[0]) == 0 {
                    pres.w[1] = sgn | (UInt64(DECIMAL_MAX_EXPON_128) << 49)
                    pres.w[0] = 0
                    return pres
                }
                // OF
                fpsc.formUnion([.overflow, .inexact])
                if (prounding_mode == BID_ROUNDING_TO_ZERO ||
                    (sgn != 0 && prounding_mode == BID_ROUNDING_UP) ||
                    (sgn == 0 && prounding_mode == BID_ROUNDING_DOWN))
                {
                    pres.w[1] = sgn | LARGEST_BID128_HIGH
                    pres.w[0] = LARGEST_BID128_LOW
                } else {
                    pres.w[1] = sgn | INFINITY_MASK64
                    pres.w[0] = 0
                }
                return pres
            }
        }
        
        pres.w[0] = coeff.w[0]
        let tmp = UInt64(expon) << 49
        pres.w[1] = sgn | tmp | coeff.w[1]
        return pres
    }
    
    // **********************************************************************

    static func double_to_bid128 (_ x: Double, _ rnd_mode:Rounding, _ fpsc: inout Status) -> UInt128 {
        // Unpack the input
        var e = 0, s = 0, t = 0
        var c = UInt128()
        if let res = unpack_binary64 (x, &s, &e, &c.w[1], &t, &fpsc) { return UInt128(w: [0, res]) }
        // Now -1126<=e<=971 (971 for max normal, -1074 for min normal, -1126 for min denormal)
        
        // Shift up to the top: like a pure quad coefficient with a shift of 15.
        // In our case, this is 2^{113-53+15} times the core, so unpack at the
        // high end shifted by 11.
        
        c.w[0] = 0;
        c.w[1] = c.w[1] << 11;
        
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
            cint.w[1] = c.w[1]; cint.w[0] = c.w[0];
            if (a <= 0) {
                cint = srl128(cint.w[1], cint.w[0], 15 - e)
                if (lt128 (cint.w[1], cint.w[0], 542101086242752, 4003012203950112768)) {
                    return return_bid128(s, 6176, cint.w[1], cint.w[0])
                }
            } else if (a <= 48) {
                var pow5 = bid_coefflimits_bid128[a];
                cint = srl128(cint.w[1], cint.w[0], 15 + t)
                if le128(cint.w[1], cint.w[0], pow5.w[1], pow5.w[0]) {
                    var cc = UInt128()
                    cc.w[1] = cint.w[1]
                    cc.w[0] = cint.w[0]
                    pow5 = bid_power_five[a]
                    __mul_128x128_low(&cc, cc, pow5)
                    return return_bid128(s, 6176 - a, cc.w[1], cc.w[0])
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
        if lt128(bid_roundbound_128[rmode].w[1], bid_roundbound_128[rmode].w[0], z.w[3], z.w[2]) {
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
        c = sll128_short(c.w[1], c.w[0], 6)
        
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
        if le128(c.w[1], c.w[0], m_min.w[1], m_min.w[0]) {
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
        if lt128(bid_roundbound_128[rmode].w[1], bid_roundbound_128[rmode].w[0], z.w[4], z.w[3]) {
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
        s = Int(x.w[BID_HIGH_128W] >> 63)
        if x.w[BID_HIGH_128W] & (3<<61) == (3<<61) {
            if x.w[BID_HIGH_128W] & (0xF<<59) == (0xF<<59) {
                if x.w[BID_HIGH_128W] & (0x1F<<58) != (0x1F<<58) { return return_double_inf(s) /*inf*/ }
                if x.w[BID_HIGH_128W] & (1<<57) != 0 {
                    pfpsf.insert(.invalidOperation)
                }
                if lt128(54210108624275,4089650035136921599,x.w[BID_HIGH_128W] & 0x3FFFFFFFFFFF,x.w[BID_LOW_128W]) {
                    return return_double_nan(s, 0, 0) /* nan(s,0,0) */
                }
                return return_double_nan(s, (x.w[BID_HIGH_128W]<<18)+(x.w[BID_LOW_128W]>>46), (x.w[BID_LOW_128W]<<18))
            }
            return return_double_zero(s) /* zero; */
        } else {
            e = Int((x.w[BID_HIGH_128W] >> 49) & ((1<<14)-1)) - 6176;
            c.w[1] = x.w[BID_HIGH_128W] & ((1<<49)-1);
            c.w[0] = x.w[BID_LOW_128W];
            if (lt128(542101086242752,4003012203950112767, c.w[1],c.w[0])) {
                c.w[1] = 0; c.w[0] = 0
            }
            if (c.w[1] == 0) && (c.w[0] == 0) { return return_double_zero(s) /* zero */ }
            let k = clz128_nz(c.w[1],c.w[0]) - 15
            c = sll128(c.w[1],c.w[0],k)
            return nil
        }
    }
    
    static func bid128_from_int64(_ x: Int64) -> UInt128 {
        var res = UInt128()
        
        // if integer is negative, use the absolute value
        if x < 0 {
            res.w[BID_HIGH_128W] = 0xb040000000000000
        } else {
            res.w[BID_HIGH_128W] = 0x3040000000000000
        }
        res.w[BID_LOW_128W] = x.magnitude
        return res
    }
    
    //
    //   No overflow/underflow checks
    //   No checking for coefficient == 10^34 (rounding artifact)
    //
    static func bid_get_BID128_very_fast(_ sgn:UInt64, _ expon:Int, _ coeff:UInt128) -> UInt128 {
        var pres = UInt128()
        pres.w[0] = coeff.w[0]
        let tmp = UInt64(expon << 49)
        pres.w[1] = sgn | tmp | coeff.w[1]
        return pres
    }
    
    /*
     * Takes a BID128 as input and converts it to a BID32 and returns it.
     */
    static func bid128_to_bid32(_ x:UInt128, _ rnd_mode:Rounding, _ pfpsf: inout Status) -> UInt32 {
        var x = x, res = UInt32()
        BID_SWAP128(&x)
        
        // unpack arguments, check for NaN or Infinity or 0
        var sign_x = UInt64(), exponent_x = 0, CX = UInt128(), Tmp = UInt128(), Tmp1 = UInt128()
        var TP128 = UInt128(), Qh = UInt128(), Ql = UInt128(), Qh1 = UInt128()
        var uf_check = false
        if !unpack_BID128_value (&sign_x, &exponent_x, &CX, x) {
            if ((x.w[1]) & 0x7800000000000000) == 0x7800000000000000 {
                Tmp.w[1] = CX.w[1] & 0x00003fffffffffff
                Tmp.w[0] = CX.w[0]
                TP128 = bid_reciprocals10_128[27]
                __mul_128x128_full(&Qh, &Ql, Tmp, TP128)
                let amount = bid_recip_scale[27] - 64
                res = UInt32(((CX.w[1] >> 32) & 0xfc000000) | (Qh.w[1] >> amount))
                if (x.w[1] & Decimal64.SNAN_MASK64) == Decimal64.SNAN_MASK64 {   // sNaN
                    pfpsf.insert(.invalidOperation)
                }
                return res
            }
            // x is 0
            exponent_x = exponent_x - DECIMAL_EXPONENT_BIAS_128 + Decimal32.EXPONENT_BIAS
            if exponent_x < 0 {
                exponent_x = 0
            }
            if exponent_x > Decimal32.MAX_EXPON { // DECIMAL_MAX_EXPON_32) {
                exponent_x = Decimal32.MAX_EXPON
            }
            return UInt32(sign_x >> 32) | UInt32(exponent_x << 23)
        }
        
        if (CX.w[1] != 0 || (CX.w[0] >= 10000000)) {
            // find number of digits in coefficient
            // 2^64
            let f64 = Float(bitPattern: 0x5f800000)
            // fx ~ CX
            let fx = Float(CX.w[1]) * f64 + Float(CX.w[0])
            let bin_expon_cx = Int((fx.bitPattern >> 23) & 0xff) - 0x7f
            var extra_digits = Int(bid_estimate_decimal_digits[bin_expon_cx]) - 7
            // scale = 38-estimate_decimal_digits[bin_expon_cx];
            let D = CX.w[1] - bid_power10_index_binexp_128[bin_expon_cx].w[1]
            if (D > 0 || (D == 0 && CX.w[0] >= bid_power10_index_binexp_128[bin_expon_cx].w[0])) {
                extra_digits+=1
            }
            
            exponent_x += extra_digits;
            
            var rmode = roundboundIndex(rnd_mode) >> 2
            var carry = UInt64()
            if (sign_x != 0 && UInt(rmode - 1) < 2) {
                rmode = 3 - rmode;
            }
            if (exponent_x < DECIMAL_EXPONENT_BIAS_128 - Decimal32.EXPONENT_BIAS) {
                uf_check = true
                if -extra_digits + exponent_x - DECIMAL_EXPONENT_BIAS_128 + Decimal32.EXPONENT_BIAS + 35 >= 0 {
                    if exponent_x == DECIMAL_EXPONENT_BIAS_128 - Decimal32.EXPONENT_BIAS - 1 {
                        let T128 = bid_round_const_table_128[rmode][extra_digits]
                        var CX1 = UInt128()
                        __add_carry_out(&CX1.w[0], &carry, T128.w[0], CX.w[0]);
                        CX1.w[1] = CX.w[1] + T128.w[1] + carry;
                        if (__unsigned_compare_ge_128(CX1, bid_power10_table_128[extra_digits + 7])) {
                            uf_check = false
                        }
                    }
                    extra_digits = extra_digits + DECIMAL_EXPONENT_BIAS_128 - Decimal32.EXPONENT_BIAS - exponent_x;
                    exponent_x = DECIMAL_EXPONENT_BIAS_128 - Decimal32.EXPONENT_BIAS
                } else {
                    rmode = roundboundIndex(BID_ROUNDING_TO_ZERO) >> 2
                }
            }
            
            let T128 = bid_round_const_table_128[rmode][extra_digits]
            __add_carry_out(&CX.w[0], &carry, T128.w[0], CX.w[0])
            CX.w[1] = CX.w[1] + T128.w[1] + carry
            
            TP128 = bid_reciprocals10_128[extra_digits]
            __mul_128x128_full(&Qh, &Ql, CX, TP128)
            let amount = bid_recip_scale[extra_digits]
            
            if (amount >= 64) {
                CX.w[0] = Qh.w[1] >> (amount - 64)
                CX.w[1] = 0
            } else {
                __shr_128(&CX, &Qh, amount)
            }
            
            if rnd_mode != BID_ROUNDING_TO_NEAREST {
                if (CX.w[0] & 1) != 0 {
                    // check whether fractional part of initial_P/10^ed1 is exactly .5
                    
                    // get remainder
                    __shl_128_long(&Qh1, Qh, (128 - amount));
                    
                    if (Qh1.w[1] == 0 && Qh1.w[0] == 0 &&
                        (Ql.w[1] < bid_reciprocals10_128[extra_digits].w[1] ||
                         (Ql.w[1] == bid_reciprocals10_128[extra_digits].w[1] &&
                          Ql.w[0] < bid_reciprocals10_128[extra_digits].w[0]))) {
                        CX.w[0]-=1
                    }
                }
            }
            
            var status = Status.inexact
            // get remainder
            __shl_128_long(&Qh1, Qh, (128 - amount));
            
            switch rnd_mode {
                case BID_ROUNDING_TO_NEAREST, BID_ROUNDING_TIES_AWAY:
                    // test whether fractional part is 0
                    if (Qh1.w[1] == 0x8000000000000000 && (Qh1.w[0] == 0)
                        && (Ql.w[1] < bid_reciprocals10_128[extra_digits].w[1]
                            || (Ql.w[1] == bid_reciprocals10_128[extra_digits].w[1]
                                && Ql.w[0] < bid_reciprocals10_128[extra_digits].w[0]))) {
                        status = []
                    }
                case BID_ROUNDING_DOWN, BID_ROUNDING_TO_ZERO:
                    if (((Qh1.w[1] == 0)) && ((Qh1.w[0] == 0))
                        && (Ql.w[1] < bid_reciprocals10_128[extra_digits].w[1]
                            || (Ql.w[1] == bid_reciprocals10_128[extra_digits].w[1]
                                && Ql.w[0] < bid_reciprocals10_128[extra_digits].w[0]))) {
                        status = []
                    }
                default:
                    // round up
                    var Stemp = UInt128(), cy = UInt64()
                    __add_carry_out(&Stemp.w[0], &cy, Ql.w[0], bid_reciprocals10_128[extra_digits].w[0]);
                    __add_carry_in_out(&Stemp.w[1], &carry, Ql.w[1], bid_reciprocals10_128[extra_digits].w[1], cy);
                    __shr_128_long(&Qh, Qh1, (128 - amount))
                    Tmp.w[0] = 1
                    Tmp.w[1] = 0
                    __shl_128_long(&Tmp1, Tmp, amount);
                    Qh.w[0] += carry;
                    if (Qh.w[0] < carry) {
                        Qh.w[1]+=1
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
        return Decimal32.get_BID32 (UInt32(sign_x >> 32), exponent_x - DECIMAL_EXPONENT_BIAS_128 + Decimal32.EXPONENT_BIAS,
                                    UInt32(CX.w[0]), rnd_mode, &pfpsf)
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
            if (x.w[1] << 1) >= 0xf000000000000000 {
                Tmp.w[1] = CX.w[1] & 0x00003fffffffffff
                Tmp.w[0] = CX.w[0]
                TP128 = bid_reciprocals10_128[18]
                __mul_128x128_full(&Qh, &Ql, Tmp, TP128)
                let amount = bid_recip_scale[18]
                __shr_128(&Tmp, &Qh, amount)
                res = (CX.w[1] & 0xfc00000000000000) | Tmp.w[0]
                if (x.w[1] & Decimal64.SNAN_MASK64) == Decimal64.SNAN_MASK64 {   // sNaN
                    pfpsf.insert(.invalidOperation)
                }
                return res
            }
            exponent_x = exponent_x - DECIMAL_EXPONENT_BIAS_128 + Decimal64.DECIMAL_EXPONENT_BIAS
            if exponent_x < 0 {
                return sign_x
            }
            if exponent_x > Decimal64.DECIMAL_MAX_EXPON_64 {
                exponent_x = Decimal64.DECIMAL_MAX_EXPON_64
            }
            return sign_x | (UInt64(exponent_x) << 53)
        }
        
        if CX.w[1] != 0 || (CX.w[0] >= 10000000000000000) {
            // find number of digits in coefficient
            // 2^64
            let f64 = Float(bitPattern: 0x5f800000)
            
            // fx ~ CX
            let fx = Float(CX.w[1]) * f64 + Float(CX.w[0])
            let bin_expon_cx = Int((fx.bitPattern >> 23) & 0xff) - 0x7f
            var extra_digits = Int(bid_estimate_decimal_digits[bin_expon_cx]) - 16
            
            // scale = 38-estimate_decimal_digits[bin_expon_cx];
            let D = CX.w[1] - bid_power10_index_binexp_128[bin_expon_cx].w[1]
            if D > 0 || (D == 0 && CX.w[0] >= bid_power10_index_binexp_128[bin_expon_cx].w[0]) {
                extra_digits+=1
            }
            
            exponent_x += extra_digits
            
            var rmode = roundboundIndex(rnd_mode) >> 2
            if sign_x != 0 && UInt(rmode - 1) < 2 {
                rmode = 3 - rmode
            }
            
            if exponent_x < DECIMAL_EXPONENT_BIAS_128 - Decimal64.DECIMAL_EXPONENT_BIAS {
                uf_check = true
                if -extra_digits + exponent_x - DECIMAL_EXPONENT_BIAS_128 + Decimal64.DECIMAL_EXPONENT_BIAS + 35 >= 0 {
                    if (exponent_x == DECIMAL_EXPONENT_BIAS_128 - Decimal64.DECIMAL_EXPONENT_BIAS - 1) {
                        T128 = bid_round_const_table_128[rmode][extra_digits];
                        __add_carry_out(&CX1.w[0], &carry, T128.w[0], CX.w[0]);
                        CX1.w[1] = CX.w[1] + T128.w[1] + carry;
                        if __unsigned_compare_ge_128(CX1, bid_power10_table_128[extra_digits + 16]) {
                            uf_check = false
                        }
                    }
                    extra_digits += DECIMAL_EXPONENT_BIAS_128 - Decimal64.DECIMAL_EXPONENT_BIAS - exponent_x
                    exponent_x = DECIMAL_EXPONENT_BIAS_128 - Decimal64.DECIMAL_EXPONENT_BIAS;
                    //uf_check = 2;
                } else {
                    rmode = roundboundIndex(BID_ROUNDING_TO_ZERO) >> 2
                }
            }
            
            T128 = bid_round_const_table_128[rmode][extra_digits]
            __add_carry_out(&CX.w[0], &carry, T128.w[0], CX.w[0])
            CX.w[1] = CX.w[1] + T128.w[1] + carry
            
            TP128 = bid_reciprocals10_128[extra_digits]
            __mul_128x128_full(&Qh, &Ql, CX, TP128)
            let amount = bid_recip_scale[extra_digits]
            
            if (amount >= 64) {
                CX.w[0] = Qh.w[1] >> (amount - 64);
                CX.w[1] = 0;
            } else {
                __shr_128(&CX, &Qh, amount)
            }
            
            if rnd_mode != BID_ROUNDING_TO_NEAREST {
                if (CX.w[0] & 1) != 0 {
                    // check whether fractional part of initial_P/10^ed1 is exactly .5
                    
                    // get remainder
                    __shl_128_long(&Qh1, Qh, (128 - amount))
                    
                    if (Qh1.w[1] == 0 && Qh1.w[0] == 0
                        && (Ql.w[1] < bid_reciprocals10_128[extra_digits].w[1]
                            || (Ql.w[1] == bid_reciprocals10_128[extra_digits].w[1]
                                && Ql.w[0] < bid_reciprocals10_128[extra_digits].w[0]))) {
                        CX.w[0]-=1
                    }
                }
            }
            
            var status = Status.inexact
            // get remainder
            __shl_128_long(&Qh1, Qh, (128 - amount))
            
            switch rnd_mode {
                case BID_ROUNDING_TO_NEAREST, BID_ROUNDING_TIES_AWAY:
                    // test whether fractional part is 0
                    if (Qh1.w[1] == 0x8000000000000000 && (Qh1.w[0] == 0)
                        && (Ql.w[1] < bid_reciprocals10_128[extra_digits].w[1]
                            || (Ql.w[1] == bid_reciprocals10_128[extra_digits].w[1]
                                && Ql.w[0] < bid_reciprocals10_128[extra_digits].w[0]))) {
                        status = []
                    }
                case BID_ROUNDING_DOWN, BID_ROUNDING_TO_ZERO:
                    if ((Qh1.w[1] == 0) && (Qh1.w[0] == 0)
                        && (Ql.w[1] < bid_reciprocals10_128[extra_digits].w[1]
                            || (Ql.w[1] == bid_reciprocals10_128[extra_digits].w[1]
                                && Ql.w[0] < bid_reciprocals10_128[extra_digits].w[0]))) {
                        status = []
                    }
                default:
                    // round up
                    var Stemp = UInt128(), cy = UInt64()
                    __add_carry_out(&Stemp.w[0], &cy, Ql.w[0], bid_reciprocals10_128[extra_digits].w[0]);
                    __add_carry_in_out(&Stemp.w[1], &carry, Ql.w[1], bid_reciprocals10_128[extra_digits].w[1], cy);
                    __shr_128_long(&Qh, Qh1, (128 - amount))
                    Tmp.w[0] = 1
                    Tmp.w[1] = 0
                    __shl_128_long(&Tmp1, Tmp, amount)
                    Qh.w[0] += carry
                    if Qh.w[0] < carry {
                        Qh.w[1]+=1
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
        return Decimal64.get_BID64 (sign_x, exponent_x - DECIMAL_EXPONENT_BIAS_128 + Decimal64.DECIMAL_EXPONENT_BIAS,
                                    CX.w[0], rnd_mode, &pfpsf);
    }

}
