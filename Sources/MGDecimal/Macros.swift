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
struct UInt128 { var w = [UInt64](repeating: 0, count: 2) }

func BID_SWAP128(_ x: inout UInt128) {
    let one = 1
    if one == one.bigEndian {
        // swap 128 bit
        let sw = x.w[1]
        x.w[1] = x.w[0]
        x.w[0] = sw
    }
}

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

func __L0_Normalize_10to18(_ X_hi:inout UInt64, _ X_lo:inout UInt64) {
    let L0_tmp = X_lo + bid_Twoto60_m_10to18
    if L0_tmp & bid_Twoto60 != 0 {
        X_hi=X_hi+1; X_lo=(L0_tmp<<4)>>4
    }
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
    s = Int(x) >> 31
    if ((x & (3<<29)) == (3<<29)) {
        if ((x & (0xF<<27)) == (0xF<<27)) {
            if ((x & (0x1F<<26)) != (0x1F<<26)) { return return_double_inf(s) }
            if ((x & (1<<25)) != 0) { status.insert(.invalidOperation) }
            return return_double_nan(s, UInt64(((x & 0xFFFFF) > 999999) ? 0 : Int(x) << 44), 0)
        }
        e = Int((x >> 21) & ((1<<8)-1)) - 101
        c = UInt64((1<<23) + (x & ((1<<21)-1)))
        if (UInt(c) > 9999999) { return return_double_zero(s) }
        k = 0
    } else {
        e = Int((x >> 23) & ((1<<8)-1)) - 101
        c = UInt64(x) & (UInt64(1)<<23 - 1)
        if c == 0 { return return_double_zero(s) }
        k = clz32(UInt32(c)) - 8
        c = c << k
    }
    return nil
}

@inlinable func unpack_binary64(_ x:Double, _ s: inout Int, _ e: inout Int, _ c: inout UInt64, _ t: inout Int, _ status: inout Status) -> UInt64? {
    let expMask = 1<<11 - 1
    e = Int(x.bitPattern >> 52) & expMask
    c = x.significandBitPattern
    s = x.sign == .minus ? 1 : 0
    if e == 0 {
        if c == 0 { return UInt64(return_bid32_zero(s)) } // number = 0
        
        // denormalized number
        let l = clz64(c) - (64 - 53)
        c = c << l
        e = -Int(l + 1074)
        t = 0
        status.insert(.subnormal)
    } else if e == expMask {
        if c == 0 { return UInt64(return_bid32_inf(s)) } // number = infinity
        status.insert(.invalidOperation)
        return UInt64(return_bid32_nan(s, c << 13, 0))
    } else {
        c |= 1 << 52  // set upper bit
        e -= 1075
        t = ctz64(c)
    }
    return nil
}

@inlinable func return_bid32_max(_ s:Int) -> UInt32 { return_bid32(s,191,9_999_999) }
@inlinable func return_bid32_zero(_ s:Int) -> UInt32 { return_bid32(s,101,0) }
@inlinable func return_bid32_inf(_ s:Int) -> UInt32 { return_bid32(s,(0xF<<4),0) }
@inlinable func return_bid32_nan(_ s:Int, _ c_hi:UInt64, _ c_lo:UInt64) -> UInt32 {
    return_bid32(s, 0x1F<<3, c_hi>>44 > 999_999 ? 0 : Int(c_hi>>44))
}

@inlinable func return_bid64_zero(_ s:Int) -> UInt64 { return_bid64(s,398,0) }
@inlinable func return_bid64_inf(_ s:Int) -> UInt64 { return_bid64(s,(0xF<<6),0) }
@inlinable func return_bid64_nan(_ s:Int, _ c_hi:UInt64, _ c_lo:UInt64) -> UInt64 {
  return_bid64(s, 0x1F<<5, (((c_hi>>14) > 999999999999999) ? 0 : Int(c_hi>>14)))
}

@inlinable func return_double_zero(_ s:Int) -> Double { return_double(s, 0, 0) }
@inlinable func return_double_inf(_ s:Int) -> Double { return_double(s, 2047, 0) }
@inlinable func return_double_nan(_ s:Int, _ c_hi:UInt64, _ c_lo:UInt64) -> Double {
    return_double(s, 2047, (c_hi>>13)+(UInt64(1)<<51))
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

@inlinable func return_bid64(_ s:Int, _ e:Int, _ c:Int) -> UInt64 {
    if UInt64(c) < (1<<53) {
        return (UInt64(s) << 63) + (UInt64(e) << 53) + UInt64(c)
    } else {
        return (UInt64(s) << 63) + UInt64((0x3<<61) - (1<<53)) + (UInt64(e) << 51) + UInt64(c)
    }
}

@inlinable func return_bid32(_ s:Int, _ e:Int, _ c:Int) -> UInt32 {
    if UInt32(c) < (1<<23) {
        return (UInt32(s) << 31) + (UInt32(e) << 23) + UInt32(c)
    } else {
        return (UInt32(s) << 31) + UInt32((0x3<<29) - (1<<23)) + (UInt32(e) << 21) + UInt32(c)
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
        Q.w[1]  = A.w[1] << k;
        Q.w[1] |= A.w[0] >> (64-k);
        Q.w[0]  = A.w[0] << k;
    } else {
        Q.w[1] = A.w[0]<<((k)-64);
        Q.w[0] = 0;
    }
}

func __shr_128_long(_ Q:inout UInt128, _ A:UInt128, _ k:Int) {
    if k<64 {
        Q.w[0]  = A.w[0] >> k;
        Q.w[0] |= A.w[1] << (64-k);
        Q.w[1]  = A.w[1] >> k;
    } else {
        Q.w[0] = A.w[1]>>(k-64);
        Q.w[1] = 0;
    }
}

// Shift 2-part 2^64 * hi + lo right by "c" bits
// The "short" form requires a shift 0 < c < 64 and will be faster
// Note that shifts of 64 can't be relied on as ANSI
func srl128_short(_ hi:UInt64, _ lo:UInt64, _ c:Int) -> UInt128 {
    UInt128(w: [(hi << (64 - c)) + (lo >> c), hi >> c])
}

func __shr_128(_ Q: inout UInt128, _ A: inout UInt128, _ k:Int) {
     Q.w[0]  = A.w[0] >> k;
     Q.w[0] |= A.w[1] << (64-k);
     Q.w[1]  = A.w[1] >> k;
}

func srl128(_ hi:UInt64, _ lo:UInt64, _ c:Int) -> UInt128 {
    if c == 0 { return UInt128(w: [lo, hi]) }
    if c >= 64 { return UInt128(w: [hi >> (c - 64), 0]) }
    else { return srl128_short(hi, lo, c) }
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
    (A.w[1]>B.w[1]) || ((A.w[1]==B.w[1]) && (A.w[0]>=B.w[0]))
}

// Counting trailing zeros in an unsigned 64-bit word
@inlinable func ctz64(_ n:UInt64) -> Int { n.trailingZeroBitCount }

// Counting leading zeros in an unsigned 64-bit word
@inlinable func clz64(_ n:UInt64) -> Int { n.leadingZeroBitCount }

// Counting leading zeros in an unsigned 64-bit word
@inlinable func clz32(_ n:UInt32) -> Int { n.leadingZeroBitCount }

func __mul_64x256_to_320(_ P:inout UInt384, _ A:UInt64, _ B:UInt256) {
    var lP0=UInt128(), lP1=UInt128(), lP2=UInt128(), lP3=UInt128()
    var lC:UInt64=0
    __mul_64x64_to_128(&lP0, A, B.w[0]);
    __mul_64x64_to_128(&lP1, A, B.w[1]);
    __mul_64x64_to_128(&lP2, A, B.w[2]);
    __mul_64x64_to_128(&lP3, A, B.w[3]);
    P.w[0] = lP0.w[0];
    __add_carry_out(&P.w[1],&lC,lP1.w[0],lP0.w[1]);
    __add_carry_in_out(&P.w[2],&lC,lP2.w[0],lP1.w[1],lC);
    __add_carry_in_out(&P.w[3],&lC,lP3.w[0],lP2.w[1],lC);
    P.w[4] = lP3.w[1] + lC;
}

// 128x256->384 bit multiplication (missing from existing macros)
// I derived this by propagating (A).w[2] = 0 in __mul_192x256_to_448
func __mul_128x256_to_384(_  P: inout UInt384, _ A:UInt128, _ B:UInt256) {
    var P0=UInt384(),P1=UInt384()
    var CY:UInt64=0
    __mul_64x256_to_320(&P0, A.w[0], B);
    __mul_64x256_to_320(&P1, A.w[1], B);
    P.w[0] = P0.w[0];
    __add_carry_out(&P.w[1],&CY,P1.w[0],P0.w[1]);
    __add_carry_in_out(&P.w[2],&CY,P1.w[1],P0.w[2],CY);
    __add_carry_in_out(&P.w[3],&CY,P1.w[2],P0.w[3],CY);
    __add_carry_in_out(&P.w[4],&CY,P1.w[3],P0.w[4],CY);
    P.w[5] = P1.w[4] + CY;
}

func __mul_64x128_low(_ Ql:inout UInt128, _ A:UInt64, _ B:UInt128) {
    var ALBL = UInt128(), ALBH = UInt128(), QM2 = UInt128()
    __mul_64x64_to_128(&ALBH, A, B.w[1])
    __mul_64x64_to_128(&ALBL, A, B.w[0])
    Ql.w[0] = ALBL.w[0]
    __add_128_64(&QM2, ALBH, ALBL.w[1])
    Ql.w[1] = QM2.w[0]
}

/*****************************************************
 *      Unsigned Multiply Macros
 *****************************************************/
// get full 64x64bit product
//
func __mul_64x64_to_128(_ P: inout UInt128, _ CX:UInt64, _ CY:UInt64) {
    let res = CX.multipliedFullWidth(by: CY)
    P.w[1] = res.high; P.w[0] = res.low
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
//    (P).w[1] = PH + (PM>>32);
//    (P).w[0] = (PM<<32)+(BID_UINT32)PL;
}

func __mul_64x128_full(_ Ph:inout UInt64, _ Ql: inout UInt128,  _ A:UInt64, _ B:UInt128) {
// BID_UINT128 ALBL, ALBH, QM2;
    var ALBL = UInt128(), ALBH = UInt128(), QM2 = UInt128()
    __mul_64x64_to_128(&ALBH, A, B.w[1])
    __mul_64x64_to_128(&ALBL, A, B.w[0])
                                                  
    Ql.w[0] = ALBL.w[0]
    __add_128_64(&QM2, ALBH, ALBL.w[1])
    Ql.w[1] = QM2.w[0]
    Ph = QM2.w[1]
}

func __mul_128x128_full(_ Qh:inout UInt128, _ Ql:inout UInt128, _ A:UInt128, _ B:UInt128) {
    var ALBL = UInt128(), ALBH = UInt128(), AHBL = UInt128(), AHBH = UInt128()
                                                  
    __mul_64x64_to_128(&ALBH, A.w[0], B.w[1]);
    __mul_64x64_to_128(&AHBL, B.w[0], A.w[1]);
    __mul_64x64_to_128(&ALBL, A.w[0], B.w[0]);
    __mul_64x64_to_128(&AHBH, A.w[1], B.w[1]);
            
    var QM = UInt128(), QM2 = UInt128()
    __add_128_128(&QM, ALBH, AHBL);
    Ql.w[0] = ALBL.w[0];
    __add_128_64(&QM2, QM, ALBL.w[1]);
    __add_128_64(&Qh, AHBH, QM2.w[1]);
    Ql.w[1] = QM2.w[0];
}

func __mul_128x128_low(_ Ql: inout UInt128, _ A:UInt128, _ B:UInt128) {
    var ALBL:UInt128 = UInt128(w: [0,0])
    __mul_64x64_to_128(&ALBL, A.w[0], B.w[0]);
    let QM64 = B.w[0]*A.w[1] + A.w[0]*(B).w[1];
                                                  
    Ql.w[0] = ALBL.w[0];
    Ql.w[1] = QM64 + ALBL.w[1];
}

/*********************************************************************
 *
 *      Add/Subtract Macros
 *
 *********************************************************************/
// add 64-bit value to 128-bit
func __add_128_64(_ R128:inout UInt128, _ A128:UInt128, _ B64:UInt64) {
    var R64H = A128.w[1]
    R128.w[0] = B64 + A128.w[0]
    if R128.w[0] < B64 {
        R64H += 1
    }
    R128.w[1] = R64H
}

// add 128-bit value to 128-bit
// assume no carry-out
func __add_128_128(_ R128:inout UInt128, _ A128:UInt128, _ B128:UInt128) {
    var Q128 = UInt128()
    Q128.w[1] = A128.w[1] + B128.w[1]
    Q128.w[0] = B128.w[0] + A128.w[0]
    if Q128.w[0] < B128.w[0] {
        Q128.w[1] += 1
    }
    R128 = Q128
}

@inlinable func __add_carry_out(_ S: inout UInt64, _ CY: inout UInt64, _ X:UInt64, _ Y:UInt64) {
    let X1=X
    S = X &+ Y
    CY = S<X1 ? 1 : 0
}

@inlinable func __add_carry_in_out(_ S: inout UInt64, _ CY: inout UInt64, _ X:UInt64, _ Y:UInt64, _ CI: UInt64) {
    let X1 = X + CI;
    S = X1 &+ Y;
    CY = ((S<X1) || (X1<CI)) ? 1 : 0;
}

// 64x64-bit product
func __mul_64x64_to_128MACH(_ P128: inout UInt128, _ CX:UInt64, _ CY:UInt64)  {
    let res = CX.multipliedFullWidth(by: CY)
    P128.w[1] = res.high; P128.w[0] = res.low
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
//  (P128).w[1] = PH + (PM>>32);
//  (P128).w[0] = (PM<<32)+(BID_UINT32)PL;
}
