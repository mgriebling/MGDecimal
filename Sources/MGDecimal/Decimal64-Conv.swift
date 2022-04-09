
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
    static let MAX_EXPON             =   767
    static let EXPONENT_BIAS         =   398
    static let MAX_DIGITS            =    16
    static let P16                   = MAX_DIGITS
    static let expmin                = -6176 // min unbiased exponent
    static let expmax                =  6111 // max unbiased exponent
    static let expmin16              =  -398 // min unbiased exponent
    static let expmax16              =   369 // max unbiased exponent
    static let expmin7               =  -101 // min unbiased exponent
    static let expmax7               =    90 // max unbiased exponent
    static let MAX_NUMBER            = UInt64(9_999_999_999_999_999)
    static let MAX_NUMBERP1          = MAX_NUMBER+1
    
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
    static func bid32_to_bid64 (_ x: UInt32, _ pfpsf: inout Status) -> UInt64 {
        var sign_x = UInt32(0), coefficient_x = UInt32(0), exponent_x = 0
        var res: UInt64
        if !Decimal32.unpack_BID32(&sign_x, &exponent_x, &coefficient_x, x) {
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
                                                  exponent_x + EXPONENT_BIAS - Decimal32.EXPONENT_BIAS,
                                                  UInt64(coefficient_x))
    }    // convert_bid32_to_bid64
    
    static func unpack_BID64(_ psign_x:inout UInt64, _ pexponent_x:inout Int, _ pcoefficient_x:inout UInt64, _ x:UInt64) -> Bool {
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
            if coeff > MAX_NUMBER {
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
    static func bid64_to_bid32(_ x: UInt64, _ rmode: Rounding, _ pfpsf: inout Status) -> UInt32 {
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
                }
                return res
            }
            exponent_x = exponent_x - EXPONENT_BIAS + Decimal32.EXPONENT_BIAS
            if exponent_x < 0 {
                exponent_x = 0
            }
            if exponent_x > Decimal32.MAX_EXPON {
                exponent_x = Decimal32.MAX_EXPON
            }
            return UInt32(sign_x >> 32) | UInt32(exponent_x << 23)
        }
        
        exponent_x = exponent_x - EXPONENT_BIAS + Decimal32.EXPONENT_BIAS
        
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
                        bid_power10_table_128[extra_digits + 7].lo) {
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
            
            coefficient_x = Q.hi >> amount
            
            if (coefficient_x & 1) != 0 {
                // check whether fractional part of initial_P/10^extra_digits
                // is exactly .5
                
                // get remainder
                let remainder_h = Q.hi << (64 - amount)
                
                if remainder_h == 0 && Q.lo < bid_reciprocals10_64[extra_digits] {
                    coefficient_x-=1
                }
            }
            
            var status = Status.inexact //.insert(.inexact)
            // get remainder
            let remainder_h = Q.hi << (64 - amount)
            
            switch rmode {
                case BID_ROUNDING_TO_NEAREST, BID_ROUNDING_TIES_AWAY:
                    // test whether fractional part is 0
                    if (remainder_h == SIGN_MASK64 && (Q.lo < bid_reciprocals10_64[extra_digits])) {
                        status = []
                    }
                case BID_ROUNDING_DOWN, BID_ROUNDING_TO_ZERO:
                    if (remainder_h == 0 && (Q.lo < bid_reciprocals10_64[extra_digits])) {
                        status = []
                    }
                default:
                    // round up
                    var Stemp = UInt64(), carry = UInt64()
                    __add_carry_out (&Stemp, &carry, Q.lo, bid_reciprocals10_64[extra_digits]);
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
                        
                        if ((remainder_h == 0) && (Q_low.hi < bid_reciprocals10_128[extra_digits].hi
                                || (Q_low.hi == bid_reciprocals10_128[extra_digits].hi
                                    && Q_low.lo < bid_reciprocals10_128[extra_digits].lo))) {
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
                            if (remainder_h == MASK_SIGN
                                && (Q_low.hi < bid_reciprocals10_128[extra_digits].hi
                                    || (Q_low.hi == bid_reciprocals10_128[extra_digits].hi
                                        && Q_low.lo <
                                        bid_reciprocals10_128[extra_digits].lo))) {
                                status = []
                            }
                        case BID_ROUNDING_DOWN, BID_ROUNDING_TO_ZERO:
                            if ((remainder_h == 0)
                                && (Q_low.hi < bid_reciprocals10_128[extra_digits].hi
                                    || (Q_low.hi == bid_reciprocals10_128[extra_digits].hi
                                        && Q_low.lo <
                                        bid_reciprocals10_128[extra_digits].lo))) {
                                status = []
                            }
                        default:
                            // round up
                            var Stemp = UInt128(), CY = UInt64(), carry = UInt64()
                            __add_carry_out (&Stemp.lo, &CY, Q_low.lo, bid_reciprocals10_128[extra_digits].lo)
                            __add_carry_in_out (&Stemp.hi, &carry, Q_low.hi, bid_reciprocals10_128[extra_digits].hi, CY)
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
            if coeff == 0 { if expon > MAX_EXPON { expon = MAX_EXPON } }
            while (coeff < 1000000000000000 && expon >= 3 * 256) {
                expon-=1
                coeff = (coeff << 3) + (coeff << 1);
            }
            if expon > MAX_EXPON {
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
        if coeff == MAX_NUMBERP1 {
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
        C128.lo = coeff + bid_round_const_table[rmode1][extra_digits]
        
        // get coeff*(2^M[extra_digits])/10^extra_digits
        var QH = UInt64(), Q_low = UInt128()
        __mul_64x128_full(&QH, &Q_low, C128.lo, bid_reciprocals10_128[extra_digits])
        
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
                    && (Q_low.hi < bid_reciprocals10_128[extra_digits].hi
                        || (Q_low.hi == bid_reciprocals10_128[extra_digits].hi
                            && Q_low.lo < bid_reciprocals10_128[extra_digits].lo))) {
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
                    if (remainder_h == MASK_SIGN
                        && (Q_low.hi < bid_reciprocals10_128[extra_digits].hi
                            || (Q_low.hi == bid_reciprocals10_128[extra_digits].hi
                                && Q_low.lo < bid_reciprocals10_128[extra_digits].lo))) {
                        status = []
                    }
                case BID_ROUNDING_DOWN, BID_ROUNDING_TO_ZERO:
                    if ((remainder_h == 0)
                        && (Q_low.hi < bid_reciprocals10_128[extra_digits].hi
                            || (Q_low.hi == bid_reciprocals10_128[extra_digits].hi
                                && Q_low.lo < bid_reciprocals10_128[extra_digits].lo))) {
                        status = []
                    }
                default:
                    // round up
                    var Stemp = UInt128(), CY = UInt64(), carry = UInt64()
                    __add_carry_out(&Stemp.lo, &CY, Q_low.lo, bid_reciprocals10_128[extra_digits].lo);
                    __add_carry_in_out(&Stemp.hi, &carry, Q_low.hi, bid_reciprocals10_128[extra_digits].hi, CY);
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
    //   No overflow/underflow checking
    //
    static func fast_get_BID64 (_ sgn:UInt64, _ expon:Int, _ coeff:UInt64) -> UInt64 {
        var mask = UInt64(1) << EXPONENT_SHIFT_SMALL64
        
        // check whether coefficient fits in 10*5+3 bits
        var r:UInt64
        if (coeff < mask) {
            r = UInt64(expon)
            r <<= EXPONENT_SHIFT_SMALL64;
            r |= (coeff | sgn);
            return r;
        }
        // special format
        
        // eliminate the case coeff==10^16 after rounding
        if (coeff == 10000000000000000) {
            r = UInt64(expon + 1)
            r <<= EXPONENT_SHIFT_SMALL64;
            r |= (1000000000000000 | sgn);
            return r;
        }
        
        r = UInt64(expon)
        r <<= EXPONENT_SHIFT_LARGE64;
        r |= (sgn | SPECIAL_ENCODING_MASK64);
        // add coeff, without leading bits
        mask = (mask >> 2) - 1;
        r |= coeff & mask
        return r
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
            if (expon == 3 * 256 - 1) && coeff == MAX_NUMBERP1 {
                expon = 3 * 256;
                coeff = 1000000000000000;
            }
            
            if UInt(expon) >= 3 * 256 {
                while (coeff < 1000000000000000 && expon >= 3 * 256) {
                    expon-=1
                    coeff = (coeff << 3) + (coeff << 1);
                }
                if expon > MAX_EXPON {
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
        if coeff == MAX_NUMBERP1 {
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
    
    ///////////////////////////////////////////////////////////////////
    // round 128-bit coefficient and return result in BID64 format
    ///////////////////////////////////////////////////////////////////
    static func __bid_full_round64 (_ sign:UInt64, _ exponent:Int, _ P:UInt128, _ extra_digits:Int, _ rounding_mode:Rounding, _ fpsc:inout Status) -> UInt64 {
        var Q_high=UInt128(), Q_low=UInt128(), C128=UInt128(), Stemp=UInt128(), PU=UInt128()
        var C64, CY, carry:UInt64
        var status = Status.clearFlags
        var extra_digits = extra_digits, exponent = exponent, P = P, sign = sign
        
        if (exponent < 0) {
            if (exponent >= -16 && (extra_digits + exponent < 0)) {
                extra_digits = -exponent;
                if (extra_digits > 0) {
                    var rmode =  roundboundIndex(rounding_mode) >> 2
                    if (sign != 0 && UInt(rmode - 1) < 2) {
                        rmode = 3 - rmode
                    }
                    __add_128_128(&PU, P, bid_round_const_table_128[rmode][extra_digits]);
                    if (__unsigned_compare_gt_128(bid_power10_table_128[extra_digits + 15], PU)) {
                        status = .underflow
                    }
                }
            }
        }
        
        if (extra_digits > 0) {
            exponent += extra_digits;
            var rmode =  roundboundIndex(rounding_mode) >> 2
            if (sign != 0 && UInt(rmode - 1) < 2) {
                rmode = 3 - rmode
            }
            __add_128_128(&P, P, bid_round_const_table_128[rmode][extra_digits]);
            
            // get P*(2^M[extra_digits])/10^extra_digits
            __mul_128x128_full(&Q_high, &Q_low, P, bid_reciprocals10_128[extra_digits]);
            
            // now get P/10^extra_digits: shift Q_high right by M[extra_digits]-128
            let amount = bid_recip_scale[extra_digits];
            __shr_128_long(&C128, Q_high, amount);
            
            C64 = C128.lo
            
            if (rmode == 0) {   //BID_ROUNDING_TO_NEAREST
                if (C64 & 1) != 0 {
                    // check whether fractional part of initial_P/10^extra_digits
                    // is exactly .5
                    
                    // get remainder
                    let amount2 = 64 - amount;
                    var remainder_h = UInt64(0)
                    remainder_h &-= 1
                    remainder_h >>= amount2;
                    remainder_h = remainder_h & Q_high.lo;
                    
                    if (remainder_h == 0
                        && (Q_low.lo < bid_reciprocals10_128[extra_digits].lo
                            || (Q_low.lo == bid_reciprocals10_128[extra_digits].lo
                                && Q_low.lo < bid_reciprocals10_128[extra_digits].lo))) {
                        C64-=1
                    }
                }
            }
            
            status.insert(.inexact)
            
            // get remainder
            let remainder_h = Q_high.lo << (64 - amount);
            
            switch rounding_mode {
                case BID_ROUNDING_TO_NEAREST, BID_ROUNDING_TIES_AWAY:
                    // test whether fractional part is 0
                    if (remainder_h == 0x8000000000000000
                        && (Q_low.lo < bid_reciprocals10_128[extra_digits].lo
                            || (Q_low.lo == bid_reciprocals10_128[extra_digits].lo
                                && Q_low.lo < bid_reciprocals10_128[extra_digits].lo))) {
                        status = []
                    }
                case BID_ROUNDING_DOWN, BID_ROUNDING_TO_ZERO:
                    if (remainder_h == 0
                        && (Q_low.lo < bid_reciprocals10_128[extra_digits].lo
                            || (Q_low.lo == bid_reciprocals10_128[extra_digits].lo
                                && Q_low.lo <
                                bid_reciprocals10_128[extra_digits].lo))) {
                        status = []
                    }
                default:
                    // round up
                    CY = 0; carry = 0
                    __add_carry_out(&Stemp.lo, &CY, Q_low.lo, bid_reciprocals10_128[extra_digits].lo)
                    __add_carry_in_out(&Stemp.lo, &carry, Q_low.lo, bid_reciprocals10_128[extra_digits].lo, CY)
                    if ((remainder_h >> (64 - amount)) + carry >= (UInt64(1) << amount)) {
                        status = []
                    }
            }
            fpsc.formUnion(status)
        } else {
            C64 = P.lo
            if C64 == 0 {
                sign = 0;
                if (rounding_mode == BID_ROUNDING_DOWN) {
                    sign = 0x8000000000000000
                }
            }
        }
        return get_BID64 (sign, exponent, C64, rounding_mode, &fpsc)
    }
    
    ///////////////////////////////////////////////////////////////////
    // round 128-bit coefficient and return result in BID64 format
    // do not worry about midpoint cases
    //////////////////////////////////////////////////////////////////
    static func __bid_simple_round64_sticky(_ sign:UInt64, _ exponent:Int, _ P:UInt128,
                                            _ extra_digits:Int, _ rounding_mode:Rounding, _ fpsc:inout Status) -> UInt64 {
        var Q_high=UInt128(), Q_low=UInt128(), C128=UInt128(), P = P
        var rmode = roundboundIndex(rounding_mode) >> 2 // rounding_mode;
        if (sign != 0 && UInt(rmode - 1) < 2) {
            rmode = 3 - rmode
        }
        __add_128_64(&P, P, bid_round_const_table[rmode][extra_digits]);
        
        // get P*(2^M[extra_digits])/10^extra_digits
        __mul_128x128_full(&Q_high, &Q_low, P, bid_reciprocals10_128[extra_digits]);
        
        // now get P/10^extra_digits: shift Q_high right by M[extra_digits]-128
        let amount = bid_recip_scale[extra_digits];
        __shr_128(&C128, Q_high, amount);
        
        let C64 = C128.lo
        
        fpsc.insert(.inexact)
        return get_BID64 (sign, exponent, C64, rounding_mode, &fpsc);
    }
    
    // **********************************************************************
    static func double_to_bid64 (_ x: Double, _ rmode:Rounding, _ fpsc: inout Status) -> UInt64 {
        // Unpack the input
        var s = 0, e = 0, c = UInt128(), t = 0
        if let res = unpack_binary64 (x, &s, &e, &c.hi, &t, &fpsc) { return res }
        // Now -1126<=e<=971 (971 for max normal, -1074 for min normal, -1126 for min denormal)
        
        // Treat like a quad input for uniformity, so (2^{113-53} * c * r) >> 312
        // (312 is the shift value for these tables) which can be written as
        // (2^68 c * r) >> 320, lopping off exactly 320 bits = 5 words. Thus we put
        // input coefficient as the high part of c (<<64) shifted by 4 bits (<<68)
        //
        // Remember to compensate for the fact that exponents are integer for quad
        
        c.hi = c.hi << 4;
        c.lo = 0;
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
            cint.hi = c.hi; cint.lo = c.lo
            if (a <= 0) {
                cint = srl128 (cint.hi, cint.lo, 8 - e);
                if ((cint.hi == 0) && (cint.lo < MAX_NUMBERP1)) {
                    return return_bid64 (s, 398, Int(cint.lo))
                }
            } else if (a <= 48) {
                var pow5 = bid_coefflimits_bid64[a]
                cint = srl128(cint.hi, cint.lo, 8 + t)
                if le128(cint.hi, cint.lo, pow5.hi, pow5.lo) {
                    var cc = UInt128()
                    cc.hi = cint.hi;
                    cc.lo = cint.lo;
                    pow5 = bid_power_five[a];
                    __mul_128x128_low(&cc, cc, pow5);
                    return return_bid64 (s, 398 - a, Int(cc.lo))
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
        if le128(c.hi, c.lo, m_min.hi, m_min.lo) {
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
        if lt128(bid_roundbound_128[rindex].hi, bid_roundbound_128[rindex].lo, z.w[4], z.w[3]) {
            c_prov = c_prov + 1
            if c_prov == MAX_NUMBERP1 {
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
        if C <= MAX_NUMBER {    // |C| <= 10^16-1 and the result is exact
            if C < 0x0020000000000000 {    // C < 2^53
                res = x_sign | 0x31c0000000000000 | C
            } else {    // C >= 2^53
                res = x_sign | 0x6c70000000000000 | (C & 0x0007ffffffffffff)
            }
        } else {    // |C| >= 10^16 and the result may be inexact
            // the smallest |C| is 10^16 which has 17 decimal digits
            // the largest |C| is MASK_SIGN = 9223372036854775808 w/ 19 digits
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
                res.lo = coefficient_x & 0x0003ffffffffffff
                __mul_64x64_to_128(&res, res.lo, bid_power10_table_128[18].lo);
                res.hi |= coefficient_x & 0xfc00000000000000
                return res
            }
        }
        
        new_coeff.lo = coefficient_x
        new_coeff.hi = 0
        return Decimal128.bid_get_BID128_very_fast(sign_x,
                                                   exponent_x + Decimal128.EXPONENT_BIAS - EXPONENT_BIAS, new_coeff)
    }    // convert_bid64_to_bid128
    
    
    static func bid_to_dpd64(_ ba:UInt64) -> UInt64 {
        var res = UInt64(), exp = UInt64(), nanb = UInt64()
        
        //printf("arg bid "BID_FMT_LLX16" \n", ba);
        let sign = ba & MASK_SIGN
        let comb = (ba & 0x7ffc000000000000) >> 50
        var trailing = ba & 0x0003ffffffffffff
        var bcoeff = UInt64()
        
        // Detect infinity, and return canonical infinity
        if (comb & 0x1f00) == 0x1e00 {
            return sign | 0x7800000000000000
            
            // Detect NaN, and canonicalize trailing
        } else if (comb & 0x1e00) == 0x1e00 {
            if trailing > 999999999999999 {
                trailing = 0
            }
            nanb = ba & 0xfe00000000000000
            exp = 0
            bcoeff = trailing
        } else {    // Normal number
            if (comb & 0x1800) == 0x1800 {    // G0..G1 = 11 -> exp is G2..G11
                exp = (comb >> 1) & 0x3ff
                bcoeff = ((8 + (comb & 1)) << 50) | trailing
            } else {
                exp = (comb >> 3) & 0x3ff
                bcoeff = ((comb & 7) << 50) | trailing
            }
            
            // Zero the coefficient if it is non-canonical (>= 10^16)
            if bcoeff >= MAX_NUMBERP1 {
                bcoeff = 0
            }
        }
        
        // Floor(2^61 / 10^9)
        let D61 = UInt64(2305843009)
        
        // Multipy the binary coefficient by ceil(2^64 / 1000), and take the upper
        // 64-bits in order to compute a division by 1000.
        
        //#if 1
        var yhi = UInt64(D61) * UInt64(UInt32(bcoeff) >> 27) >> 34
        var ylo = bcoeff - 1000000000 * yhi
        if ylo >= 1000000000 {
            ylo = ylo - 1000000000
            yhi = yhi + 1
        }
        //#else
        //        let yhi = bcoeff / 1000000000
        //        let ylo = bcoeff % 1000000000
        // #endif
        
        // yhi = ABBBCCC ylo = DDDEEEFFF
        let b5 = Int(ylo % 1000)    // b5 = FFF
        let b3 = Int(ylo / 1000000) // b3 = DDD
        let b4 = Int((Int(ylo) / 1000) - (1000 * b3))    // b4 = EEE
        let b2 = Int(yhi % 1000)    // b2 = CCC
        let b0 = Int(yhi / 1000000) // b0 = A
        let b1 = Int((Int(yhi) / 1000) - (1000 * b0))    // b1 = BBB
        
        let dcoeff = bid_b2d[b5] | bid_b2d2[b4] | bid_b2d3[b3] | bid_b2d4[b2] | bid_b2d5[b1]
        
        if b0 >= 8 {    // is b0 8 or 9?
            res = sign | ((UInt64(0x1800) | ((exp >> 8) << 9) | (UInt64(b0 & 1) << 8) | (exp & 0xff)) << 50) | dcoeff
        } else {   // else b0 is 0..7
            res = sign | ((((exp >> 8) << 11) | UInt64(b0 << 8) | (exp & 0xff)) << 50) | dcoeff
        }
        res |= nanb
        return res
    }
    
    static func dpd_to_bid64 (_ da:UInt64) -> UInt64 {
        var res = UInt64(), nanb = UInt64(), d0 = UInt64(), exp = UInt64()
        let sign = da & MASK_SIGN
        let comb = (da & 0x7ffc000000000000) >> 50
        let trailing = da & 0x0003ffffffffffff
        
        if (comb & 0x1f00) == 0x1e00 {    // G0..G4 = 11110 -> Inf
            return da & 0xf800000000000000
        } else if (comb & 0x1f00) == 0x1f00 {    // G0..G5 = 11111 -> NaN
            nanb = da & 0xfe00000000000000
            exp = 0
            d0 = 0
        } else {
            // Normal number
            if (comb & 0x1800) == 0x1800 {    // G0..G1 = 11 -> d0 = 8 + G4
                d0 = ((comb >> 8) & 1) | 8
                // d0 = (comb & 0x0100 ? 9 : 8);
                exp = (comb & 0x600) >> 1
                // exp = (comb & 0x0400 ? 1 : 0) * 0x200 + (comb & 0x0200 ? 1 : 0) * 0x100; // exp leading bits are G2..G3
            } else {
                d0 = (comb >> 8) & 0x7
                exp = (comb & 0x1800) >> 3
                // exp = (comb & 0x1000 ? 1 : 0) * 0x200 + (comb & 0x0800 ? 1 : 0) * 0x100; // exp loading bits are G0..G1
            }
        }
        let d1 = bid_d2b5[Int(trailing >> 40) & 0x3ff];
        let d2 = bid_d2b4[Int(trailing >> 30) & 0x3ff];
        let d3 = bid_d2b3[Int(trailing >> 20) & 0x3ff];
        let d4 = bid_d2b2[Int(trailing >> 10) & 0x3ff];
        let d5 = bid_d2b[Int(trailing) & 0x3ff];
        
        let bcoeff = (d5 + d4 + d3) + d2 + d1 + (1000000000000000 * d0)
        exp += comb & 0xff
        res = very_fast_get_BID64 (sign, Int(exp), bcoeff)
        
        res |= nanb
        return res
    }
    
    /*****************************************************************************
     *  BID64_to_int64_int
     ****************************************************************************/
    static func bid64_to_int (_ x:UInt64, _ pfpsf: inout Status) -> Int {
        var res = 0, x_exp = UInt64(), C1 = UInt64(), P128 = UInt128(), C = UInt128()
        
        // check for NaN or Infinity
        if ((x & MASK_NAN) == MASK_NAN || (x & MASK_INF) == MASK_INF) {
            // set invalid flag
            pfpsf.insert(.invalidOperation)
            
            // return Integer Indefinite
            return Int(bitPattern: UInt(MASK_SIGN))
        }
        // unpack x
        let x_sign = x & MASK_SIGN;    // 0 for positive, MASK_SIGN for negative
        // if steering bits are 11 (condition will be 0), then exponent is G[0:w+1] =>
        if ((x & MASK_STEERING_BITS) == MASK_STEERING_BITS) {
            x_exp = (x & MASK_BINARY_EXPONENT2) >> 51    // biased
            C1 = (x & MASK_BINARY_SIG2) | MASK_BINARY_OR2
            if C1 > 9999999999999999 {    // non-canonical
                x_exp = 0;
                C1 = 0;
            }
        } else {
            x_exp = (x & MASK_BINARY_EXPONENT1) >> 53;    // biased
            C1 = x & MASK_BINARY_SIG1;
        }
        
        // check for zeros (possibly from non-canonical values)
        if C1 == 0 {
            // x is 0
            return 0x00000000
        }
        // x is not special and is not zero
        
        // q = nr. of decimal digits in x (1 <= q <= 54)
        //  determine first the nr. of bits in x
        var x_nr_bits:Int
        if C1 >= 0x0020000000000000 {    // x >= 2^53
            // split the 64-bit value in two 32-bit halves to avoid rounding errors
            let tmp1 = Double(C1 >> 32);   // exact conversion
            x_nr_bits = 33 + (((Int(tmp1.bitPattern >> 52)) & 0x7ff) - 0x3ff)
        } else {    // if x < 2^53
            let tmp1 = Double(C1)    // exact conversion
            x_nr_bits = 1 + (((Int(tmp1.bitPattern >> 52)) & 0x7ff) - 0x3ff)
        }
        var q = Int(bid_nr_digits[x_nr_bits - 1].digits)
        if q == 0 {
            q = Int(bid_nr_digits[x_nr_bits - 1].digits1)
            if (C1 >= bid_nr_digits[x_nr_bits - 1].threshold_lo) {
                q+=1
            }
        }
        let exp = Int(x_exp) - 398;    // unbiased exponent
        
        if ((q + exp) > 19) {    // x >= 10^19 ~= 2^63.11... (cannot fit in BID_SINT64)
            // set invalid flag
            pfpsf.insert(.invalidOperation)
            
            // return Integer Indefinite
            return Int(bitPattern: UInt(MASK_SIGN))
        } else if ((q + exp) == 19) {    // x = c(0)c(1)...c(18).c(19)...c(q-1)
            // in this case 2^63.11... ~= 10^19 <= x < 10^20 ~= 2^66.43...
            // so x rounded to an integer may or may not fit in a signed 64-bit int
            // the cases that do not fit are identified here; the ones that fit
            // fall through and will be handled with other cases further,
            // under '1 <= q + exp <= 19'
            if x_sign != 0 {    // if n < 0 and q + exp = 19
                // if n <= -2^63 - 1 then n is too large
                // too large if c(0)c(1)...c(18).c(19)...c(q-1) >= 2^63+1
                // <=> 0.c(0)c(1)...c(q-1) * 10^20 >= 5*(2^64+2), 1<=q<=16
                // <=> 0.c(0)c(1)...c(q-1) * 10^20 >= 0x5000000000000000a, 1<=q<=16
                // <=> C * 10^(20-q) >= 0x5000000000000000a, 1<=q<=16
                // 1 <= q <= 16 => 4 <= 20-q <= 19 => 10^(20-q) is 64-bit, and so is C1
                __mul_64x64_to_128MACH (&C, C1, bid_ten2k64[20 - q]);
                // Note: C1 * 10^(11-q) has 19 or 20 digits; 0x5000000000000000a, has 20
                if (C.hi > 0x05 || (C.hi == 0x05 && C.lo >= 0x0a)) {
                    // set invalid flag
                    pfpsf.insert(.invalidOperation)
                    
                    // return Integer Indefinite
                    return Int(bitPattern: UInt(MASK_SIGN))
                }
                // else cases that can be rounded to a 64-bit int fall through
                // to '1 <= q + exp <= 19'
            } else {    // if n > 0 and q + exp = 19
                // if n >= 2^63 then n is too large
                // too large if c(0)c(1)...c(18).c(19)...c(q-1) >= 2^63
                // <=> if 0.c(0)c(1)...c(q-1) * 10^20 >= 5*2^64, 1<=q<=16
                // <=> if 0.c(0)c(1)...c(q-1) * 10^20 >= 0x50000000000000000, 1<=q<=16
                // <=> if C * 10^(20-q) >= 0x50000000000000000, 1<=q<=16
                C.hi = 0x0000000000000005;
                C.lo = 0x0000000000000000;
                // 1 <= q <= 16 => 4 <= 20-q <= 19 => 10^(20-q) is 64-bit, and so is C1
                __mul_64x64_to_128MACH(&C, C1, bid_ten2k64[20 - q]);
                if (C.hi >= 0x05) {
                    // actually C.hi == 0x05 && C.lo >= 0x0000000000000000) {
                    // set invalid flag
                    pfpsf.insert(.invalidOperation)
                    // return Integer Indefinite
                    return Int(bitPattern: UInt(MASK_SIGN))
                }
                // else cases that can be rounded to a 64-bit int fall through
                // to '1 <= q + exp <= 19'
            }    // end else if n > 0 and q + exp = 19
        }    // end else if ((q + exp) == 19)
        
        // n is not too large to be converted to int64: -2^63-1 < n < 2^63
        // Note: some of the cases tested for above fall through to this point
        if (q + exp) <= 0 {    // n = +/-0.0...c(0)c(1)...c(q-1)
            // return 0
            return 0
        } else {    // if (1 <= q + exp <= 19, 1 <= q <= 16, -15 <= exp <= 18)
            // -2^63-1 < x <= -1 or 1 <= x < 2^63 so x can be rounded
            // to nearest to a 64-bit signed integer
            if exp < 0 {    // 2 <= q <= 16, -15 <= exp <= -1, 1 <= q + exp <= 19
                let ind = -exp;    // 1 <= ind <= 15; ind is a synonym for 'x'
                // chop off ind digits from the lower part of C1
                // C1 fits in 64 bits
                // calculate C* and f*
                // C* is actually floor(C*) in this case
                // C* and f* need shifting and masking, as shown by
                // bid_shiftright128[] and bid_maskhigh128[]
                // 1 <= x <= 15
                // kx = 10^(-x) = bid_ten2mk64[ind - 1]
                // C* = C1 * 10^(-x)
                // the approximation of 10^(-x) was rounded up to 54 bits
                __mul_64x64_to_128MACH(&P128, C1, bid_ten2mk64[ind - 1]);
                var Cstar = Int(P128.hi)
                // the top Ex bits of 10^(-x) are T* = bid_ten2mk128trunc[ind].lo, e.g.
                // if x=1, T*=bid_ten2mk128trunc[0].lo=0x1999999999999999
                // C* = floor(C*) (logical right shift; C has p decimal digits,
                //     correct by Property 1)
                // n = C* * 10^(e+x)
                
                // shift right C* by Ex-64 = bid_shiftright128[ind]
                let shift = bid_shiftright128[ind - 1];    // 0 <= shift <= 39
                Cstar = Cstar >> shift;
                
                if x_sign != 0 {
                    res = -Cstar
                } else {
                    res = Cstar
                }
            } else if exp == 0 {
                // 1 <= q <= 16
                // res = +/-C (exact)
                if x_sign != 0 {
                    res = -Int(C1)
                } else {
                    res = Int(C1)
                }
            } else {    // if (exp > 0) => 1 <= exp <= 18, 1 <= q <= 16, 2 <= q + exp <= 20
                // (the upper limit of 20 on q + exp is due to the fact that
                // +/-C * 10^exp is guaranteed to fit in 64 bits)
                // res = +/-C * 10^exp (exact)
                if x_sign != 0 {
                    res = -Int(C1 * bid_ten2k64[exp])
                } else {
                    res = Int(C1 * bid_ten2k64[exp])
                }
            }
        }
        return res
    }

    // **********************************************************************
    
    static func bid64_to_double (_ x:UInt64, _ rnd_mode:Rounding, _ pfpsf: inout Status) -> Double {
        var s = 0, e = 0, k = 0, c = UInt128(), r = UInt256(), z = UInt384()
        if let res = unpack_bid64(x, &s, &e, &k, &c.hi, &pfpsf) { return res }
        
        // Correct to 2^112 <= c < 2^113 with corresponding exponent adding 113-54=59
        // In fact shift a further 6 places ready for reciprocal multiplication
        // Thus (113-54)+6=65, a shift of 1 given that we've already upacked in c.hi
        c.hi = c.hi << 1
        c.lo = 0
        k = k + 59
        
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
        var e_out = bid_exponents_binary64[e+358] - k
        
        // Choose provisional exponent and reciprocal multiplier based on breakpoint
        if le128(c.hi, c.lo, m_min.hi, m_min.lo) {
            r = bid_multipliers1_binary64[e+358]
        } else {
            r = bid_multipliers2_binary64[e+358]
            e_out = e_out + 1
        }
        
        // Do the reciprocal multiplication
        __mul_64x256_to_320(&z, c.hi, r)
        z.w[5]=z.w[4]; z.w[4]=z.w[3]; z.w[3]=z.w[2]; z.w[2]=z.w[1]; z.w[1]=z.w[0]; z.w[0]=0
        
        // Check for exponent underflow and compensate by shifting the product
        // Cut off the process at precision+2, since we can't really shift further
        if e_out < 1 {
            var d = 1 - e_out
            if d > 55 {
                d = 55
            }
            e_out = 1
            let r = srl256_short(z.w[5], z.w[4], z.w[3], z.w[2], d)
            z.w[2...5] = r.w[0...]
        }
        var c_prov = z.w[5]
        
        // Round using round-sticky words
        // If we spill into the next binade, correct
        // Flag underflow where it may be needed even for |result| = SNN
        let rndInd = roundboundIndex(rnd_mode, s != 0, Int(c_prov))
        if lt128(bid_roundbound_128[rndInd].hi, bid_roundbound_128[rndInd].lo, z.w[4], z.w[3]) {
            c_prov = c_prov + 1
            if (c_prov == (1 << 53)) {
                c_prov = 1 << 52;
                e_out = e_out + 1;
            } else if (c_prov == (1 << 52)) && (e_out == 1) {
                let rnd_mode = roundboundIndex(rnd_mode) >> 2
                if rnd_mode + (s & 1) == 2 {
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
        return return_double(s, e_out, c_prov);
    }
    
    //
    //   This pack macro doesnot check for coefficients above 2^53
    //
    static func get_BID64_small_mantissa(_ sgn:UInt64, _ expon:Int, _ coeff:UInt64, _ rnd_mode:Rounding, _ fpsc: inout Status) -> UInt64 {
        var C128 = UInt128(), Q_low = UInt128(), Stemp = UInt128()
        var r, mask, _C64, remainder_h:UInt64
        var extra_digits, amount, amount2:Int
        var expon = expon, coeff = coeff, CY = UInt64(0), QH = UInt64(0), carry = UInt64(0)
        
        // check for possible underflow/overflow
        if (UInt(expon) >= 3 * 256) {
            if (expon < 0) {
                // underflow
                if (expon + MAX_DIGITS < 0) {
                    fpsc.formUnion([.underflow, .inexact])
                    if (rnd_mode == BID_ROUNDING_DOWN && sgn != 0) {
                        return 0x8000000000000001;
                    }
                    if (rnd_mode == BID_ROUNDING_UP && sgn == 0) {
                        return 1;
                    }
                    
                    // result is 0
                    return sgn;
                }
                
                var rmode = roundboundIndex(rnd_mode) >> 2
                if (sgn != 0 && UInt(rmode - 1) < 2) {
                    rmode = 3 - rmode;
                }
                
                // get digits to be shifted out
                extra_digits = -expon;
                C128.lo = coeff + bid_round_const_table[rmode][extra_digits];
                
                // get coeff*(2^M[extra_digits])/10^extra_digits
                __mul_64x128_full(&QH, &Q_low, C128.lo, bid_reciprocals10_128[extra_digits]);
                
                // now get P/10^extra_digits: shift Q_high right by M[extra_digits]-128
                amount = Int(bid_recip_scale[extra_digits])
                
                _C64 = QH >> amount;
                
                if (rmode == 0) {   //BID_ROUNDING_TO_NEAREST
                    if (_C64 & 1 != 0) {
                        // check whether fractional part of initial_P/10^extra_digits is exactly .5
                        
                        // get remainder
                        amount2 = 64 - amount
                        remainder_h = 0
                        remainder_h &-= 1
                        remainder_h >>= amount2
                        remainder_h = remainder_h & QH
                        
                        if (remainder_h == 0 && (Q_low.hi < bid_reciprocals10_128[extra_digits].hi
                                || (Q_low.hi == bid_reciprocals10_128[extra_digits].hi
                                    && Q_low.lo < bid_reciprocals10_128[extra_digits].lo))) {
                            _C64-=1
                        }
                    }
                }
                
                if fpsc.contains(.inexact) {
                    fpsc.insert(.underflow)
                } else {
                    var status = Status.inexact // BID_INEXACT_EXCEPTION;
                    // get remainder
                    remainder_h = QH << (64 - amount);
                    
                    switch rnd_mode {
                        case BID_ROUNDING_TO_NEAREST, BID_ROUNDING_TIES_AWAY:
                            // test whether fractional part is 0
                            if (remainder_h == 0x8000000000000000
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
                            __add_carry_out(&Stemp.lo, &CY, Q_low.lo, bid_reciprocals10_128[extra_digits].lo);
                            __add_carry_in_out(&Stemp.hi, &carry, Q_low.hi, bid_reciprocals10_128[extra_digits].hi, CY);
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
            
            while coeff < 1_000_000_000_000_000 && expon >= 3 * 256 {
                expon-=1
                coeff = (coeff << 3) + (coeff << 1)
            }
            if expon > MAX_EXPON {
                fpsc.formUnion([.overflow, .inexact])
                
                // overflow
                r = sgn | INFINITY_MASK64
                switch rnd_mode {
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
            } else {
                mask = 1
                mask <<= EXPONENT_SHIFT_SMALL64
                if (coeff >= mask) {
                    r = UInt64(expon)
                    r <<= EXPONENT_SHIFT_LARGE64
                    r |= (sgn | SPECIAL_ENCODING_MASK64)
                    // add coeff, without leading bits
                    mask = (mask >> 2) - 1
                    coeff &= mask
                    r |= coeff
                    return r
                }
            }
        }
        
        r = UInt64(expon)
        r <<= EXPONENT_SHIFT_SMALL64
        r |= (coeff | sgn)
        return r
    }
    
}


