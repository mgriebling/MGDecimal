//
//  Decimal32-Conv.swift
//  
//
//  Created by Mike Griebling on 2022-03-20.
//

import Foundation

extension Decimal32 {
    
    ////////////////////////////////////////
    // BID32 definitions
    ////////////////////////////////////////
    static let MAX_EXPON                = 191
    static let MIN_EXPON                = 0
    static let EXPONENT_BIAS            = 101
    static let MAX_DIGITS               = 7
    static let P7                       = MAX_DIGITS
    static let MAX_NUMBER               = 9_999_999
    static let MAX_NUMBERP1             = MAX_NUMBER+1

    ////////////////////////////////////////
    // Constant Definitions
    ///////////////////////////////////////
    static let SPECIAL_ENCODING_MASK32  = UInt32(0x6000_0000)
    static let MASK_STEERING_BITS32     = SPECIAL_ENCODING_MASK32
    static let SINFINITY_MASK32         = UInt32(0xf800_0000)
    static let INFINITY_MASK32          = UInt32(0x7800_0000)
    static let MASK_INF32               = INFINITY_MASK32
    static let LARGE_COEFF_MASK32       = UInt32(0x007f_ffff)
    static let MASK_BINARY_SIG1_32      = LARGE_COEFF_MASK32
    static let LARGE_COEFF_HIGH_BIT32   = UInt32(0x0080_0000)
    static let MASK_BINARY_OR2_32       = LARGE_COEFF_HIGH_BIT32
    static let SMALL_COEFF_MASK32       = UInt32(0x001f_ffff)
    static let MASK_BINARY_SIG2_32      = SMALL_COEFF_MASK32
    static let EXPONENT_MASK32          = UInt32(0xff)
    static let LARGEST_BID32            = UInt32(0x77f8_967f)
    static let MASK_BINARY_EXPONENT1_32 = UInt32(0x7f80_0000)
    static let MASK_BINARY_EXPONENT2_32 = UInt32(0x1fe0_0000)
    static let NAN_MASK32               = UInt32(0x7c00_0000)
    static let MASK_NAN32               = NAN_MASK32
    static let SNAN_MASK32              = UInt32(0x7e00_0000)
    static let SSNAN_MASK32             = UInt32(0xfe00_0000)
    static let MASK_SNAN32              = SNAN_MASK32
    static let QUIET_MASK32             = UInt32(0xfdff_ffff)
    static let SIGN_MASK32              = UInt32(0x8000_0000)
    static let COMB_MASK32              = UInt32(0x7ff0_0000)
    static let MASK_SIGN32              = SIGN_MASK32
    static let BINARY_EXPONENT_BIAS     = 0x3ff
    static let UPPER_EXPON_LIMIT        = 51
    
    static let NAN_MASK12 = NAN_MASK32 >> 20
    static let INF_MASK12 = INFINITY_MASK32 >> 20
    static let SPE_MASK12 = SPECIAL_ENCODING_MASK32 >> 20
    
    // **********************************************************************
    
    static func bid_to_dpd32 (_ pba:UInt32) -> UInt32 {
        let ba = pba
        var res : UInt32
        let sign = (ba & SIGN_MASK32)
        let comb = (ba & COMB_MASK32) >> 20
        var trailing = (ba & 0xfffff)
        var nanb = UInt32(0), exp = 0
        var bcoeff = UInt32(0)
        
        // Detect infinity, and return canonical infinity
        if (comb & NAN_MASK12) == INF_MASK12 {
            return sign | INFINITY_MASK32
            // Detect NaN, and canonicalize trailing
        } else if (comb & NAN_MASK12) == NAN_MASK12 {
            if trailing > 999999 {
                trailing = 0
            }
            nanb = ba & 0xfe00_0000
            exp = 0
            bcoeff = trailing
        } else {    // Normal number
            if (comb & SPE_MASK12) == SPE_MASK12 {    // G0..G1 = 11 -> exp is G2..G11
                exp = Int((comb >> 1) & 0xff)
                bcoeff = ((8 + (comb & 1)) << 20) | trailing
            } else {
                exp = Int((comb >> 3) & 0xff)
                bcoeff = ((comb & 7) << 20) | trailing
            }
            // Zero the coefficient if non-canonical (>= 10^7)
            if bcoeff > MAX_NUMBER {
                bcoeff = 0
            }
        }
        
        let b0 = bcoeff / 1000000
        let b1 = Int(bcoeff / 1000) % 1000
        let b2 = Int(bcoeff % 1000)
        let dcoeff = (bid_b2d[b1] << 10) | bid_b2d[b2]
        
        if b0 >= 8 {   // is b0 8 or 9?
            res = UInt32(UInt64(sign | ((SPE_MASK12 | UInt32((exp >> 6) << 7) | ((b0 & 1) << 6) | UInt32(exp & 0x3f)) << 20)) | dcoeff)
        } else {   // else b0 is 0..7
            res = UInt32(UInt64(sign | ((UInt32((exp >> 6) << 9) | (b0 << 6) | UInt32(exp & 0x3f)) << 20)) | dcoeff)
        }
        
        res |= nanb
        return res
    }


    static func dpd_to_bid32 (_ pda: UInt32) -> UInt32 {
        let in1 = pda
        let sign = in1 & SIGN_MASK32
        let comb = (in1 & COMB_MASK32) >> 20
        let trailing = Int(in1 & 0x000fffff)
        var res : UInt32
        var nanb = UInt32()
        var exp = 0
        var d0 = UInt32()
        
        if (comb & NAN_MASK12) == 0x780 {    // G0..G4 = 11110 -> Inf
            return in1 & SINFINITY_MASK32
        } else if (comb & NAN_MASK12) == NAN_MASK12 {    // G0..G5 = 11111 -> NaN
            nanb = in1 & SSNAN_MASK32
            exp = 0
        } else {
            // Normal number
            if (comb & SPE_MASK12) == SPE_MASK12 {    // G0..G1 = 11 -> d0 = 8 + G4
                d0 = ((comb >> 6) & 1) | 8;
                exp = Int(((comb & 0x180) >> 1) | (comb & 0x3f))
            } else {
                d0 = (comb >> 6) & 0x7
                exp = Int(((comb & SPE_MASK12) >> 3) | (comb & 0x3f))
            }
        }
        let d1 = bid_d2b2[(trailing >> 10) & 0x3ff]
        let d2 = bid_d2b[(trailing) & 0x3ff]
        
        let bcoeff = UInt32(d2 + d1 + UInt64(1000000 * d0))
        if bcoeff < 0x800000 {
            res = UInt32(exp << 23) | bcoeff | sign
        } else {
            res = UInt32(exp << 21) | sign | SPECIAL_ENCODING_MASK32 | (bcoeff & 0x1fffff)
        }
        
        res |= nanb
        return res
    }

    
    static func bid32_to_double (_ x: UInt32, _ rmode: Rounding, _ pfpsf: inout Status) -> Double {
        var c = UInt128(), k = 0, e = 0, s = 0
        if let res = unpack_bid32(x, &s, &e, &k, &c.w[1], &pfpsf) { return res }
        
        // Correct to 2^112 <= c < 2^113 with corresponding exponent adding 113-24=89
        // In fact shift a further 6 places ready for reciprocal multiplication
        // Thus (113-24)+6=95, a shift of 31 given that we've already upacked in c.w[1]
        c.w[1] = c.w[1] << 31
        c.w[0] = 0
        k = k + 89
        
        // Check for "trivial" overflow, when 10^e * 1 > 2^{sci_emax+1}, just to
        // keep tables smaller (it would be intercepted later otherwise).
        //
        // (Note that we may have normalized the coefficient, but we have a
        //  corresponding exponent postcorrection to account for; this can
        //  afford to be conservative anyway.)
        //
        // We actually check if e >= ceil((sci_emax + 1) * log_10(2))
        // which in this case is e >= ceil(1024 * log_10(2)) = ceil(308.25) = 309
        
        // Look up the breakpoint and approximate exponent
        let m_min = bid_breakpoints_binary64[e+358]
        var e_out = bid_exponents_binary64[e+358] - Int(k)
        
        // Choose provisional exponent and reciprocal multiplier based on breakpoint
        var r = UInt256()
        if (c.w[1] < m_min.w[1]) {
            r = bid_multipliers1_binary64[e+358]
        } else {
            r = bid_multipliers2_binary64[e+358]
            e_out = e_out + 1;
        }
        
        // Do the reciprocal multiplication
        var z = UInt384()
        __mul_64x256_to_320(&z, c.w[1], r)
        z.w[5]=z.w[4]; z.w[4]=z.w[3]; z.w[3]=z.w[2]; z.w[2]=z.w[1]; z.w[1]=z.w[0]; z.w[0]=0
        
        // Check for exponent underflow and compensate by shifting the product
        // Cut off the process at precision+2, since we can't really shift further
        
        var c_prov = Int(z.w[5])
        
        // Round using round-sticky words
        // If we spill into the next binade, correct
        let rind = roundboundIndex(rmode, s != 0, c_prov)
        if (lt128(bid_roundbound_128[rind].w[1], bid_roundbound_128[rind].w[0], z.w[4], z.w[3])) {
            c_prov = c_prov + 1;
        }
        c_prov = c_prov & ((1 << 52) - 1);
        
        // Set the inexact and underflow flag as appropriate
        
        if (z.w[4] != 0) || (z.w[3] != 0) {
            pfpsf.insert(.inexact)
        }
        // Package up the result as a binary floating-point number
        return return_double(s, e_out, UInt64(c_prov))
    }

    
    static func int64_to_BID32 (_ value:Int64, _ rnd_mode:Rounding, _ state: inout Status) -> Decimal32 {
        // Dealing with 64-bit integer
        let x_sign32 : UInt32 = (value < 0 ? SIGN_MASK32 : 0)
        let C = UInt64(value.magnitude) // if the integer is negative, use the absolute value
        
        var res: UInt32
        if C <= UInt64(Decimal32.MAX_NUMBER) { // |C| <= 10^7-1 and the result is exact
            if C < UInt64(LARGE_COEFF_HIGH_BIT32) { // C < 2^23
                res = x_sign32 | 0x3280_0000 | UInt32(C) & LARGE_COEFF_MASK32
            } else { // C >= 2^23
                res = x_sign32 | 0x6ca0_0000 | UInt32(C) & SMALL_COEFF_MASK32
            }
        } else { // |C| >= 10^7 and the result may be inexact
            // the smallest |C| is 10^7 which has 8 decimal digits
            // the largest |C| is SIGN_MASK64 = 9223372036854775808 w/ 19 digits
            var q, ind : Int
            switch C {
                case 0..<100_000_000:               q =  8; ind = 1  // number of digits to remove for q = 8
                case  ..<1_000_000_000:             q =  9; ind = 2  // number of digits to remove for q = 9
                case  ..<10_000_000_000:            q = 10; ind = 3  // number of digits to remove for q = 10
                case  ..<100_000_000_000:           q = 11; ind = 4  // number of digits to remove for q = 11
                case  ..<1_000_000_000_000:         q = 12; ind = 5  // number of digits to remove for q = 12
                case  ..<10_000_000_000_000:        q = 13; ind = 6  // number of digits to remove for q = 13
                case  ..<100_000_000_000_000:       q = 14; ind = 7  // number of digits to remove for q = 14
                case  ..<1_000_000_000_000_000:     q = 15; ind = 8  // number of digits to remove for q = 11
                case  ..<10_000_000_000_000_000:    q = 16; ind = 9  // number of digits to remove for q = 12
                case  ..<100_000_000_000_000_000:   q = 17; ind = 10 // number of digits to remove for q = 13
                case  ..<1_000_000_000_000_000_000: q = 18; ind = 11 // number of digits to remove for q = 14
                default:                            q = 19; ind = 12 // number of digits to remove for q = 19
            }
//            if C < 100_000_000 { // x < 10^8
//                q = 8
//                ind = 1    // number of digits to remove for q = 8
//            } else if C < 1_000_000_000 { // C < 10^9
//                q = 9
//                ind = 2   // number of digits to remove for q = 9
//            } else if C < 10_000_000_000 { // C < 10^10
//                q = 10
//                ind = 3  // number of digits to remove for q = 10
//            } else if C < 100_000_000_000 { // C < 10^11
//                q = 11
//                ind = 4  // number of digits to remove for q = 11
//            } else if C < 1_000_000_000_000 { // C < 10^12
//                q = 12
//                ind = 5  // number of digits to remove for q = 12
//            } else if C < 10_000_000_000_000 { // C < 10^13
//                q = 13
//                ind = 6  // number of digits to remove for q = 13
//            } else if C < 100_000_000_000_000 { // C < 10^14
//                q = 14
//                ind = 7  // number of digits to remove for q = 14
//            } else if C < 1_000_000_000_000_000 { // C < 10^15
//                q = 15
//                ind = 8  // number of digits to remove for q = 15
//            } else if C < 10_000_000_000_000_000 { // C < 10^16
//                q = 16
//                ind = 9  // number of digits to remove for q = 16
//            } else if C < 100_000_000_000_000_000 { // C < 10^17
//                q = 17
//                ind = 10  // number of digits to remove for q = 17
//            } else if C < 1_000_000_000_000_000_000 { // C < 10^18
//                q = 18
//                ind = 11  // number of digits to remove for q = 18
//            } else { // C < 10^19
//                q = 19
//                ind = 12    // number of digits to remove for q = 19
//            }
            // overflow and underflow are not possible
            // Note: performance can be improved by inlining this call
            var is_midpoint_lt_even = false, is_midpoint_gt_even = false, is_inexact_lt_midpoint = false
            var is_inexact_gt_midpoint = false, res64 = UInt64(0), incr_exp = 0
            bid_round64_2_18 ( // will work for 19 digits too if C fits in 64 bits
                q, ind, C, &res64, &incr_exp,
                &is_midpoint_lt_even, &is_midpoint_gt_even,
                &is_inexact_lt_midpoint, &is_inexact_gt_midpoint)
            res = UInt32(res64)
            if incr_exp != 0 {
                ind+=1
            }
            // set the inexact flag
            if is_inexact_lt_midpoint || is_inexact_gt_midpoint || is_midpoint_lt_even || is_midpoint_gt_even {
                state.insert(.inexact)
            }
            // general correction from RN to RA, RM, RP, RZ; result uses ind for exp
            if rnd_mode != BID_ROUNDING_TO_NEAREST {
                let x_sign = value < 0
                if ((!x_sign && ((rnd_mode == .up && is_inexact_lt_midpoint) ||
                    ((rnd_mode == .toNearestOrEven || rnd_mode == .up) && is_midpoint_gt_even))) ||
                   (x_sign && ((rnd_mode == .down && is_inexact_lt_midpoint) ||
                   ((rnd_mode == .toNearestOrEven || rnd_mode == .down) && is_midpoint_gt_even)))) {
                    res = res + 1
                    if res == MAX_NUMBERP1 { // res = 10^7 => rounding overflow
                        res = 1_000_000 // 10^6
                        ind = ind + 1
                    }
                } else if ((is_midpoint_lt_even || is_inexact_gt_midpoint) &&
                           ((x_sign && (rnd_mode == .towardZero || rnd_mode == .down)) ||
                            (!x_sign && (rnd_mode == .towardZero || rnd_mode == .down)))) {
                    res = res - 1
                    // check if we crossed into the lower decade
                    if res == 999_999 { // 10^6 - 1
                        res = UInt32(MAX_NUMBER)  // 10^7 - 1
                        ind = ind - 1
                    }
                } else {
                    // exact, the result is already correct
                }
            }
            if res < LARGE_COEFF_HIGH_BIT32 { // res < 2^23
                res = x_sign32 | UInt32(ind + EXPONENT_BIAS) << 23 | res
            } else { // res >= 2^23
                res = x_sign32 | SPECIAL_ENCODING_MASK32 | UInt32(ind + EXPONENT_BIAS) << 21 | (res & SMALL_COEFF_MASK32)
            }
        }
        return Decimal32(raw: res)
    }
    
    static func double_to_bid32 (_ x:Double, _ rnd_mode:Rounding, _ state: inout Status) -> UInt32 {
        // Unpack the input
        var s = 0, e = 0, t = 0
        var c = UInt128(w: [0,0])
        if let res = unpack_binary64 (x, &s, &e, &c.w[0], &t, &state) { return UInt32(res) }
        
        // Now -1126<=e<=971 (971 for max normal, -1074 for min normal, -1126 for min denormal)
        
        // Treat like a quad input for uniformity, so (2^{113-53} * c * r) >> 320,
        // where 320 is the truncation value for the reciprocal multiples, exactly
        // five 64-bit words. So we shift 113-53=60 places
        //
        // Remember to compensate for the fact that exponents are integer for quad
        c.w[1] = 0
        c = sll128_short(c.w[1], c.w[0], 60)
        t += (113 - 53)
        e -= (113 - 53) // Now e belongs [-1186;911].
        
        // Check for "trivial" overflow, when 2^e * 2^112 > 10^emax * 10^d.
        // We actually check if e >= ceil((emax + d) * log_2(10) - 112)
        // This could be intercepted later, but it's convenient to keep tables smaller
        if e >= 211 {
            state.formUnion([.overflow, .inexact])
            return return_bid32_ovf(s)
        }
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
        if e <= 0 {
            var cint:UInt128
            let a = -(e + t)
            cint = c
            if a <= 0 {
                cint = srl128(cint.w[1], cint.w[0], -e)
                if ((cint.w[1] == 0) && (cint.w[0] < MAX_NUMBERP1)) {
                    return return_bid32(s, EXPONENT_BIAS, Int(cint.w[0]))
                }
            } else if a <= 48 {
                var pow5 = bid_coefflimits_bid32[a]
                cint = srl128(cint.w[1], cint.w[0], t)
                if le128(cint.w[1], cint.w[0], pow5.w[1], pow5.w[0]) {
                    var cc = cint
                    pow5 = bid_power_five[a]
                    __mul_128x128_low(&cc, cc, pow5)
                    return return_bid32(s, EXPONENT_BIAS - a, Int(cc.w[0]))
                }
            }
        }
        
        // Check for "trivial" underflow, when 2^e * 2^113 <= 10^emin * 1/4,
        // so test e <= floor(emin * log_2(10) - 115)
        // In this case just fix ourselves at that value for uniformity.
        //
        // This is important not only to keep the tables small but to maintain the
        // testing of the round/sticky words as a correct rounding method
        if e <= -450 {
            e = -450
        }
        
        // Now look up our exponent e, and the breakpoint between e and e+1
        let m_min = bid_breakpoints_bid32[e+450]
        var e_out = bid_exponents_bid32[e+450]
        
        // Choose exponent and reciprocal multiplier based on breakpoint
        var r:UInt256
        if le128(c.w[1], c.w[0], m_min.w[1], m_min.w[0]) {
            r = bid_multipliers1_bid32[e+450]
        } else {
            r = bid_multipliers2_bid32[e+450]
            e_out += 1
        }
        
        // Do the reciprocal multiplication
        var z:UInt384=UInt384()
        __mul_128x256_to_384(&z, c, r)
        var c_prov = z.w[5]
        
        // Test inexactness and underflow (when testing tininess before rounding)
        if ((z.w[4] != 0) || (z.w[3] != 0)) {
            // __set_status_flags(pfpsf,BID_INEXACT_EXCEPTION);
            state.insert(.inexact)
            if (c_prov < 1000000) {
                state.insert(.underflow)
                // __set_status_flags(pfpsf,BID_UNDERFLOW_EXCEPTION);
            }
        }
        
        // Round using round-sticky words
        // If we spill over into the next decade, correct
        // Flag underflow where it may be needed even for |result| = SNN
        let ind = roundboundIndex(rnd_mode, s == 1, Int(c_prov))
        if (lt128(bid_roundbound_128[ind].w[1], bid_roundbound_128[ind].w[0], z.w[4], z.w[3])) {
            c_prov += 1
            if c_prov == MAX_NUMBERP1 {
                c_prov = 1_000_000
                e_out += 1
            } else if c_prov == 1_000_000 && e_out == 0 {
                let ind = roundboundIndex(rnd_mode, false, 0) >> 2
                if ((((ind & 3) == 0) && (z.w[4] <= 17524406870024074035)) ||
                    ((ind + (s & 1) == 2) && (z.w[4] <= 16602069666338596454))) {
                    state.insert(.underflow)
                    // __set_status_flags(pfpsf,BID_UNDERFLOW_EXCEPTION);
                }
            }
        }
        
        // Check for overflow
        if e_out > 90 + EXPONENT_BIAS {
            // __set_status_flags(pfpsf, BID_OVERFLOW_INEXACT_EXCEPTION);
            state.formUnion([.overflow, .inexact])
            return return_bid32_ovf(s)
        }
        
        // Set the inexact flag as appropriate and check underflow
        // It's no doubt superfluous to check inexactness, but anyway...
        if z.w[4] != 0 || z.w[3] != 0 {
            state.insert(.inexact)
            if c_prov < 1_000_000 {
                state.insert(.underflow)
            }
        }
        
        // Package up the result
        return return_bid32 (s, e_out, Int(c_prov))
    }

    static func bid_round64_2_18 (_ q: Int, _ x:Int, _ C: UInt64, _ ptr_Cstar: inout UInt64, _ incr_exp: inout Int,
                                  _ ptr_is_midpoint_lt_even: inout Bool, _ ptr_is_midpoint_gt_even: inout Bool,
                                  _ ptr_is_inexact_lt_midpoint: inout Bool, _ ptr_is_inexact_gt_midpoint: inout Bool) {
        // Note:
        //    In round128_2_18() positive numbers with 2 <= q <= 18 will be
        //    rounded to nearest only for 1 <= x <= 3:
        //     x = 1 or x = 2 when q = 17
        //     x = 2 or x = 3 when q = 18
        // However, for generality and possible uses outside the frame of IEEE 754
        // this implementation works for 1 <= x <= q - 1
        
        // assume *ptr_is_midpoint_lt_even, *ptr_is_midpoint_gt_even,
        // *ptr_is_inexact_lt_midpoint, and *ptr_is_inexact_gt_midpoint are
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
        var P128: UInt128 = UInt128(w:[0,0])
        __mul_64x64_to_128MACH (&P128, C, bid_Kx64[ind]);
        // calculate C* = floor (P128) and f*
        // Cstar = P128 >> Ex
        // fstar = low Ex bits of P128
        let shift = bid_Ex64m64[ind];    // in [3, 56]
        var Cstar = P128.w[1] >> shift;
        var fstar: UInt128 = UInt128(w:[0,0])
        fstar.w[1] = P128.w[1] & bid_mask64[ind];
        fstar.w[0] = P128.w[0]
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
        if (fstar.w[1] > bid_half64[ind] || (fstar.w[1] == bid_half64[ind] && fstar.w[0] != 0)) {
            // f* > 1/2 and the result may be exact
            // Calculate f* - 1/2
            let tmp64 = fstar.w[1] - bid_half64[ind];
            if (tmp64 != 0 || fstar.w[0] > bid_ten2mxtrunc64[ind]) {    // f* - 1/2 > 10^(-x)
                ptr_is_inexact_lt_midpoint = true
            }    // else the result is exact
        } else {    // the result is inexact; f2* <= 1/2
            ptr_is_inexact_gt_midpoint = true
        }
        // check for midpoints (could do this before determining inexactness)
        if (fstar.w[1] == 0 && fstar.w[0] <= bid_ten2mxtrunc64[ind]) {
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
    
    /*****************************************************************************
     *
     *    BID32 pack/unpack macros
     *
     *****************************************************************************/
    static func unpack_BID32 (_ sgn: inout UInt32, _ exp: inout Int, _ coeff: inout UInt32, _ x: UInt32) -> Bool {
        sgn = x & SIGN_MASK32
        
        if (x & SPECIAL_ENCODING_MASK32) == SPECIAL_ENCODING_MASK32 {
            // special encodings
            if (x & INFINITY_MASK32) == INFINITY_MASK32 {
                coeff = x & 0xfe0f_ffff
                if (x & 0x000f_ffff) >= 1_000_000 {
                    coeff = x & SSNAN_MASK32
                }
                if (x & NAN_MASK32) == INFINITY_MASK32 {
                    coeff = x & SINFINITY_MASK32
                }
                exp = 0
                return false    // NaN or Infinity
            }
            // coefficient
            coeff = (x & SMALL_COEFF_MASK32) | LARGE_COEFF_HIGH_BIT32
            
            // check for non-canonical value
            if coeff > MAX_NUMBER {
                coeff = 0
            }
            
            // get exponent
            let tmp = x >> 21
            exp = Int(tmp & EXPONENT_MASK32)
            return coeff != 0
        }
        
        // exponent
        let tmp = x >> 23;
        exp = Int(tmp & EXPONENT_MASK32)
        
        // coefficient
        coeff = (x & LARGE_COEFF_MASK32)
        return coeff != 0
    }
    
    //
    //   no overflow/underflow checks
    //
    static func very_fast_get_BID32 (_ sgn: UInt32, _ expon: Int, _ coeff: UInt32) -> UInt32  {
        var mask = UInt32(1) << 23
        
        // check whether coefficient fits in 10*2+3 bits
        var r: UInt32
        if coeff < mask {
            r = UInt32(expon)
            r <<= 23
            r |= (coeff | sgn)
            return r
        }
        // special format
        r = UInt32(expon)
        r <<= 21
        r |= (sgn | SPECIAL_ENCODING_MASK32)
        // add coeff, without leading bits
        mask = (1 << 21) - 1
        r |= coeff & mask
        return r
    }
    
    static func fast_get_BID32 (_ sgn: UInt32, _ expon: Int, _ coeff: UInt32) -> UInt32  {
        // var mask = UInt32(1) << 23
        var expon = expon
        var coeff = coeff
        if coeff > MAX_NUMBER {
            expon += 1
            coeff = 1000000
        }
        return very_fast_get_BID32(sgn, expon, coeff)
//        // check whether coefficient fits in 10*2+3 bits
//        var r: UInt32
//        if coeff < mask {
//            r = UInt32(expon)
//            r <<= 23
//            r |= (coeff | sgn)
//            return r;
//        }
//        // special format
//        r = UInt32(expon)
//        r <<= 21
//        r |= (sgn | SPECIAL_ENCODING_MASK32)
//        // add coeff, without leading bits
//        mask = (1 << 21) - 1
//        r |= coeff & mask
//        return r
    }
    
    //
    //   General pack macro for BID32
    //
    static func get_BID32 (_ sgn: UInt32, _ expon: Int, _ coeff: UInt32, _ rmode: Rounding, _ fpsc: inout Status) -> UInt32 {
        var expon = expon
        var coeff = coeff
        var rmode = rmode
        
        if coeff > MAX_NUMBER {
            expon += 1
            coeff = 1000000
        }
        
        // check for possible underflow/overflow
        if UInt32(expon) > MAX_EXPON {
            if expon < 0 {
                // underflow
                if expon + MAX_DIGITS < 0 {
                    fpsc.formUnion([.underflow, .inexact])
                    if rmode == .down && sgn != 0 {
                        return 0x80000001
                    }
                    if (rmode == .up && sgn == 0) {
                        return 1
                    }
                }
                // result is 0
                return sgn
            }
            
            // swap up & down round modes when negative
            if sgn != 0 {
                if rmode == .up { rmode = .down }
                else if rmode == .down { rmode = .up }
            }
            
            // determine the rounding table index
            let roundIndex = roundboundIndex(rmode, false, 0) >> 2
            
            // get digits to be shifted out
            let extra_digits = -expon
            coeff += UInt32(bid_round_const_table[roundIndex][extra_digits])
            
            // get coeff*(2^M[extra_digits])/10^extra_digits
            var Q : UInt128 = UInt128(w: [0, 0])
            __mul_64x64_to_128 (&Q, UInt64(coeff), bid_reciprocals10_64[extra_digits]);
            
            // now get P/10^extra_digits: shift Q_high right by M[extra_digits]-128
            let amount = bid_short_recip_scale[extra_digits]
            
            var _C64 = Q.w[1] >> amount
            var remainder_h = UInt64(0)
            
            if rmode == BID_ROUNDING_TO_NEAREST {
                if (_C64 & 1 != 0) {
                    // check whether fractional part of initial_P/10^extra_digits is exactly .5
                    
                    // get remainder
                    let amount2 = 64 - amount
                    remainder_h = 0
                    remainder_h &-= 1
                    remainder_h >>= amount2
                    remainder_h = remainder_h & Q.w[1]
                    
                    if remainder_h == 0 && Q.w[0] < bid_reciprocals10_64[extra_digits] {
                        _C64 -= 1
                    }
                }
            }
            
            if fpsc.contains(.inexact) {
                fpsc.insert(.underflow)
            } else {
                var status = Status.inexact
                // get remainder
                remainder_h = Q.w[1] << (64 - amount)
                
                switch rmode {
                    case BID_ROUNDING_TO_NEAREST, BID_ROUNDING_TIES_AWAY:
                        // test whether fractional part is 0
                        if (remainder_h == Decimal64.SIGN_MASK64 && (Q.w[0] < bid_reciprocals10_64[extra_digits])) {
                            status = Status.clearFlags // BID_EXACT_STATUS;
                        }
                    case BID_ROUNDING_DOWN, BID_ROUNDING_TO_ZERO:
                        if remainder_h == 0 && Q.w[0] < bid_reciprocals10_64[extra_digits] {
                            status = Status.clearFlags // BID_EXACT_STATUS;
                        }
                    default:
                        // round up
                        var Stemp = UInt64(0), carry = UInt64(0)
                        __add_carry_out (&Stemp, &carry, Q.w[0], bid_reciprocals10_64[extra_digits]);
                        if (remainder_h >> (64 - amount)) + carry >= UInt64(1) << amount {
                            status = Status.clearFlags // BID_EXACT_STATUS;
                        }
                }
                
                if !status.isEmpty {
                    status.insert(.underflow)
                    fpsc.formUnion(status)
                    //                  __set_status_flags (fpsc, BID_UNDERFLOW_EXCEPTION | status);
                }
                
                return sgn | UInt32(_C64)
            }
            
            if coeff == 0 { if expon > MAX_EXPON { expon = MAX_EXPON } }
            while coeff < 1000000 && expon > MAX_EXPON {
                coeff = (coeff << 3) + (coeff << 1)
                expon -= 1
            }
            if UInt32(expon) > MAX_EXPON {
                fpsc.formUnion([.overflow, .inexact])
                // overflow
                var r = sgn | INFINITY_MASK32
                switch (rmode) {
                    case BID_ROUNDING_DOWN:
                        if sgn == 0 {
                            r = LARGEST_BID32
                        }
                    case BID_ROUNDING_TO_ZERO:
                        r = sgn | LARGEST_BID32
                    case BID_ROUNDING_UP:
                        // round up
                        if sgn != 0 {
                            r = sgn | LARGEST_BID32
                        }
                    default: break
                }
                return r
            }
        }
        
        var mask = UInt32(1) << 23
        
        // check whether coefficient fits in DECIMAL_COEFF_FIT bits
        if coeff < mask {
            var r = UInt32(expon)
            r <<= 23
            r |= (coeff | sgn)
            return r
        }
        
        // special format
        var r = UInt32(expon)
        r <<= 21
        r |= sgn | SPECIAL_ENCODING_MASK32
        
        // add coeff, without leading bits
        mask = (UInt32(1) << 21) - 1
        r |= coeff & mask
        return r
    }
    
    //
    //   General pack macro for BID32
    //
    static func get_BID32_UF (_ sgn: UInt32, _ expon: Int, _ coeff: UInt64, _ R: Int, _ rmode:Rounding, _ fpsc: inout Status) -> UInt32 {
        var expon = expon
        var coeff = coeff
        var rmode = rmode
        
        if coeff > MAX_NUMBER {
            expon+=1
            coeff = 1000000
        }
        // check for possible underflow/overflow
        if UInt32(expon) > MAX_EXPON {
            if expon < 0 {
                // underflow
                if (expon + MAX_DIGITS < 0) {
                    fpsc.formUnion([.underflow, .inexact])
                    if (rmode == .down && sgn != 0) {
                        return 0x80000001
                    }
                    if (rmode == .up && sgn == 0) {
                        return 1
                    }
                    // result is 0
                    return sgn
                }
                
                // swap up & down round modes when negative
                if sgn != 0 {
                    if rmode == .up { rmode = .down }
                    else if rmode == .down { rmode = .up }
                }
                
                // determine the rounding table index
                let roundIndex = roundboundIndex(rmode, false, 0) >> 2
                
                // 10*coeff
                coeff = (coeff << 3) + (coeff << 1)
                if R != 0 {
                    coeff |= 1
                }
                
                let extra_digits = 1-expon;
                coeff += bid_round_const_table[roundIndex][extra_digits];
                
                // get coeff*(2^M[extra_digits])/10^extra_digits
                var Q:UInt128 = UInt128(w: [0,0])
                __mul_64x64_to_128 (&Q, coeff, bid_reciprocals10_64[extra_digits])
                
                // now get P/10^extra_digits: shift Q_high right by M[extra_digits]-128
                let amount = bid_short_recip_scale[extra_digits]
                
                var _C64 = Q.w[1] >> amount
                
                if rmode == .toNearestOrEven {   //BID_ROUNDING_TO_NEAREST
                    if (_C64 & 1 != 0) {
                        // check whether fractional part of initial_P/10^extra_digits is exactly .5
                        
                        // get remainder
                        let amount2 = 64 - amount;
                        var remainder_h = UInt64(0)
                        remainder_h &-= 1            // Intentional underflow
                        remainder_h >>= amount2
                        remainder_h = remainder_h & Q.w[1]
                        
                        if remainder_h == 0 && (Q.w[0] < bid_reciprocals10_64[extra_digits]) {
                            _C64-=1
                        }
                    }
                }
                
                if fpsc.contains(.inexact) {
                    fpsc.insert(.underflow)
                } else {
                    var status = Status.inexact // BID_INEXACT_EXCEPTION;
                    // get remainder
                    let remainder_h = Q.w[1] << (64 - amount)
                    
                    switch rmode {
                        case BID_ROUNDING_TO_NEAREST, BID_ROUNDING_TIES_AWAY:
                            // test whether fractional part is 0
                            if (remainder_h == Decimal64.SIGN_MASK64 && (Q.w[0] < bid_reciprocals10_64[extra_digits])) {
                                status = Status.clearFlags // BID_EXACT_STATUS;
                            }
                        case BID_ROUNDING_DOWN, BID_ROUNDING_TO_ZERO:
                            if remainder_h == 0 && (Q.w[0] < bid_reciprocals10_64[extra_digits]) {
                                status = Status.clearFlags // BID_EXACT_STATUS;
                            }
                        default:
                            // round up
                            var Stemp = UInt64(0), carry = UInt64(0)
                            __add_carry_out (&Stemp, &carry, Q.w[0], bid_reciprocals10_64[extra_digits])
                            if (remainder_h >> (64 - amount)) + carry >= UInt64(1) << amount {
                                status = Status.clearFlags // BID_EXACT_STATUS;
                            }
                    }
                    
                    if !status.isEmpty {
                        status.insert(.underflow)
                        fpsc.formUnion(status)
                    }
                }
                return sgn | UInt32(_C64)
            }
            
            while coeff < 1000000 && expon > MAX_EXPON {
                coeff = (coeff << 3) + (coeff << 1)
                expon -= 1
            }
            if UInt32(expon) > MAX_EXPON {
                fpsc.formUnion([.overflow, .inexact])
                var r = sgn | INFINITY_MASK32
                switch rmode {
                    case BID_ROUNDING_DOWN:
                        if sgn == 0 {
                            r = LARGEST_BID32
                        }
                    case BID_ROUNDING_TO_ZERO:
                        r = sgn | LARGEST_BID32
                    case BID_ROUNDING_UP:
                        // round up
                        if sgn != 0 {
                            r = sgn | LARGEST_BID32
                        }
                    default: break
                }
                return r
            }
        }
        
        var mask = UInt32(1) << 23;
        var r: UInt32
        
        // check whether coefficient fits in DECIMAL_COEFF_FIT bits
        if coeff < mask {
            r = UInt32(expon)
            r <<= 23;
            r |= UInt32(coeff) | sgn
            return r
        }
        // special format
        r = UInt32(expon)
        r <<= 21
        r |= (sgn | SPECIAL_ENCODING_MASK32)
        // add coeff, without leading bits
        mask = (UInt32(1) << 21) - 1
        r |= (UInt32(coeff) & mask)
        return r
    }
    
    /*****************************************************************************
     *  BID32_to_int64_int
     ****************************************************************************/
    static func bid32_to_int (_ x: UInt32, _ rmode:Rounding, _ pfpsc: inout Status) -> Int {
        var res: Int = 0
        
        // check for NaN or Infinity
        if ((x & MASK_NAN32) == MASK_NAN32 || (x & MASK_INF32) == MASK_INF32) {
            // set invalid flag
            pfpsc.insert(.invalidOperation)
            // return Integer Indefinite
            return Int.max
        }
        // unpack x
        let x_sign = x & MASK_SIGN32; // 0 for positive, MASK_SIGN32 for negative
        var x_exp, C1 : UInt32
        // if steering bits are 11 (condition will be 0), then exponent is G[0:w+1] =>
        if (x & MASK_STEERING_BITS32) == MASK_STEERING_BITS32 {
            x_exp = (x & MASK_BINARY_EXPONENT2_32) >> 21 // biased
            C1 = (x & MASK_BINARY_SIG2_32) | MASK_BINARY_OR2_32
            if C1 > MAX_NUMBER { // non-canonical
                x_exp = 0;
                C1 = 0;
            }
        } else {
            x_exp = (x & MASK_BINARY_EXPONENT1_32) >> 23 // biased
            C1 = x & MASK_BINARY_SIG1_32
        }
        
        // check for zeros (possibly from non-canonical values)
        if C1 == 0 {
            // x is 0
            return 0
        }
        // x is not special and is not zero
        
        // q = nr. of decimal digits in x (1 <= q <= 7)
        //  determine first the nr. of bits in x
        let q = digitsIn(C1)
        let exp = Int(x_exp) - EXPONENT_BIAS // unbiased exponent
        
        if (q + exp) > 19 { // x >= 10^19 ~= 2^63.11... (cannot fit in BID_SINT64)
            // set invalid flag
            pfpsc.insert(.invalidOperation)
            // return Integer Indefinite
            return Int.max
        } else if (q + exp) == 19 { // x = c(0)c(1)...c(q-1)00...0 (19 dec. digits)
            // in this case 2^63.11... ~= 10^19 <= x < 10^20 ~= 2^66.43...
            // so x rounded to an integer may or may not fit in a signed 64-bit int
            // the cases that do not fit are identified here; the ones that fit
            // fall through and will be handled with other cases further,
            // under '1 <= q + exp <= 19'
            var C = UInt128()
            if x_sign != 0 { // if n < 0 and q + exp = 19
                // if n <= -2^63 - 1 then n is too large
                // <=> c(0)c(1)...c(q-1)00...0[19 dec. digits] >= 2^63+1
                // <=> 0.c(0)c(1)...c(q-1) * 10^20 >= 0x5000000000000000a, 1<=q<=7
                // <=> C * 10^(20-q) >= 0x5000000000000000a, 1<=q<=7
                // 1 <= q <= 7 => 13 <= 20-q <= 19 => 10^(20-q) is 64-bit, and so is C1
                __mul_64x64_to_128MACH (&C, UInt64(C1), bid_ten2k64[20 - q]);
                // Note: C1 * 10^(11-q) has 19 or 20 digits; 0x5000000000000000a, has 20
                if (C.w[1] > 0x05 || (C.w[1] == 0x05 && C.w[0] >= 0x0a)) {
                    // set invalid flag
                    pfpsc.insert(.invalidOperation)
                    // return Integer Indefinite
                    return Int.max
                }
                // else cases that can be rounded to a 64-bit int fall through
                // to '1 <= q + exp <= 19'
            } else { // if n > 0 and q + exp = 19
                // if n >= 2^63 then n is too large
                // <=> c(0)c(1)...c(q-1)00...0[19 dec. digits] >= 2^63
                // <=> if 0.c(0)c(1)...c(q-1) * 10^20 >= 0x50000000000000000, 1<=q<=7
                // <=> if C * 10^(20-q) >= 0x50000000000000000, 1<=q<=7
                C.w[1] = 0x0000000000000005
                C.w[0] = 0x0000000000000000
                // 1 <= q <= 7 => 13 <= 20-q <= 19 => 10^(20-q) is 64-bit, and so is C1
                __mul_64x64_to_128MACH (&C, UInt64(C1), bid_ten2k64[20 - q])
                if C.w[1] >= 0x05 {
                    // actually C.w[1] == 0x05 && C.w[0] >= 0x0000000000000000) {
                    // set invalid flag
                    pfpsc.insert(.invalidOperation)
                    // return Integer Indefinite
                    return Int.max
                }
                // else cases that can be rounded to a 64-bit int fall through
                // to '1 <= q + exp <= 19'
            }    // end else if n > 0 and q + exp = 19
        }    // end else if ((q + exp) == 19)
        
        // n is not too large to be converted to int64: -2^63-1 < n < 2^63
        // Note: some of the cases tested for above fall through to this point
        if (q + exp) <= 0 { // n = +/-0.0...c(0)c(1)...c(q-1)
            // return 0
            return 0x0000000000000000
        } else { // if (1 <= q + exp <= 19, 1 <= q <= 7, -6 <= exp <= 18)
            // -2^63-1 < x <= -1 or 1 <= x < 2^63 so x can be rounded
            // to nearest to a 64-bit signed integer
            if exp < 0 { // 2 <= q <= 7, -6 <= exp <= -1, 1 <= q + exp <= 19
                let ind = -exp // 1 <= ind <= 6; ind is a synonym for 'x'
                // chop off ind digits from the lower part of C1
                // C1 fits in 64 bits
                // calculate C* and f*
                // C* is actually floor(C*) in this case
                // C* and f* need shifting and masking, as shown by
                // bid_shiftright128[] and bid_maskhigh128[]
                // 1 <= x <= 6
                // kx = 10^(-x) = bid_ten2mk64[ind - 1]
                // C* = C1 * 10^(-x)
                // the approximation of 10^(-x) was rounded up to 54 bits
                var P128 = UInt128()
                __mul_64x64_to_128MACH(&P128, UInt64(C1), bid_ten2mk64[ind - 1])
                var Cstar = P128.w[1]
                // the top Ex bits of 10^(-x) are T* = bid_ten2mk128trunc[ind].w[0], e.g.
                // if x=1, T*=bid_ten2mk128trunc[0].w[0]=0x1999999999999999
                // C* = floor(C*) (logical right shift; C has p decimal digits,
                //     correct by Property 1)
                // n = C* * 10^(e+x)
                
                // shift right C* by Ex-64 = bid_shiftright128[ind]
                let shift = bid_shiftright128[ind - 1] // 0 <= shift <= 39
                Cstar = Cstar >> shift
                
                if x_sign != 0 {
                    res = -Int(Cstar)
                } else {
                    res = Int(Cstar)
                }
            } else if exp == 0 {
                // 1 <= q <= 7
                // res = +/-C (exact)
                if x_sign != 0 {
                    res = -Int(C1)
                } else {
                    res = Int(C1)
                }
            } else { // if (exp > 0) => 1 <= exp <= 18, 1 <= q <= 7, 2 <= q + exp <= 20
                // (the upper limit of 20 on q + exp is due to the fact that
                // +/-C * 10^exp is guaranteed to fit in 64 bits)
                // res = +/-C * 10^exp (exact)
                if x_sign != 0 {
                    res = -Int(UInt64(C1) * bid_ten2k64[exp])
                } else {
                    res = Int(UInt64(C1) * bid_ten2k64[exp])
                }
            }
        }
        return res
    }
    
    /*
     * Takes a BID32 as input and converts it to a BID128 and returns it.
     */
    static func bid32_to_bid128(_ x:UInt32, _ pfpsc: inout Status) -> UInt128 {
        var sign_x = UInt32(), exponent_x = 0, coefficient_x = UInt32()
        var res = UInt128()
        if !unpack_BID32 (&sign_x, &exponent_x, &coefficient_x, x) {
            if (x & 0x78000000) == 0x78000000 {
                if (x & 0x7e000000) == 0x7e000000 {
                    // sNaN
                    pfpsc.insert(.invalidOperation)
                }
                res.w[0] = UInt64(coefficient_x & 0x000fffff)
                __mul_64x128_low(&res, res.w[0], bid_power10_table_128[27])
                res.w[1] |= ((UInt64(coefficient_x) << 32) & 0xfc00000000000000)
                return res
            }
        }
        var new_coeff = UInt128()
        new_coeff.w[0] = UInt64(coefficient_x)
        new_coeff.w[1] = 0
        return Decimal128.bid_get_BID128_very_fast(UInt64(sign_x) << 32,
                                exponent_x + Decimal128.DECIMAL_EXPONENT_BIAS_128 - EXPONENT_BIAS, new_coeff)
    }    // convert_bid32_to_bid128
    
    /*
     * Takes a BID32 as input and converts it to a BID64 and returns it.
     */
    static func bid32_to_bid64(_ x:UInt32, _ pfpsf: inout Status) -> UInt64 {
        var sign_x = UInt32(), exponent_x = 0, coefficient_x = UInt32()
        var res = UInt64()
        if !unpack_BID32 (&sign_x, &exponent_x, &coefficient_x, x) {
            // Inf, NaN, 0
            if (x & 0x78000000) == 0x78000000 {
                if (x & 0x7e000000) == 0x7e00000 {    // sNaN
                    pfpsf.insert(.invalidOperation)
                }
                res = UInt64(coefficient_x & 0x000fffff)
                res *= 1000000000
                res |= (UInt64(coefficient_x) << 32) & 0xfc00000000000000
                return res
            }
        }
        return Decimal64.very_fast_get_BID64_small_mantissa(UInt64(sign_x) << 32,
                                            exponent_x + Decimal64.DECIMAL_EXPONENT_BIAS - EXPONENT_BIAS,
                                            UInt64(coefficient_x))
    }    // convert_bid32_to_bid64
    
}
