//
//  Macros.swift
//  
//
//  Created by Mike Griebling on 2022-03-06.
//

import Foundation

// define the BID rounding modes
public typealias Rounding = FloatingPointRoundingRule
let BID_ROUNDING_UP = Rounding.up
let BID_ROUNDING_DOWN = Rounding.down
let BID_ROUNDING_TO_ZERO = Rounding.towardZero
let BID_ROUNDING_TO_NEAREST = Rounding.toNearestOrEven
let BID_ROUNDING_TIES_AWAY = Rounding.toNearestOrAwayFromZero

// Use these for now
struct UInt512 { var w = [UInt64](repeating: 0, count: 8) }
struct UInt384 { var w = [UInt64](repeating: 0, count: 6) }
struct UInt256 { var w = [UInt64](repeating: 0, count: 4) }

var isBigEndian: Bool { let one=1; return one == one.bigEndian }

func BID_SWAP128(_ x: inout UInt128) {
    if isBigEndian {
        // swap 64-bit words
        let sw = x.hi
        x.hi = x.lo
        x.lo = sw
    }
}

let BID_LOW_128W = isBigEndian ? 1 : 0
let BID_HIGH_128W = isBigEndian ? 0 : 1

func __L0_MiDi2Str_Lead(_ X:UInt32, _ c_ptr : inout String) {
    var L0_src = bid_midi_tbl[Int(X)]
    if X >= 100 {
        /* Nothing to do */
    } else if X >= 10 {
        L0_src.removeFirst()
    } else {
        L0_src.removeFirst(2)
    }
    c_ptr += L0_src
}

func __L0_MiDi2Str(_ X:UInt32, _ c_ptr : inout String)  {
    let L0_src = bid_midi_tbl[Int(X)]
    c_ptr += L0_src
}

func __L0_Split_MiDi_2(_ X:UInt32, _ ptr : inout [UInt32]) {
    //BID_UINT32 L0_head, L0_tail, L0_tmp;
    var L0_head = X >> 10
    var L0_tail = (X&0x03FF)+(L0_head<<5)-(L0_head<<3)
    let L0_tmp  = L0_tail>>10; L0_head += L0_tmp
    L0_tail = (L0_tail&0x03FF)+(L0_tmp<<5)-(L0_tmp<<3)
    if L0_tail > 999 { L0_tail -= 1000; L0_head += 1 }
    ptr.append(L0_head); ptr.append(L0_tail)
}

func __L0_Split_MiDi_3(_ X:UInt32, _ ptr : inout [UInt32]) {
    var L0_X    = X
    var L0_head = ((L0_X>>17)*34359)>>18
    L0_X   -= L0_head*1000000
    if (L0_X >= 1000000) { L0_X -= 1000000; L0_head+=1 }
    var L0_mid  = L0_X >> 10;
    var L0_tail = (L0_X & (0x03FF))+(L0_mid<<5)-(L0_mid<<3)
    let L0_tmp  = (L0_tail)>>10; L0_mid += L0_tmp
    L0_tail = (L0_tail&(0x3FF))+(L0_tmp<<5)-(L0_tmp<<3)
    if L0_tail > 999 { L0_tail-=1000; L0_mid+=1 }
    ptr.append(L0_head); ptr.append(L0_mid); ptr.append(L0_tail)
}

func __L1_Split_MiDi_6_Lead( _ X:UInt64, _ ptr: inout [UInt32])  {
    if X >= UInt64(bid_Tento9) {
        var L1_Xhi_64 = ((X>>28)*bid_Inv_Tento9) >> 33
        var L1_Xlo_64 = X - L1_Xhi_64 * UInt64(bid_Tento9)
        if L1_Xlo_64 >= UInt64(bid_Tento9) {
            L1_Xlo_64-=UInt64(bid_Tento9); L1_Xhi_64+=1
        }
        let L1_X_hi=UInt32(L1_Xhi_64)
        let L1_X_lo=UInt32(L1_Xlo_64)
        if L1_X_hi >= bid_Tento6 {
            __L0_Split_MiDi_3(L1_X_hi, &ptr)
            __L0_Split_MiDi_3(L1_X_lo, &ptr)
        } else if L1_X_hi >= bid_Tento3 {
            __L0_Split_MiDi_2(L1_X_hi, &ptr)
            __L0_Split_MiDi_3(L1_X_lo, &ptr)
        }
        else {
            ptr.append(L1_X_hi)
            __L0_Split_MiDi_3(L1_X_lo, &ptr)
        }
    } else {
        let L1_X_lo = UInt32(X)
        if L1_X_lo >= bid_Tento6 {
            __L0_Split_MiDi_3(L1_X_lo, &ptr)
        } else if L1_X_lo >= bid_Tento3 {
            __L0_Split_MiDi_2(L1_X_lo, &ptr)
        } else {
            ptr.append(L1_X_lo)
        }
    }
}

func __L1_Split_MiDi_6( _ X:UInt64, _ ptr: inout [UInt32]) {
    //BID_UINT32 L1_X_hi, L1_X_lo;
    //BID_UINT64 L1_Xhi_64, L1_Xlo_64;
    var L1_Xhi_64 = ((X>>28)*bid_Inv_Tento9) >> 33
    var L1_Xlo_64 = X - L1_Xhi_64*UInt64(bid_Tento9)
    if L1_Xlo_64 >= UInt64(bid_Tento9) {
        L1_Xlo_64-=UInt64(bid_Tento9); L1_Xhi_64+=1
    }
    let L1_X_hi=UInt32(L1_Xhi_64); let L1_X_lo=UInt32(L1_Xlo_64)
    __L0_Split_MiDi_3(L1_X_hi, &ptr)
    __L0_Split_MiDi_3(L1_X_lo, &ptr)
}

func __L0_Normalize_10to18(_ X_hi:inout UInt64, _ X_lo:inout UInt64) {
    let L0_tmp = X_lo + bid_Twoto60_m_10to18
    if L0_tmp & bid_Twoto60 != 0 {
        X_hi=X_hi+1; X_lo=(L0_tmp<<4)>>4
    }
}

/*********************************************************************
 *
 *      Compare Macros
 *
 *********************************************************************/
// greater than
//  return 0 if A<=B
//  non-zero if A>B
func __unsigned_compare_gt_128(_ A:UInt128, _ B:UInt128) -> Bool {
    (A.hi>B.hi) || ((A.hi==B.hi) && (A.lo>B.lo))
}

// Unpack decimal floating-point number x into sign,exponent,coefficient
// In special cases, call the macros provided
// Coefficient is normalized in the binary sense with postcorrection k,
// so that x = 10^e * c / 2^k and the range of c is:
//
// 2^23 <= c < 2^24   (decimal32)
// 2^53 <= c < 2^54   (decimal64)
// 2^112 <= c < 2^113 (decimal128)
@inlinable func unpack_bid32(_ x:UInt32, _ s: inout Int, _ e: inout Int, _ k: inout Int, _ c: inout UInt64, _ status: inout Status) -> Double? {
    s = Int(x >> 31)
    if (x & (UInt32(3)<<29)) == (UInt32(3)<<29) {
        if ((x & (UInt32(0xF)<<27)) == (UInt32(0xF)<<27)) {
            if ((x & (UInt32(0x1F<<26))) != (UInt32(0x1F)<<26)) { return return_double_inf(s) }
            if ((x & (UInt32(1)<<25)) != 0) { status.insert(.invalidOperation) }
            return return_double_nan(s, ((x & 0xFFFFF) > 999999) ? 0 : UInt64(x) << 44, 0)
        }
        e = Int((x >> 21) & ((UInt32(1)<<8)-1)) - 101
        c = UInt64((UInt32(1)<<23) + (x & ((UInt32(1)<<21)-1)))
        if (UInt(c) > 9999999) { return return_double_zero(s) }
        k = 0
    } else {
        e = Int((x >> 23) & ((UInt32(1)<<8)-1)) - 101
        c = UInt64(x) & (UInt64(1)<<23 - 1)
        if c == 0 { return return_double_zero(s) }
        k = clz32(UInt32(c)) - 8
        c = c << k
    }
    return nil
}

func unpack_bid64(_ x:UInt64, _ s: inout Int, _ e: inout Int, _ k: inout Int, _ c: inout UInt64, _ status: inout Status) -> Double? {
    s = Int(x >> 63)
    if ((x & (UInt64(3)<<61)) == (UInt64(3)<<61)) {
        if ((x & (UInt64(0xF)<<59)) == (UInt64(0xF)<<59)) {
            if ((x & (UInt64(0x1F)<<58)) != (UInt64(0x1F)<<58)) { return return_double_inf(s) }
            if ((x & (UInt64(1)<<57)) != 0) { status.insert(.invalidOperation) }
            return return_double_nan(s,(((x & 0x3FFFFFFFFFFFF) > 999999999999999) ? 0 : (UInt64(x) << 14)), 0)
        }
        e = Int((x >> 51) & ((UInt64(1)<<10)-1)) - 398
        c = (UInt64(1)<<53) + (x & ((UInt64(1)<<51)-1))
        if c > 9999999999999999 { return return_double_zero(s) }
        k = 0
    } else {
        e = Int((x >> 53) & ((UInt64(1)<<10)-1)) - 398
        c = x & ((UInt64(1)<<53)-1)
        if c == 0 { return return_double_zero(s) }
        k = clz64(c) - 10
        c = c << k
    }
    return nil
}

func unpack_bid128(_ x:UInt128, _ s: inout Int, _ e: inout Int, _ k: inout Int, _ c: inout UInt128, _ status: inout Status) -> Double? {
    s = Int(x.hi >> 63)
    if ((x.hi & (UInt64(3)<<61)) == (UInt64(3)<<61)) {
        if ((x.hi & (UInt64(0xF)<<59)) == (UInt64(0xF)<<59)) {
            if ((x.hi & (UInt64(0x1F)<<58)) != (UInt64(0x1F)<<58)) { return return_double_inf(s) }
            if ((x.hi & (UInt64(1)<<57)) != 0) {
                status.insert(.invalidOperation)
            }
            if lt128(54210108624275,4089650035136921599, x.hi & 0x3FFFFFFFFFFF, x.lo) {
                return return_double_nan(s,0,0)
            }
            return return_double_nan(s, x.hi << 18 + x.lo >> 46, x.lo << 18)
        }
        return return_double_zero(s)
    } else {
        e = Int((x.hi >> 49) & ((UInt64(1)<<14)-1)) - 6176;
        c.hi = x.hi & ((UInt64(1)<<49)-1)
        c.lo = x.lo
        if lt128(542101086242752,4003012203950112767,c.hi,c.lo) { c.hi = 0; c.lo = 0 }
        if (c.hi == 0) && (c.lo == 0) { return return_double_zero(s) }
        k = clz128_nz(c.hi,c.lo) - 15
        c = sll128(c.hi, c.lo, k)
        return nil
    }
}


func unpack_binary64(_ x:Double, _ s: inout Int, _ e: inout Int, _ c: inout UInt64, _ t: inout Int, _ status: inout Status) -> UInt64? {
    let expMask = 1<<11 - 1
    e = Int(x.bitPattern >> 52) & expMask
    c = x.significandBitPattern
    s = x.sign == .minus ? 1 : 0
    if e == 0 {
        if c == 0 { return return_bid64_zero(s) } // number = 0
        
        // denormalized number
        let l = clz64(c) - (64 - 53)
        c = c << l
        e = -(l + 1074)
        t = 0
        status.insert(.subnormal)
    } else if e == expMask {
        if c == 0 { return return_bid64_inf(s) } // number = infinity
        status.insert(.invalidOperation)
        return return_bid64_nan(s, c << 13, 0)
    } else {
        c |= 1 << 52  // set upper bit
        e -= 1075
        t = ctz64(c)
    }
    return nil
}

func return_bid32_max(_ s:Int) -> UInt32 { return_bid32(s,Decimal32.MAX_EXPON,Decimal32.MAX_NUMBER) }
func return_bid32_zero(_ s:Int) -> UInt32 { return_bid32(s,Decimal32.EXPONENT_BIAS,0) }
@inlinable func return_bid32_inf(_ s:Int) -> UInt32 { return_bid32(s,0xF<<4,0) }
@inlinable func return_bid32_nan(_ s:Int, _ c_hi:UInt64, _ c_lo:UInt64) -> UInt32 {
    return_bid32(s, 0x1F<<3, c_hi>>44 > 999_999 ? 0 : Int(c_hi>>44))
}

func return_bid64_max(_ s:Int) -> UInt64 { return_bid64(s,Decimal64.MAX_EXPON,Int(Decimal64.MAX_NUMBER)) }
func return_bid64_zero(_ s:Int) -> UInt64 { return_bid64(s,Decimal64.EXPONENT_BIAS,0) }
@inlinable func return_bid64_inf(_ s:Int) -> UInt64 { return_bid64(s,0xF<<6,0) }
@inlinable func return_bid64_nan(_ s:Int, _ c_hi:UInt64, _ c_lo:UInt64) -> UInt64 {
  return_bid64(s, 0x1F<<5, (((c_hi>>14) > 999_999_999_999_999) ? 0 : Int(c_hi>>14)))
}

func return_bid128_max(_ s:Int) -> UInt128 {
    return_bid128(s,Decimal128.MAX_EXPON,542101086242752,4003012203950112767)
}
func return_bid128_zero(_ s:Int) -> UInt128 { return_bid128(s,Decimal128.EXPONENT_BIAS,0,0) }
func return_bid128_inf(_ s:Int) -> UInt128 { return_bid128(s,0xF<<10,0,0) }
func return_bid128_nan(_ s:Int, _ c_hi:UInt64, _ c_lo:UInt64) -> UInt128 {
    if lt128(54210108624275,4089650035136921599, (c_hi>>18),((c_lo>>18)+(c_hi<<46))) {
        return return_bid128(s,0x1F<<9,0,0)
    } else {
        return return_bid128(s,0x1F<<9,c_hi>>18,(c_lo>>18)+(c_hi<<46))
    }
}

@inlinable func return_double_max(_ s:Int) -> Double { return_double(s,2046,(1<<52)-1) }
@inlinable func return_double_zero(_ s:Int) -> Double { return_double(s, 0, 0) }
@inlinable func return_double_inf(_ s:Int) -> Double { return_double(s, 2047, 0) }
@inlinable func return_double_nan(_ s:Int, _ c_hi:UInt64, _ c_lo:UInt64) -> Double {
    return_double(s, 2047, (c_hi>>13)+(UInt64(1)<<51))
}
func return_double_ovf(_ s:Int, _ rnd_mode:Rounding) -> Double {
    if (rnd_mode == BID_ROUNDING_TO_ZERO) || (rnd_mode == ((s != 0) ? BID_ROUNDING_UP : BID_ROUNDING_DOWN)) {
        return return_double_max(s)
    } else {
        return return_double_inf(s)
    }
}

@inlinable func return_double(_ s:Int, _ e:Int, _ c:UInt64) -> Double {
    let x = (UInt64(s) << 63) + (UInt64(e) << 52) + c
    return Double(bitPattern: x)
}

func return_bid32_ovf(_ s:Int) -> UInt32 {
    let rnd_mode = Decimal32.rounding
    if ((rnd_mode == BID_ROUNDING_TO_ZERO) || (rnd_mode==(s != 0 ? BID_ROUNDING_UP : BID_ROUNDING_DOWN))) {
        return return_bid32_max(s)
    } else {
        return return_bid32_inf(s)
    }
}

func return_bid128(_ s:Int, _ e:Int, _ c_hi:UInt64, _ c_lo:UInt64) -> UInt128 {
    var x_out = UInt128()
    x_out.lo = c_lo
    x_out.hi = (UInt64(s) << 63) + (UInt64(e) << 49) + c_hi
    return x_out
}

@inlinable func return_bid64(_ s:Int, _ e:Int, _ c:Int) -> UInt64 {
    if UInt64(c) < (UInt64(1)<<53) {
        return (UInt64(s) << 63) + (UInt64(e) << 53) + UInt64(c)
    } else {
        return (UInt64(s) << 63) + UInt64((0x3<<61) - (1<<53)) + (UInt64(e) << 51) + UInt64(c)
    }
}

@inlinable func return_bid32(_ s:Int, _ e:Int, _ c:Int) -> UInt32 {
    if UInt32(c) < UInt32(1)<<23 {
        return (UInt32(s) << 31) + (UInt32(e) << 23) + UInt32(c)
    } else {
        return (UInt32(s) << 31) + UInt32((0x3<<29) - (UInt32(1)<<23)) + (UInt32(e) << 21) + UInt32(c)
    }
}

// Shift 2-part 2^64 * hi + lo left by "c" bits
// The "short" form requires a shift 0 < c < 64 and will be faster
// Note that shifts of 64 can't be relied on as ANSI

func sll128_short(_ hi:UInt64, _ lo:UInt64, _ c:Int) -> UInt128 {
    UInt128(w: [lo << c, (hi << c) + (lo>>(64-c))])
}

func sll128(_ hi:UInt64, _ lo:UInt64, _ c:Int) -> UInt128 {
    if c == 0 { return UInt128(w: [lo, hi]) }
    if c >= 64 { return UInt128(w: [0, lo << (c - 64)]) }
    else { return sll128_short(hi, lo, c) }
}

func __shl_128_long(_ Q:inout UInt128, _ A:UInt128, _ k:Int) {
    if k<64 {
        Q.hi  = A.hi << k;
        Q.hi |= A.lo >> (64-k);
        Q.lo  = A.lo << k;
    } else {
        Q.hi = A.lo<<((k)-64);
        Q.lo = 0;
    }
}

func __shr_128_long(_ Q:inout UInt128, _ A:UInt128, _ k:Int) {
    if k<64 {
        Q.lo  = A.lo >> k;
        Q.lo |= A.hi << (64-k);
        Q.hi  = A.hi >> k;
    } else {
        Q.lo = A.hi>>(k-64);
        Q.hi = 0;
    }
}

// Shift 4-part 2^196 * x3 + 2^128 * x2 + 2^64 * x1 + x0
// right by "c" bits (must have c < 64)
func srl256_short(_ x3:UInt64, _ x2:UInt64, _ x1:UInt64, _ x0:UInt64, _ c:Int) -> UInt256 {
    let _x0 = (x1 << (64 - c)) + (x0 >> c)
    let _x1 = (x2 << (64 - c)) + (x1 >> c)
    let _x2 = (x3 << (64 - c)) + (x2 >> c)
    let _x3 = x3 >> c
    return UInt256(w: [_x0, _x1, _x2, _x3])
}

// Shift 2-part 2^64 * hi + lo right by "c" bits
// The "short" form requires a shift 0 < c < 64 and will be faster
// Note that shifts of 64 can't be relied on as ANSI
func srl128_short(_ hi:UInt64, _ lo:UInt64, _ c:Int) -> UInt128 {
    UInt128(w: [(hi << (64 - c)) + (lo >> c), hi >> c])
}

func __shr_128(_ Q: inout UInt128, _ A: inout UInt128, _ k:Int) {
     Q.lo  = A.lo >> k;
     Q.lo |= A.hi << (64-k);
     Q.hi  = A.hi >> k;
}

func srl128(_ hi:UInt64, _ lo:UInt64, _ c:Int) -> UInt128 {
    if c == 0 { return UInt128(w: [lo, hi]) }
    if c >= 64 { return UInt128(w: [hi >> (c - 64), 0]) }
    else { return srl128_short(hi, lo, c) }
}

func srl384_short(_ x5: UInt64, _ x4: UInt64, _ x3:UInt64, _ x2:UInt64, _ x1:UInt64, _ x0:UInt64, _ c:Int) -> UInt384 {
    let _x0 = (x1 << (64 - c)) + (x0 >> c)
    let _x1 = (x2 << (64 - c)) + (x1 >> c)
    let _x2 = (x3 << (64 - c)) + (x2 >> c)
    let _x3 = (x4 << (64 - c)) + (x3 >> c)
    let _x4 = (x5 << (64 - c)) + (x4 >> c)
    let _x5 = x5 >> c
    return UInt384(w: [_x0, _x1, _x2, _x3, _x4, _x5])
}

// Compare "<" two 2-part unsigned integers
@inlinable func lt128(_ x_hi:UInt64, _ x_lo:UInt64, _ y_hi:UInt64, _ y_lo:UInt64) -> Bool {
  (((x_hi) < (y_hi)) || (((x_hi) == (y_hi)) && ((x_lo) < (y_lo))))
}

// Likewise "<="
@inlinable func le128(_ x_hi:UInt64, _ x_lo:UInt64, _ y_hi:UInt64, _ y_lo:UInt64) -> Bool {
  (((x_hi) < (y_hi)) || (((x_hi) == (y_hi)) && ((x_lo) <= (y_lo))))
}

func __unsigned_compare_ge_128(_ A:UInt128, _ B:UInt128) -> Bool {
    (A.hi>B.hi) || ((A.hi==B.hi) && (A.lo>=B.lo))
}

// Counting trailing zeros in an unsigned 64-bit word
@inlinable func ctz64(_ n:UInt64) -> Int { n.trailingZeroBitCount }

// Counting leading zeros in an unsigned 64-bit word
@inlinable func clz64(_ n:UInt64) -> Int { n.leadingZeroBitCount }

// Counting leading zeros in an unsigned 64-bit word
@inlinable func clz32(_ n:UInt32) -> Int { n.leadingZeroBitCount }

// Counting leading zeros in an unsigned 2-part 128-bit word
@inlinable func clz128(_ n_hi:UInt64, _ n_lo:UInt64) -> Int    { (n_hi == 0) ? 64 + clz64(n_lo) : clz64(n_hi) }
@inlinable func clz128_nz(_ n_hi:UInt64, _ n_lo:UInt64) -> Int { (n_hi == 0) ? 64 + clz64(n_lo) : clz64(n_hi) }

func __mul_64x256_to_320(_ P:inout UInt384, _ A:UInt64, _ B:UInt256) {
    var lP0=UInt128(), lP1=UInt128(), lP2=UInt128(), lP3=UInt128()
    var lC:UInt64=0
    __mul_64x64_to_128(&lP0, A, B.w[0]);
    __mul_64x64_to_128(&lP1, A, B.w[1]);
    __mul_64x64_to_128(&lP2, A, B.w[2]);
    __mul_64x64_to_128(&lP3, A, B.w[3]);
    P.w[0] = lP0.lo;
    __add_carry_out(&P.w[1],&lC,lP1.lo,lP0.hi);
    __add_carry_in_out(&P.w[2],&lC,lP2.lo,lP1.hi,lC);
    __add_carry_in_out(&P.w[3],&lC,lP3.lo,lP2.hi,lC);
    P.w[4] = lP3.hi + lC;
}

// 128x256->384 bit multiplication (missing from existing macros)
// I derived this by propagating (A).w[2] = 0 in __mul_192x256_to_448
func __mul_128x256_to_384(_  P: inout UInt384, _ A:UInt128, _ B:UInt256) {
    var P0=UInt384(),P1=UInt384()
    var CY:UInt64=0
    __mul_64x256_to_320(&P0, A.lo, B);
    __mul_64x256_to_320(&P1, A.hi, B);
    P.w[0] = P0.w[0];
    __add_carry_out(&P.w[1],&CY,P1.w[0],P0.w[1]);
    __add_carry_in_out(&P.w[2],&CY,P1.w[1],P0.w[2],CY);
    __add_carry_in_out(&P.w[3],&CY,P1.w[2],P0.w[3],CY);
    __add_carry_in_out(&P.w[4],&CY,P1.w[3],P0.w[4],CY);
    P.w[5] = P1.w[4] + CY;
}

func __mul_64x128_low(_ Ql:inout UInt128, _ A:UInt64, _ B:UInt128) {
    var ALBL = UInt128(), ALBH = UInt128(), QM2 = UInt128()
    __mul_64x64_to_128(&ALBH, A, B.hi)
    __mul_64x64_to_128(&ALBL, A, B.lo)
    Ql.lo = ALBL.lo
    __add_128_64(&QM2, ALBH, ALBL.hi)
    Ql.hi = QM2.lo
}

/*****************************************************
 *      Unsigned Multiply Macros
 *****************************************************/
// get full 64x64bit product
//
func __mul_64x64_to_128(_ P: inout UInt128, _ CX:UInt64, _ CY:UInt64) {
    let res = CX.multipliedFullWidth(by: CY)
    P.hi = res.high; P.lo = res.low
//BID_UINT64 CXH, CXL, CYH,CYL,PL,PH,PM,PM2;
//    CXH = (CX) >> 32;
//    CXL = (BID_UINT32)(CX);
//    CYH = (CY) >> 32;
//    CYL = (BID_UINT32)(CY);
//
//    PM = CXH*CYL;
//    PH = CXH*CYH;
//    PL = CXL*CYL;
//    PM2 = CXL*CYH;
//    PH += (PM>>32);
//    PM = (BID_UINT64)((BID_UINT32)PM)+PM2+(PL>>32);
//
//    (P).hi = PH + (PM>>32);
//    (P).lo = (PM<<32)+(BID_UINT32)PL;
}

// get full 64x64bit product
// Note:
// This macro is used for CX < 2^61, CY < 2^61
//
func __mul_64x64_to_128_fast(_ P: inout UInt128, _ CX:UInt64, _ CY:UInt64) {
    let res = CX.multipliedFullWidth(by: CY)
    P.hi = res.high; P.lo = res.low
//    CXH = (CX) >> 32;
//    CXL = (BID_UINT32)(CX);
//    CYH = (CY) >> 32;
//    CYL = (BID_UINT32)(CY);
//
//    PM = CXH*CYL;
//    PL = CXL*CYL;
//    PH = CXH*CYH;
//    PM += CXL*CYH;
//    PM += (PL>>32);
//
//    (P).hi = PH + (PM>>32);
//    (P).lo = (PM<<32)+(BID_UINT32)PL;
}

func __mul_64x128_full(_ Ph:inout UInt64, _ Ql: inout UInt128,  _ A:UInt64, _ B:UInt128) {
// BID_UINT128 ALBL, ALBH, QM2;
    var ALBL = UInt128(), ALBH = UInt128(), QM2 = UInt128()
    __mul_64x64_to_128(&ALBH, A, B.hi)
    __mul_64x64_to_128(&ALBL, A, B.lo)
                                                  
    Ql.lo = ALBL.lo
    __add_128_64(&QM2, ALBH, ALBL.hi)
    Ql.hi = QM2.lo
    Ph = QM2.hi
}

func __mul_128x128_full(_ Qh:inout UInt128, _ Ql:inout UInt128, _ A:UInt128, _ B:UInt128) {
    var ALBL = UInt128(), ALBH = UInt128(), AHBL = UInt128(), AHBH = UInt128()
                                                  
    __mul_64x64_to_128(&ALBH, A.lo, B.hi);
    __mul_64x64_to_128(&AHBL, B.lo, A.hi);
    __mul_64x64_to_128(&ALBL, A.lo, B.lo);
    __mul_64x64_to_128(&AHBH, A.hi, B.hi);
            
    var QM = UInt128(), QM2 = UInt128()
    __add_128_128(&QM, ALBH, AHBL);
    Ql.lo = ALBL.lo;
    __add_128_64(&QM2, QM, ALBL.hi);
    __add_128_64(&Qh, AHBH, QM2.hi);
    Ql.hi = QM2.lo;
}

func __mul_128x128_high(_ Q:inout UInt128, _ A:UInt128, _ B:UInt128) {
    var ALBL=UInt128(), ALBH=UInt128(), AHBL=UInt128(), AHBH=UInt128(), QM=UInt128(), QM2=UInt128()
    
    __mul_64x64_to_128(&ALBH, A.lo, B.hi)
    __mul_64x64_to_128(&AHBL, B.lo, A.hi)
    __mul_64x64_to_128(&ALBL, A.lo, B.lo)
    __mul_64x64_to_128(&AHBH, A.hi, B.hi)
    
    __add_128_128(&QM, ALBH, AHBL)
    __add_128_64(&QM2, QM, ALBL.hi)
    __add_128_64(&Q, AHBH, QM2.hi)
}

func __mul_128x128_low(_ Ql: inout UInt128, _ A:UInt128, _ B:UInt128) {
    var ALBL:UInt128 = UInt128(w: [0,0])
    __mul_64x64_to_128(&ALBL, A.lo, B.lo);
    let QM64 = B.lo*A.hi + A.lo*(B).hi;
                                                  
    Ql.lo = ALBL.lo;
    Ql.hi = QM64 + ALBL.hi;
}

func __mul_256x256_to_512(_ P: inout UInt512, _ A:UInt256, _ B:UInt256) {
    var P0=UInt384(), P1=UInt384(), P2=UInt384(), P3=UInt384(), CY=UInt64()
    __mul_64x256_to_320(&P0, A.w[0], B)
    __mul_64x256_to_320(&P1, A.w[1], B)
    __mul_64x256_to_320(&P2, A.w[2], B)
    __mul_64x256_to_320(&P3, A.w[3], B)
    P.w[0] = P0.w[0]
    __add_carry_out(&P.w[1],&CY,P1.w[0],P0.w[1])
    __add_carry_in_out(&P.w[2],&CY,P1.w[1],P0.w[2],CY)
    __add_carry_in_out(&P.w[3],&CY,P1.w[2],P0.w[3],CY)
    __add_carry_in_out(&P.w[4],&CY,P1.w[3],P0.w[4],CY)
    P.w[5] = P1.w[4] + CY
    __add_carry_out(&P.w[2],&CY,P2.w[0],(P).w[2])
    __add_carry_in_out(&P.w[3],&CY,P2.w[1],P.w[3],CY)
    __add_carry_in_out(&P.w[4],&CY,P2.w[2],P.w[4],CY)
    __add_carry_in_out(&P.w[5],&CY,P2.w[3],P.w[5],CY)
    P.w[6] = P2.w[4] + CY
    __add_carry_out(&P.w[3],&CY,P3.w[0],(P).w[3])
    __add_carry_in_out(&P.w[4],&CY,P3.w[1],P.w[4],CY)
    __add_carry_in_out(&P.w[5],&CY,P3.w[2],P.w[5],CY)
    __add_carry_in_out(&P.w[6],&CY,P3.w[3],P.w[6],CY)
    P.w[7] = P3.w[4] + CY
}

// Multiply a 64-bit number by 10, getting "carry" and "sum"

func __mul_10x64(_ sum:inout UInt64,_ carryout:inout UInt64, _ input:UInt64, _ carryin:UInt64) {
    var s3 = input + input >> 2
    carryout = (s3 < UInt64(input) ? 1 : 0)<<3 + (s3>>61)
    s3 = (s3<<3) + ((input&3)<<1)
    sum = s3 + carryin
    if (UInt64(sum) < s3) { carryout += 1 }
}

// Likewise a 384-bit number

func __mul_10x384_to_384(_ a5:UInt64, _ a4:UInt64, _ a3:UInt64, _ a2:UInt64, _ a1:UInt64, _ a0:UInt64) -> UInt384 {
    var p5=UInt64(), p4=UInt64(), p3=UInt64(), p2=UInt64(), p1=UInt64(), p0=UInt64()
    var c0=UInt64(), c1=UInt64(), c2=UInt64(), c3=UInt64(), c4=UInt64(), c5=UInt64()
    __mul_10x64(&p0,&c0,a0,0)
    __mul_10x64(&p1,&c1,a1,c0)
    __mul_10x64(&p2,&c2,a2,c1)
    __mul_10x64(&p3,&c3,a3,c2)
    __mul_10x64(&p4,&c4,a4,c3)
    __mul_10x64(&p5,&c5,a5,c4)
    return UInt384(w: [p0, p1, p2, p3, p4, p5])
}

func __mul_128x128_to_256(_ P256: inout UInt256, _ A:UInt128, _ B:UInt128) {
    var Qll = UInt128(), Qlh = UInt128()
    var Phl = UInt64(), Phh = UInt64(), CY1 = UInt64(), CY2 = UInt64()
    
    __mul_64x128_full(&Phl, &Qll, A.lo, B)
    __mul_64x128_full(&Phh, &Qlh, A.hi, B)
    P256.w[0] = Qll.lo
    __add_carry_out(&P256.w[1], &CY1, Qlh.lo, Qll.hi)
    __add_carry_in_out(&P256.w[2], &CY2, Qlh.hi, Phl, CY1)
    P256.w[3] = Phh + CY2
}

func __mul_128x64_to_128(_ Q128: inout UInt128, _ A64:UInt64, _ B128:UInt128) {
  let ALBH_L = A64 * B128.hi
  __mul_64x64_to_128MACH(&Q128, A64, B128.lo)
  Q128.hi += ALBH_L
}

func __scale128_x10(_ _TMP:UInt128) -> UInt128 {
    var _TMP2=UInt128(), _TMP8=UInt128()
    _TMP2 = sll128(_TMP.hi, _TMP.lo, 1)
    _TMP8 = sll128(_TMP.hi, _TMP.lo, 3)
    __add_128_128(&_TMP2, _TMP2, _TMP8)
    return _TMP2
}

func bid___div_128_by_128 (_ pCQ: inout UInt128, _ pCR: inout UInt128, _ CX0:UInt128, _ CY:UInt128) {
    if CX0.hi == 0 && CY.hi == 0 {
        pCQ.lo = CX0.lo / CY.lo
        pCQ.hi = 0
        pCR.hi = 0; pCR.lo = 0
        pCR.lo = CX0.lo - pCQ.lo * CY.lo
        return
    }
    
    var CX = CX0, Q = UInt64()
    
    // 2^64
    let t64 = Double(bitPattern: 0x43f0000000000000)
    var lx = Double(CX.hi) * t64 + Double(CX.lo)
    let ly = Double(CY.hi) * t64 + Double(CY.lo)
    var lq = lx / ly
    
    var CY36 = UInt128(), CQ = UInt128(), A2 = UInt128()
    CY36.hi = CY.lo >> (64 - 36);
    CY36.lo = CY.lo << 36;
    
    CQ.hi = 0; CQ.lo = 0;
    
    // Q >= 2^100 ?
    if (CY.hi == 0 && CY36.hi == 0 && (CX.hi >= CY36.lo)) {
        // then Q >= 2^100
        
        // 2^(-60)*CX/CY
        let d60 = Double(bitPattern: 0x3c30000000000000)
        lq *= d60
        Q = UInt64(lq - 4)
        
        // Q*CY
        __mul_64x64_to_128(&A2, Q, CY.lo);
        
        // A2 <<= 60
        A2.hi = (A2.hi << 60) | (A2.lo >> (64 - 60));
        A2.lo <<= 60;
        
        __sub_128_128(&CX, CX, A2);
        
        lx = Double(CX.hi) * t64 + Double(CX.lo)
        lq = lx / ly
        
        CQ.hi = Q >> (64 - 60);
        CQ.lo = Q << 60;
    }
    
    var CY51 = UInt128(), CQT = UInt128()
    CY51.hi = (CY.hi << 51) | (CY.lo >> (64 - 51));
    CY51.lo = CY.lo << 51;
    
    if (CY.hi < (UInt64(1) << (64 - 51)) && (__unsigned_compare_gt_128(CX, CY51))) {
        // Q > 2^51
        
        // 2^(-49)*CX/CY
        let d49 = Double(bitPattern: 0x3ce0000000000000)
        lq *= d49
        
        Q = UInt64(lq) - 1
        
        // Q*CY
        __mul_64x64_to_128(&A2, Q, CY.lo);
        A2.hi += Q * CY.hi;
        
        // A2 <<= 49
        A2.hi = (A2.hi << 49) | (A2.lo >> (64 - 49));
        A2.lo <<= 49;
        
        __sub_128_128(&CX, CX, A2);
        
        CQT.hi = Q >> (64 - 49);
        CQT.lo = Q << 49;
        __add_128_128(&CQ, CQ, CQT);
        
        lx = Double(CX.hi) * t64 + Double(CX.lo)
        lq = lx / ly
    }
    
    Q = UInt64(lq)
    
    __mul_64x64_to_128(&A2, Q, CY.lo);
    A2.hi += Q * CY.hi;
    
    __sub_128_128(&CX, CX, A2);
    if (Int(CX.hi) < 0) {
        Q-=1
        CX.lo += CY.lo;
        if (CX.lo < CY.lo) {
            CX.hi+=1
        }
        CX.hi += CY.hi;
        if (Int(CX.hi) < 0) {
            Q-=1
            CX.lo += CY.lo;
            if (CX.lo < CY.lo) {
                CX.hi+=1
            }
            CX.hi += CY.hi
        }
    } else if (__unsigned_compare_ge_128(CX, CY)) {
        Q+=1
        __sub_128_128(&CX, CX, CY)
    }
    
    __add_128_64(&CQ, CQ, Q);
    pCQ = CQ; pCR = CX
}

/*********************************************************************
 *
 *      Add/Subtract Macros
 *
 *********************************************************************/
// add 64-bit value to 128-bit
func __add_128_64(_ R128:inout UInt128, _ A128:UInt128, _ B64:UInt64) {
    var R64H = A128.hi
    R128.lo = B64 &+ A128.lo
    if R128.lo < B64 {
        R64H += 1
    }
    R128.hi = R64H
}

func __sub_128_128(_ R128:inout UInt128, _ A128:UInt128, _ B128:UInt128) {
    var Q128 = UInt128()
    Q128.hi = A128.hi - B128.hi
    Q128.lo = A128.lo &- B128.lo
    if A128.lo < B128.lo {
        Q128.hi -= 1
    }
    R128.hi = Q128.hi
    R128.lo = Q128.lo
}

// add 128-bit value to 128-bit
// assume no carry-out
func __add_128_128(_ R128:inout UInt128, _ A128:UInt128, _ B128:UInt128) {
    var Q128 = UInt128()
    Q128.hi = A128.hi + B128.hi
    Q128.lo = B128.lo &+ A128.lo
    if Q128.lo < B128.lo {
        Q128.hi += 1
    }
    R128 = Q128
}

@inlinable func __add_carry_out(_ S: inout UInt64, _ CY: inout UInt64, _ X:UInt64, _ Y:UInt64) {
    S = X &+ Y  // allow overflow
    CY = S < X ? 1 : 0
}

@inlinable func __sub_borrow_out(_ S: inout UInt64, _ CY: inout UInt64, _ X:UInt64, _ Y:UInt64) {
    S = X &- Y  // allow underflow
    CY = S > X ? 1 : 0
}

@inlinable func __add_carry_in_out(_ S: inout UInt64, _ CY: inout UInt64, _ X:UInt64, _ Y:UInt64, _ CI: UInt64) {
    let X1 = X + CI
    S = X1 &+ Y
    CY = ((S<X1) || (X1<CI)) ? 1 : 0
}

// 64x64-bit product
func __mul_64x64_to_128MACH(_ P128: inout UInt128, _ CX:UInt64, _ CY:UInt64)  {
    let res = CX.multipliedFullWidth(by: CY)
    P128.hi = res.high; P128.lo = res.low
//  BID_UINT64 CXH,CXL,CYH,CYL,PL,PH,PM,PM2;
//  CXH = (CX64) >> 32;
//  CXL = (BID_UINT32)(CX64);
//  CYH = (CY64) >> 32;
//  CYL = (BID_UINT32)(CY64);
//  PM = CXH*CYL;
//  PH = CXH*CYH;
//  PL = CXL*CYL;
//  PM2 = CXL*CYH;
//  PH += (PM>>32);
//  PM = (BID_UINT64)((BID_UINT32)PM)+PM2+(PL>>32);
//  (P128).hi = PH + (PM>>32);
//  (P128).lo = (PM<<32)+(BID_UINT32)PL;
}

/// Following is shamelessly borrowed from:
/*
    Copyright 2020 Chip Jarred

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
*/

/*
 The operators in this file implement the tuple operations for the 2-digit
 arithmetic needed for Knuth's Algorithm D, and *only* those operations.
 There is no attempt to be a complete set. They are meant to make the code that
 uses them more readable than if the operations they express were written out
 directly.
 */

infix operator /% : MultiplicationPrecedence

typealias Digit = UInt64
typealias TwoDigits = (high: Digit, low: Digit)

// -------------------------------------
internal extension FixedWidthInteger {
    // -------------------------------------
    /// Fast creation of an integer from a Bool
    init(_ source: Bool) {
        assert(unsafeBitCast(source, to: UInt8.self) & 0xfe == 0)
        self.init(unsafeBitCast(source, to: UInt8.self))
    }
}

// -------------------------------------
/// Divide a tuple of digits by 1 digit obtaining both quotient and remainder
internal func /% (left: TwoDigits, right: Digit) -> (quotient: TwoDigits, remainder: TwoDigits) {
    var r: Digit
    let q: TwoDigits
    (q.high, r) = left.high.quotientAndRemainder(dividingBy: right)
    (q.low, r) = right.dividingFullWidth((high: r, low: left.low))
    return (q, (high: 0, low: r))
}

func addReportingCarry(_ x: inout Digit, _ y: Digit) -> Digit {
    let c: Bool
    (x, c) = x.addingReportingOverflow(y)
    return Digit(c)
}

internal func * (left: TwoDigits, right: Digit) -> TwoDigits {
    var product = left.low.multipliedFullWidth(by: right)
    let productHigh = left.high.multipliedFullWidth(by: right)
    assert(productHigh.high == 0, "multiplication overflow")
    let c = addReportingCarry(&product.high, productHigh.low)
    assert(c == 0, "multiplication overflow")
    return product
}

internal func > (left: TwoDigits, right: TwoDigits) -> UInt8 {
    return UInt8(left.high > right.high) |
            (UInt8(left.high == right.high) & UInt8(left.low > right.low))
}

// -------------------------------------
/// Add a digit to a tuple's low part, carrying to the high part.
func += (left: inout TwoDigits, right: Digit) {
    left.high &+= addReportingCarry(&left.low, right)
}

// -------------------------------------
/// Add one tuple to another tuple
func += (left: inout TwoDigits, right: TwoDigits) {
    left.high &+= addReportingCarry(&left.low, right.low)
    left.high &+= right.high
}

func subtractReportingBorrow(_ x: inout Digit, _ y: Digit) -> Digit {
    let b: Bool
    (x, b) = x.subtractingReportingOverflow(y)
    return Digit(b)
}

// -------------------------------------
/// Subtract a digit from a tuple, borrowing the high part if necessary
func -= (left: inout TwoDigits, right: Digit) {
    left.high &-= subtractReportingBorrow(&left.low, right)
}
