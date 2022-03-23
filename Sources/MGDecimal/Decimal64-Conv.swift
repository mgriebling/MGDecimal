
import Foundation

/******************************************************************************
 Copyright (c) 2022 Computer Inspirations
 Translated to Swift from an original work in C by Intel Corp.
 All rights reserved.
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
 
 * Redistributions of source code must retain the above copyright notice,
   this list of conditions and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.
 * Neither the name of Intel Corporation nor the names of its contributors
   may be used to endorse or promote products derived from this software
   without specific prior written permission.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
 LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
 THE POSSIBILITY OF SUCH DAMAGE.
 ******************************************************************************/



extension Decimal64 {
    
    ////////////////////////////////////////
    // BID64 definitions
    ////////////////////////////////////////
    static let DECIMAL_MAX_EXPON_64  =   767
    static let DECIMAL_EXPONENT_BIAS =   398
    static let MAX_DIGITS            =    16
    static let expmin                = -6176 // min unbiased exponent
    static let expmax                =  6111 // max unbiased exponent
    static let expmin16              =  -398 // min unbiased exponent
    static let expmax16              =   369 // max unbiased exponent
    static let expmin7               =  -101 // min unbiased exponent
    static let expmax7               =    90 // max unbiased exponent
    static let BID64_SIG_MAX         = 9_999_999_999_999_999
    
    ////////////////////////////////////////
    // Constant Definitions
    ///////////////////////////////////////
    static let EXP_MIN                  = UInt64(0x0000_0000_0000_0000)  // EXP_MIN = (-6176 + 6176) << 49
    static let EXP_MAX                  = UInt64(0x5ffe_0000_0000_0000)  // EXP_MAX = (6111 + 6176) << 49
    static let EXP_MAX_P1               = UInt64(0x6000_0000_0000_0000)  // EXP_MAX + 1 = (6111 + 6176 + 1) << 49
    static let EXP_P1                   = UInt64(0x0002_0000_0000_0000)
    static let SPECIAL_ENCODING_MASK64  = UInt64(0x6000_0000_0000_0000)
    static let MASK_STEERING_BITS       = SPECIAL_ENCODING_MASK64
    static let MASK_BINARY_EXPONENT1    = UInt64(0x7fe0_0000_0000_0000)
    static let MASK_BINARY_SIG1         = SMALL_COEFF_MASK64
    static let MASK_BINARY_EXPONENT2    = UInt64(0x1ff8_0000_0000_0000)
    static let MASK_BINARY_SIG2         = UInt64(0x0007_ffff_ffff_ffff)
    static let MASK_BINARY_OR2          = UInt64(0x0020_0000_0000_0000)
    static let MASK_ANY_INF             = UInt64(0x7c00_0000_0000_0000)
    static let INFINITY_MASK64          = UInt64(0x7800_0000_0000_0000)
    static let MASK_INF                 = INFINITY_MASK64
    static let SINFINITY_MASK64         = UInt64(0xf800_0000_0000_0000)
    static let SSNAN_MASK64             = UInt64(0xfc00_0000_0000_0000)
    static let NAN_MASK64               = UInt64(0x7c00_0000_0000_0000)
    static let MASK_NAN                 = NAN_MASK64
    static let SNAN_MASK64              = UInt64(0x7e00_0000_0000_0000)
    static let MASK_SNAN                = SNAN_MASK64
    static let QUIET_MASK64             = UInt64(0xfdff_ffff_ffff_ffff)
    static let LARGE_COEFF_MASK64       = UInt64(0x0007_ffff_ffff_ffff)
    static let LARGE_COEFF_HIGH_BIT64   = UInt64(0x0020_0000_0000_0000)
    static let SMALL_COEFF_MASK64       = UInt64(0x001f_ffff_ffff_ffff)
    static let SIGN_MASK64              = UInt64(0x8000_0000_0000_0000)
    static let MASK_SIGN                = SIGN_MASK64
    static let EXPONENT_MASK64          = 0x3ff
    static let EXPONENT_SHIFT_LARGE64   = 51
    static let EXPONENT_SHIFT_SMALL64   = 53
    static let LARGEST_BID64            = UInt64(0x77fb_86f2_6fc0_ffff)
    static let SMALLEST_BID64           = UInt64(0xf7fb_86f2_6fc0_ffff)
    static let MASK_BINARY_EXPONENT     = UInt64(0x7ff0_0000_0000_0000)
    static let BINARY_EXPONENT_BIAS     = 0x3ff
    static let UPPER_EXPON_LIMIT        = 51
    
    //
    //   No overflow/underflow checking
    //   or checking for coefficients equal to 10^16 (after rounding)
    //
    static func very_fast_get_BID64 (_ sgn:UInt64, _ expon:Int, _ coeff:UInt64) -> UInt64 {
        var mask = UInt64(1) << EXPONENT_SHIFT_SMALL64
        
        // check whether coefficient fits in 10*5+3 bits
        var r:UInt64
        if coeff < mask {
            r = UInt64(expon)
            r <<= EXPONENT_SHIFT_SMALL64
            r |= coeff | sgn
            return r
        }
        
        // special format
        r = UInt64(expon)
        r <<= EXPONENT_SHIFT_LARGE64
        r |= (sgn | SPECIAL_ENCODING_MASK64)
        
        // add coeff, without leading bits
        mask = (mask >> 2) - 1
        r |= coeff & mask
        return r
    }
    
    
    //
    //   No overflow/underflow checking or checking for coefficients above 2^53
    //
    static func very_fast_get_BID64_small_mantissa (_ sgn:UInt64, _ expon:Int, _ coeff:UInt64) -> UInt64 {
      // no UF/OF
      var r = UInt64(expon) << EXPONENT_SHIFT_SMALL64
      r |= coeff | sgn
      return r
    }
    
    /*
     * Takes a BID32 as input and converts it to a BID64 and returns it.
     */
    static func BID32_to_BID64 (_ x: UInt32, _ pfpsf: inout Status) -> UInt64 {
        var sign_x = UInt32(0), coefficient_x = UInt32(0), exponent_x = 0
        var res: UInt64
        if !Decimal32.unpack_BID32 (&sign_x, &exponent_x, &coefficient_x, x) {
            // Inf, NaN, 0
            if (x & Decimal32.INFINITY_MASK32) == Decimal32.INFINITY_MASK32 {
                if (x & Decimal32.SNAN_MASK32) == Decimal32.SNAN_MASK32 {    // sNaN
                    pfpsf.insert(.invalidOperation)
                    // __set_status_flags (pfpsf, BID_INVALID_EXCEPTION);
                }
                res = UInt64(coefficient_x & 0x000fffff)
                res *= 1_000_000_000
                res |= ((UInt64(coefficient_x) << 32) & SSNAN_MASK64)
                return res
            }
        }
        
        return very_fast_get_BID64_small_mantissa(UInt64(sign_x) << 32,
                                                  exponent_x + DECIMAL_EXPONENT_BIAS - Decimal32.EXPONENT_BIAS,
                                                  UInt64(coefficient_x))
    }    // convert_bid32_to_bid64
    
    static func unpack_BID64 (_ psign_x:inout UInt64, _ pexponent_x:inout Int, _ pcoefficient_x:inout UInt64, _ x:UInt64) -> Bool {
        var tmp, coeff: UInt64
        psign_x = x & SIGN_MASK64
        
        if (x & SPECIAL_ENCODING_MASK64) == SPECIAL_ENCODING_MASK64 {
            // special encodings
            // coefficient
            coeff = (x & LARGE_COEFF_MASK64) | LARGE_COEFF_HIGH_BIT64
            
            if (x & INFINITY_MASK64) == INFINITY_MASK64 {
                pexponent_x = 0;
                pcoefficient_x = x & 0xfe03ffffffffffff
                if (x & 0x0003ffffffffffff) >= 1_000_000_000_000_000 {
                    pcoefficient_x = x & 0xfe00000000000000
                }
                if (x & NAN_MASK64) == INFINITY_MASK64 {
                    pcoefficient_x = x & SINFINITY_MASK64
                }
                return false    // NaN or Infinity
            }
            // check for non-canonical values
            if coeff > BID64_SIG_MAX {
                coeff = 0
            }
            pcoefficient_x = coeff
            // get exponent
            tmp = x >> EXPONENT_SHIFT_LARGE64
            pexponent_x = Int(tmp & UInt64(EXPONENT_MASK64))
            return coeff != 0
        }
        // exponent
        tmp = x >> EXPONENT_SHIFT_SMALL64;
        pexponent_x = Int(tmp & UInt64(EXPONENT_MASK64))
        // coefficient
        pcoefficient_x = (x & UInt64(SMALL_COEFF_MASK64))
        
        return pcoefficient_x != 0
    }
    
    /*
     * Takes a BID64 as input and converts it to a BID32 and returns it.
     */
    static func BID64_to_BID32 (_ x: UInt64, _ rmode: Rounding, _ pfpsf: inout Status) -> UInt32 {
        // BID_OPT_SAVE_BINARY_FLAGS()
        
        // unpack arguments, check for NaN or Infinity, 0
        var sign_x = UInt64(0), coefficient_x = UInt64(0), exponent_x = 0
        var res: UInt32
        if !unpack_BID64 (&sign_x, &exponent_x, &coefficient_x, x) {
            if (x & INFINITY_MASK64) == INFINITY_MASK64 {
                let t64 = coefficient_x & 0x0003_ffff_ffff_ffff
                res = UInt32(t64 / 1_000_000_000)
                res |= UInt32(coefficient_x >> 32) & Decimal32.SSNAN_MASK32
                if (x & SNAN_MASK64) == SNAN_MASK64 {    // sNaN
                    pfpsf.insert(.invalidOperation)
                    // __set_status_flags (pfpsf, BID_INVALID_EXCEPTION);
                }
                return res
            }
            exponent_x = exponent_x - DECIMAL_EXPONENT_BIAS + Decimal32.EXPONENT_BIAS
            if exponent_x < 0 {
                exponent_x = 0
            }
            if exponent_x > Decimal32.MAX_EXPON {
                exponent_x = Decimal32.MAX_EXPON
            }
            return UInt32(sign_x >> 32) | UInt32(exponent_x << 23)
        }
        
        exponent_x = exponent_x - DECIMAL_EXPONENT_BIAS + Decimal32.EXPONENT_BIAS
        
        // check number of digits
        if coefficient_x > Decimal32.MAX_NUMBER {
            let tempx = Float(coefficient_x)
            let bin_expon_cx = Int(((tempx.bitPattern >> 23) & 0xff) - 0x7f)
            var extra_digits = Int(bid_estimate_decimal_digits[bin_expon_cx] - 7)
            // add test for range
            if coefficient_x >= bid_power10_index_binexp[bin_expon_cx] {
                extra_digits+=1
            }
            
            var rmode1 = roundboundIndex(rmode) >> 2
            if sign_x != 0 && UInt(rmode1 - 1) < 2 {
                rmode1 = 3 - rmode1
            }
            
            exponent_x += extra_digits
            if (exponent_x < 0) && (exponent_x + Decimal32.MAX_DIGITS >= 0) {
                pfpsf.insert(.underflow)
                if exponent_x == -1 {
                    if (coefficient_x + bid_round_const_table[rmode1][extra_digits] >=
                        bid_power10_table_128[extra_digits + 7].w[0]) {
                        pfpsf = []
                    }
                    extra_digits -= exponent_x
                    exponent_x = 0
                }
            }
            coefficient_x += bid_round_const_table[rmode1][extra_digits]
            var Q = UInt128()
            __mul_64x64_to_128(&Q, coefficient_x, bid_reciprocals10_64[extra_digits])
            
            // now get P/10^extra_digits: shift Q_high right by M[extra_digits]-128
            let amount = bid_short_recip_scale[extra_digits]
            
            coefficient_x = Q.w[1] >> amount
            
            if (coefficient_x & 1) != 0 {
                // check whether fractional part of initial_P/10^extra_digits
                // is exactly .5
                
                // get remainder
                let remainder_h = Q.w[1] << (64 - amount)
                
                if remainder_h == 0 && Q.w[0] < bid_reciprocals10_64[extra_digits] {
                    coefficient_x-=1
                }
            }
            
            var status = Status.inexact //.insert(.inexact)
            // get remainder
            let remainder_h = Q.w[1] << (64 - amount)
            
            switch rmode {
                case BID_ROUNDING_TO_NEAREST, BID_ROUNDING_TIES_AWAY:
                    // test whether fractional part is 0
                    if (remainder_h == SIGN_MASK64 && (Q.w[0] < bid_reciprocals10_64[extra_digits])) {
                        status = []
                    }
                case BID_ROUNDING_DOWN, BID_ROUNDING_TO_ZERO:
                    if (remainder_h == 0 && (Q.w[0] < bid_reciprocals10_64[extra_digits])) {
                        status = []
                    }
                default:
                    // round up
                    var Stemp = UInt64(), carry = UInt64()
                    __add_carry_out (&Stemp, &carry, Q.w[0], bid_reciprocals10_64[extra_digits]);
                    if (remainder_h >> (64 - amount)) + carry >= (UInt64(1) << amount) {
                        status = []
                    }
            }
            if !status.isEmpty {
                pfpsf.formUnion(status)
                // __set_status_flags (pfpsf, status)
            }
        }
        return Decimal32.get_BID32(UInt32(sign_x >> 32), exponent_x, UInt32(coefficient_x), rmode, &pfpsf)
    }
    
    //
    //   BID64 pack macro (general form)
    //
    static func get_BID64 (_ sgn:UInt64, _ expon:Int, _ coeff:UInt64, _ rmode:Rounding, _ fpsc: inout Status) -> UInt64 {
        var expon = expon
        var coeff = coeff
        
        if coeff > 9999999999999999 {
            expon+=1
            coeff = 1000000000000000
        }
        // check for possible underflow/overflow
        if UInt(expon) >= 3 * 256 {
            if expon < 0 {
                // underflow
                if expon + MAX_DIGITS < 0 {
                    fpsc.formUnion([.underflow, .inexact])
                    
                    if rmode == BID_ROUNDING_DOWN && sgn != 0 {
                        return 0x8000000000000001
                    }
                    if rmode == BID_ROUNDING_UP && sgn == 0 {
                        return 1
                    }
                    // result is 0
                    return sgn
                }
                var rmode1 = roundboundIndex(rmode) >> 2
                if sgn != 0 && UInt(rmode1 - 1) < 2 {
                    rmode1 = 3 - rmode1
                }
                
                // get digits to be shifted out
                let extra_digits = -expon
                coeff += bid_round_const_table[rmode1][extra_digits]
                
                // get coeff*(2^M[extra_digits])/10^extra_digits
                var QH = UInt64(), Q_low = UInt128()
                __mul_64x128_full(&QH, &Q_low, coeff, bid_reciprocals10_128[extra_digits])
                
                // now get P/10^extra_digits: shift Q_high right by M[extra_digits]-128
                let amount = bid_recip_scale[extra_digits]
                var remainder_h = UInt64(0)
                var _C64 = QH >> amount
                
                if rmode == BID_ROUNDING_TO_NEAREST {
                    if (_C64 & 1) != 0 {
                        // check whether fractional part of initial_P/10^extra_digits is exactly .5
                        // get remainder
                        let amount2 = 64 - amount
                        remainder_h = 0
                        remainder_h &-= 1
                        remainder_h >>= amount2
                        remainder_h = remainder_h & QH;
                        
                        if ((remainder_h == 0) && (Q_low.w[1] < bid_reciprocals10_128[extra_digits].w[1]
                                || (Q_low.w[1] == bid_reciprocals10_128[extra_digits].w[1]
                                    && Q_low.w[0] < bid_reciprocals10_128[extra_digits].w[0]))) {
                            _C64-=1
                        }
                    }
                }
                if fpsc.contains(.inexact) {
                    fpsc.insert(.underflow)
                } else {
                    var status = Status.inexact
                    // get remainder
                    remainder_h = QH << (64 - amount);
                    
                    switch (rmode) {
                        case BID_ROUNDING_TO_NEAREST, BID_ROUNDING_TIES_AWAY:
                            // test whether fractional part is 0
                            if (remainder_h == 0x8000000000000000
                                && (Q_low.w[1] < bid_reciprocals10_128[extra_digits].w[1]
                                    || (Q_low.w[1] == bid_reciprocals10_128[extra_digits].w[1]
                                        && Q_low.w[0] <
                                        bid_reciprocals10_128[extra_digits].w[0]))) {
                                status = []
                            }
                        case BID_ROUNDING_DOWN, BID_ROUNDING_TO_ZERO:
                            if ((remainder_h == 0)
                                && (Q_low.w[1] < bid_reciprocals10_128[extra_digits].w[1]
                                    || (Q_low.w[1] == bid_reciprocals10_128[extra_digits].w[1]
                                        && Q_low.w[0] <
                                        bid_reciprocals10_128[extra_digits].w[0]))) {
                                status = []
                            }
                        default:
                            // round up
                            var Stemp = UInt128(), CY = UInt64(), carry = UInt64()
                            __add_carry_out (&Stemp.w[0], &CY, Q_low.w[0], bid_reciprocals10_128[extra_digits].w[0])
                            __add_carry_in_out (&Stemp.w[1], &carry, Q_low.w[1], bid_reciprocals10_128[extra_digits].w[1], CY)
                            if ((remainder_h >> (64 - amount)) + carry >= (UInt64(1) << amount)) {
                                status = []
                            }
                    }
                    
                    if !status.isEmpty {
                        fpsc.insert(.underflow); fpsc.formUnion(status)
                    }
                }
                
                return sgn | _C64;
            }
            if coeff == 0 { if expon > DECIMAL_MAX_EXPON_64 { expon = DECIMAL_MAX_EXPON_64 } }
            while (coeff < 1000000000000000 && expon >= 3 * 256) {
                expon-=1
                coeff = (coeff << 3) + (coeff << 1);
            }
            if expon > DECIMAL_MAX_EXPON_64 {
                fpsc.formUnion([.underflow, .inexact])

                // overflow
                var r = sgn | INFINITY_MASK64
                switch rmode {
                    case BID_ROUNDING_DOWN:
                        if sgn == 0 {
                            r = LARGEST_BID64
                        }
                    case BID_ROUNDING_TO_ZERO:
                        r = sgn | LARGEST_BID64
                    case BID_ROUNDING_UP:
                        // round up
                        if sgn != 0 {
                            r = SMALLEST_BID64
                        }
                    default: break
                }
                return r
            }
        }
        
        var mask = UInt64(1) << EXPONENT_SHIFT_SMALL64
        var r:UInt64
        
        // check whether coefficient fits in 10*5+3 bits
        if coeff < mask {
            r = UInt64(expon)
            r <<= EXPONENT_SHIFT_SMALL64
            r |= coeff | sgn
            return r
        }
        // special format
        
        // eliminate the case coeff==10^16 after rounding
        if coeff == 10000000000000000 {
            r = UInt64(expon + 1)
            r <<= EXPONENT_SHIFT_SMALL64
            r |= 1000000000000000 | sgn
            return r
        }
        
        r = UInt64(expon)
        r <<= EXPONENT_SHIFT_LARGE64
        r |= sgn | SPECIAL_ENCODING_MASK64
        
        // add coeff, without leading bits
        mask = (mask >> 2) - 1
        coeff &= mask
        r |= coeff
        return r
    }
    
    //
    // This pack macro is used when underflow is known to occur
    //
    static func get_BID64_UF (_ sgn:UInt64, _ expon:Int, _ coeff:UInt64, _ R:UInt64, _ rmode:Rounding, _ fpsc: inout Status) -> UInt64 {
        var coeff = coeff
        
        // underflow
        if expon + MAX_DIGITS < 0 {
            fpsc.formUnion([.underflow, .inexact])
            if (rmode == BID_ROUNDING_DOWN && (sgn != 0)) {
                return 0x8000000000000001
            }
            if (rmode == BID_ROUNDING_UP && (sgn == 0)) {
                return 1
            }
            // result is 0
            return sgn
        }
        // 10*coeff
        coeff = (coeff << 3) + (coeff << 1)
        var rmode1 = roundboundIndex(rmode) >> 2
        if sgn != 0 && UInt(rmode1 - 1) < 2 {
            rmode1 = 3 - rmode1
        }
        if R != 0 {
            coeff |= 1
        }
        
        // get digits to be shifted out
        let extra_digits = 1 - expon
        var C128 = UInt128()
        C128.w[0] = coeff + bid_round_const_table[rmode1][extra_digits]
        
        // get coeff*(2^M[extra_digits])/10^extra_digits
        var QH = UInt64(), Q_low = UInt128()
        __mul_64x128_full(&QH, &Q_low, C128.w[0], bid_reciprocals10_128[extra_digits])
        
        // now get P/10^extra_digits: shift Q_high right by M[extra_digits]-128
        let amount = bid_recip_scale[extra_digits]
        
        var _C64 = QH >> amount
        //__shr_128(C128, Q_high, amount);
        
        if rmode == BID_ROUNDING_TO_NEAREST {
            if (_C64 & 1) != 0 {
                // check whether fractional part of initial_P/10^extra_digits is exactly .5
                
                // get remainder
                let amount2 = 64 - amount
                var remainder_h = 0
                remainder_h-=1
                remainder_h >>= amount2;
                remainder_h = remainder_h & Int(QH)
                
                if ((remainder_h == 0)
                    && (Q_low.w[1] < bid_reciprocals10_128[extra_digits].w[1]
                        || (Q_low.w[1] == bid_reciprocals10_128[extra_digits].w[1]
                            && Q_low.w[0] < bid_reciprocals10_128[extra_digits].w[0]))) {
                    _C64-=1
                }
            }
        }
        
        if fpsc.contains(.inexact) {
            fpsc.insert(.underflow)
        } else {
            var status = Status.inexact
            // get remainder
            let remainder_h = QH << (64 - amount)
            
            switch (rmode) {
                case BID_ROUNDING_TO_NEAREST, BID_ROUNDING_TIES_AWAY:
                    // test whether fractional part is 0
                    if (remainder_h == 0x8000000000000000
                        && (Q_low.w[1] < bid_reciprocals10_128[extra_digits].w[1]
                            || (Q_low.w[1] == bid_reciprocals10_128[extra_digits].w[1]
                                && Q_low.w[0] < bid_reciprocals10_128[extra_digits].w[0]))) {
                        status = []
                    }
                case BID_ROUNDING_DOWN, BID_ROUNDING_TO_ZERO:
                    if ((remainder_h == 0)
                        && (Q_low.w[1] < bid_reciprocals10_128[extra_digits].w[1]
                            || (Q_low.w[1] == bid_reciprocals10_128[extra_digits].w[1]
                                && Q_low.w[0] < bid_reciprocals10_128[extra_digits].w[0]))) {
                        status = []
                    }
                default:
                    // round up
                    var Stemp = UInt128(), CY = UInt64(), carry = UInt64()
                    __add_carry_out(&Stemp.w[0], &CY, Q_low.w[0], bid_reciprocals10_128[extra_digits].w[0]);
                    __add_carry_in_out(&Stemp.w[1], &carry, Q_low.w[1], bid_reciprocals10_128[extra_digits].w[1], CY);
                    if ((remainder_h >> (64 - amount)) + carry >= (UInt64(1) << amount)) {
                        status = []
                    }
            }
            
            if !status.isEmpty {
                fpsc.insert(.underflow); fpsc.formUnion(status)
            }
        }
        return sgn | _C64
    }
    
    //
    //   no underflow checking
    //
    static func fast_get_BID64_check_OF (_ sgn:UInt64, _ expon:Int, _ coeff:UInt64, _ rmode:Rounding, _ fpsc: inout Status) -> UInt64 {
        // BID_UINT64 r, mask;
        var expon = expon
        var coeff = coeff
        var r:UInt64
        if UInt(expon) >= 3 * 256 - 1 {
            if (expon == 3 * 256 - 1) && coeff == 10000000000000000 {
                expon = 3 * 256;
                coeff = 1000000000000000;
            }
            
            if UInt(expon) >= 3 * 256 {
                while (coeff < 1000000000000000 && expon >= 3 * 256) {
                    expon-=1
                    coeff = (coeff << 3) + (coeff << 1);
                }
                if expon > DECIMAL_MAX_EXPON_64 {
                    fpsc.formUnion([.overflow, .inexact])
                    
                    // overflow
                    r = sgn | INFINITY_MASK64;
                    switch rmode {
                        case BID_ROUNDING_DOWN:
                            if sgn == 0 {
                                r = LARGEST_BID64
                            }
                        case BID_ROUNDING_TO_ZERO:
                            r = sgn | LARGEST_BID64
                        case BID_ROUNDING_UP:
                            // round up
                            if sgn != 0 {
                                r = SMALLEST_BID64
                            }
                        default: break
                    }
                    return r
                }
            }
        }
        
        var mask = UInt64(1) << EXPONENT_SHIFT_SMALL64
        
        // check whether coefficient fits in 10*5+3 bits
        if coeff < mask {
            r = UInt64(expon)
            r <<= EXPONENT_SHIFT_SMALL64
            r |= (coeff | sgn)
            return r
        }
        // special format
        
        // eliminate the case coeff==10^16 after rounding
        if coeff == 10000000000000000 {
            r = UInt64(expon + 1)
            r <<= EXPONENT_SHIFT_SMALL64
            r |= 1000000000000000 | sgn
            return r
        }
        
        r = UInt64(expon)
        r <<= EXPONENT_SHIFT_LARGE64
        r |= sgn | SPECIAL_ENCODING_MASK64
        // add coeff, without leading bits
        mask = (mask >> 2) - 1
        coeff &= mask
        r |= coeff
        return r
    }
    
    // **********************************************************************
    static func double_to_bid64 (_ x: Double, _ rmode:Rounding, _ fpsc: inout Status) -> UInt64 {
        // Unpack the input
        var s = 0, e = 0, c = UInt128(), t = 0
        if let res = unpack_binary64 (x, &s, &e, &c.w[1], &t, &fpsc) { return res }
        // Now -1126<=e<=971 (971 for max normal, -1074 for min normal, -1126 for min denormal)
        
        // Treat like a quad input for uniformity, so (2^{113-53} * c * r) >> 312
        // (312 is the shift value for these tables) which can be written as
        // (2^68 c * r) >> 320, lopping off exactly 320 bits = 5 words. Thus we put
        // input coefficient as the high part of c (<<64) shifted by 4 bits (<<68)
        //
        // Remember to compensate for the fact that exponents are integer for quad
        
        c.w[1] = c.w[1] << 4;
        c.w[0] = 0;
        t += (113 - 53);
        e -= (113 - 53); // Now e belongs [-1186;911].
        
        // Check for "trivial" overflow, when 2^e * 2^112 > 10^emax * 10^d.
        // We actually check if e >= ceil((emax + d) * log_2(10) - 112)
        // This could be intercepted later, but it's convenient to keep tables smaller
        
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
        // c is already 8 places to the left in preparation for the reciprocal
        // multiplication; thus we add 8 to all the shift counts
        
        if (e <= 0) {
            var cint = UInt128()
            let a = -(e + t)
            cint.w[1] = c.w[1]; cint.w[0] = c.w[0]
            if (a <= 0) {
                cint = srl128 (cint.w[1], cint.w[0], 8 - e);
                if ((cint.w[1] == 0) && (cint.w[0] < 10000000000000000)) {
                    return return_bid64 (s, 398, Int(cint.w[0]))
                }
            } else if (a <= 48) {
                var pow5 = bid_coefflimits_bid64[a]
                cint = srl128(cint.w[1], cint.w[0], 8 + t)
                if le128(cint.w[1], cint.w[0], pow5.w[1], pow5.w[0]) {
                    var cc = UInt128()
                    cc.w[1] = cint.w[1];
                    cc.w[0] = cint.w[0];
                    pow5 = bid_power_five[a];
                    __mul_128x128_low(&cc, cc, pow5);
                    return return_bid64 (s, 398 - a, Int(cc.w[0]))
                }
            }
        }
        // Check for "trivial" underflow, when 2^e * 2^113 <= 10^emin * 1/4,
        // so test e <= floor(emin * log_2(10) - 115)
        // In this case just fix ourselves at that value for uniformity.
        //
        // This is important not only to keep the tables small but to maintain the
        // testing of the round/sticky words as a correct rounding method
        
        // Now look up our exponent e, and the breakpoint between e and e+1
        let m_min = bid_breakpoints_bid64[e+1437]
        var e_out = bid_exponents_bid64[e+1437]
        
        // Choose exponent and reciprocal multiplier based on breakpoint
        var r = UInt256()
        if le128(c.w[1], c.w[0], m_min.w[1], m_min.w[0]) {
            r = bid_multipliers1_bid64[e+1437]
        } else {
            r = bid_multipliers2_bid64[e+1437]
            e_out = e_out + 1
        }
        
        // Do the reciprocal multiplication
        var z = UInt384()
        __mul_128x256_to_384(&z, c, r)
        var c_prov = Int(z.w[5])
        
        // Round using round-sticky words
        // If we spill over into the next decade, correct
        let rindex = roundboundIndex(rmode, s != 0, c_prov)
        if lt128(bid_roundbound_128[rindex].w[1], bid_roundbound_128[rindex].w[0], z.w[4], z.w[3]) {
            c_prov = c_prov + 1
            if c_prov == 10000000000000000 {
                c_prov = 1000000000000000
                e_out = e_out + 1
            }
        }
        
        // Check for overflow
        // Set the inexact flag as appropriate and check underflow
        // It's no doubt superfluous to check inexactness, but anyway...
        if (z.w[4] != 0) || (z.w[3] != 0) {
            fpsc.insert(.inexact)
        }
        
        // Package up the result
        return return_bid64 (s, e_out, c_prov)
    }
    
    static func bid64_from_int64(_ x: Int64, _ rnd_mode:Rounding, _ pfpsf: inout Status) -> UInt64 {
        var res = UInt64()
        let x_sign = x < 0 ? SIGN_MASK64 : 0
        var C = UInt64(), q = 0, ind = 0
        
        // if the integer is negative, use the absolute value
        C = x.magnitude
        if C <= BID64_SIG_MAX {    // |C| <= 10^16-1 and the result is exact
            if C < 0x0020000000000000 {    // C < 2^53
                res = x_sign | 0x31c0000000000000 | C
            } else {    // C >= 2^53
                res = x_sign | 0x6c70000000000000 | (C & 0x0007ffffffffffff)
            }
        } else {    // |C| >= 10^16 and the result may be inexact
            // the smallest |C| is 10^16 which has 17 decimal digits
            // the largest |C| is 0x8000000000000000 = 9223372036854775808 w/ 19 digits
            if C < 0x16345785d8a0000 {    // x < 10^17
                q = 17
                ind = 1    // number of digits to remove for q = 17
            } else if C < 0xde0b6b3a7640000 {    // C < 10^18
                q = 18
                ind = 2    // number of digits to remove for q = 18
            } else {    // C < 10^19
                q = 19
                ind = 3    // number of digits to remove for q = 19
            }
            
            // overflow and underflow are not possible
            // Note: performance can be improved by inlining this call
            var is_midpoint_lt_even = false, is_midpoint_gt_even = false
            var is_inexact_lt_midpoint = false, is_inexact_gt_midpoint = false
            var incr_exp = 0
            Decimal32.bid_round64_2_18(q, ind, C, &res, &incr_exp,
                &is_midpoint_lt_even, &is_midpoint_gt_even, &is_inexact_lt_midpoint, &is_inexact_gt_midpoint)
            if incr_exp != 0 {
                ind+=1
            }
            
            // set the inexact flag
            if is_inexact_lt_midpoint || is_inexact_gt_midpoint || is_midpoint_lt_even || is_midpoint_gt_even {
                pfpsf.insert(.inexact)
            }
            
            // general correction from RN to RA, RM, RP, RZ; result uses ind for exp
            if rnd_mode != BID_ROUNDING_TO_NEAREST {
                if (x_sign == 0 && ((rnd_mode == BID_ROUNDING_UP && is_inexact_lt_midpoint) ||
                   ((rnd_mode == BID_ROUNDING_TIES_AWAY || rnd_mode == BID_ROUNDING_UP) && is_midpoint_gt_even))) ||
                    (x_sign != 0 && ((rnd_mode == BID_ROUNDING_DOWN && is_inexact_lt_midpoint) ||
                   ((rnd_mode == BID_ROUNDING_TIES_AWAY || rnd_mode == BID_ROUNDING_DOWN) && is_midpoint_gt_even))) {
                    res = res + 1
                    if res == 0x002386f26fc10000 {  // res = 10^16 => rounding overflow
                        res = 0x00038d7ea4c68000    // 10^15
                        ind = ind + 1
                    }
                } else if (is_midpoint_lt_even || is_inexact_gt_midpoint) &&
                           ((x_sign != 0 && (rnd_mode == BID_ROUNDING_UP || rnd_mode == BID_ROUNDING_TO_ZERO)) ||
                            (x_sign == 0 && (rnd_mode == BID_ROUNDING_DOWN || rnd_mode == BID_ROUNDING_TO_ZERO))) {
                    res = res - 1
                    // check if we crossed into the lower decade
                    if res == 0x00038d7ea4c67fff {  // 10^15 - 1
                        res = 0x002386f26fc0ffff    // 10^16 - 1
                        ind = ind - 1
                    }
                } else {
                    // exact, the result is already correct
                }
            }
            if res < 0x0020000000000000 {
                // res < 2^53
                res = x_sign | (UInt64(ind + 398) << 53) | res
            } else {
                // res >= 2^53
                res = x_sign | 0x6000000000000000 | (UInt64(ind + 398) << 51) | (res & 0x0007ffffffffffff)
            }
        }
        return res
    }
    
    /*
     * Takes a BID64 as input and converts it to a BID128 and returns it.
     */
    static func bid64_to_bid128( _ x:UInt64, _ pfpsf: inout Status) -> UInt128 {
        var sign_x = UInt64(), exponent_x = 0, coefficient_x = UInt64()
        var res = UInt128(), new_coeff = UInt128()
        if !unpack_BID64 (&sign_x, &exponent_x, &coefficient_x, x) {
            if (x << 1) >= 0xf000000000000000 {
                if (x & SNAN_MASK64) == SNAN_MASK64 {   // sNaN
                    pfpsf.insert(.invalidOperation)
                }
                res.w[0] = coefficient_x & 0x0003ffffffffffff
                __mul_64x64_to_128(&res, res.w[0], bid_power10_table_128[18].w[0]);
                res.w[1] |= coefficient_x & 0xfc00000000000000
                return res
            }
        }
        
        new_coeff.w[0] = coefficient_x
        new_coeff.w[1] = 0
        return Decimal128.bid_get_BID128_very_fast(sign_x,
                    exponent_x + Decimal128.DECIMAL_EXPONENT_BIAS_128 - DECIMAL_EXPONENT_BIAS, new_coeff)
    }    // convert_bid64_to_bid128

}


