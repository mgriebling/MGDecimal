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

}
