////
////  Common.swift
////
////
////  Created by Mike Griebling on 2022-03-04.
////
//
import Foundation

///* ------------------------------------------------------------------ */
///* Combination field lookup tables (uInts to save measurable work)    */
///*                                                                    */
///*   DECCOMBEXP  - 2 most-significant-bits of exponent (00, 01, or    */
///*                 10), shifted left for format, or Inf/NaN           */
///*   DECCOMBWEXP - The same, for the next-wider format (unless QUAD)  */
///*   DECCOMBMSD  - 4-bit most-significant-digit                       */
///*                 [0 if the index is a special (Infinity or NaN)]    */
///*   DECCOMBFROM - 5-bit combination field from EXP top bits and MSD  */
///*                 (placed in uInt so no shift is needed)             */
///*                                                                    */
///* DECCOMBEXP, DECCOMBWEXP, and DECCOMBMSD are indexed by the sign    */
///*   and 5-bit combination field (0-63, the second half of the table  */
///*   identical to the first half)                                     */
///* DECCOMBFROM is indexed by expTopTwoBits*16 + msd                   */
///*                                                                    */
///* DECCOMBMSD and DECCOMBFROM are not format-dependent and so are     */
///* only included once, when QUAD is being built                       */
///* ------------------------------------------------------------------ */
//extension MGDecimal128 {
//
//    /* ---------------------------------------------------------------- */
//    /* Shared constants                                                 */
//    /* ---------------------------------------------------------------- */
//
//    /* sign and special values [top 32-bits; last two bits are don"t-care
//       for Infinity on input, last bit don"t-care for NaNs] */
//    private static let Sign  = UInt32(0x80000000)     /* 1 00000 00 Sign */
//    private static let NaN   = UInt32(0x7c000000)     /* 0 11111 00 NaN generic */
//    private static let qNaN  = UInt32(0x7c000000)     /* 0 11111 00 qNaN */
//    private static let sNaN  = UInt32(0x7e000000)     /* 0 11111 10 sNaN */
//    private static let Inf   = UInt32(0x78000000)     /* 0 11110 00 Infinity */
//    private static let MinSp = UInt32(0x78000000)     /* minimum special value */
//
//    static let DECECONL = EconL
//    static let DECQTINY = -Bias
//
//    static let DECCOMBEXP:[UInt32] = [
//        0, 0, 0, 0, 0, 0, 0, 0,
//        1<<DECECONL, 1<<DECECONL, 1<<DECECONL, 1<<DECECONL,
//        1<<DECECONL, 1<<DECECONL, 1<<DECECONL, 1<<DECECONL,
//        2<<DECECONL, 2<<DECECONL, 2<<DECECONL, 2<<DECECONL,
//        2<<DECECONL, 2<<DECECONL, 2<<DECECONL, 2<<DECECONL,
//        0,           0,           1<<DECECONL, 1<<DECECONL,
//        2<<DECECONL, 2<<DECECONL, Inf,         NaN,
//        0, 0,        0, 0,        0, 0,        0, 0,
//        1<<DECECONL, 1<<DECECONL, 1<<DECECONL, 1<<DECECONL,
//        1<<DECECONL, 1<<DECECONL, 1<<DECECONL, 1<<DECECONL,
//        2<<DECECONL, 2<<DECECONL, 2<<DECECONL, 2<<DECECONL,
//        2<<DECECONL, 2<<DECECONL, 2<<DECECONL, 2<<DECECONL,
//        0,           0,           1<<DECECONL, 1<<DECECONL,
//        2<<DECECONL, 2<<DECECONL, Inf,         NaN
//    ]
//
//    static let DECCOMBMSD:[UInt32] = [
//        0, 1, 2, 3, 4, 5, 6, 7, 0, 1, 2, 3, 4, 5, 6, 7,
//        0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 8, 9, 8, 9, 0, 0,
//        0, 1, 2, 3, 4, 5, 6, 7, 0, 1, 2, 3, 4, 5, 6, 7,
//        0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 8, 9, 8, 9, 0, 0
//    ]
//
//    static let DECCOMBFROM:[UInt32] = [
//        0x00000000, 0x04000000, 0x08000000, 0x0C000000, 0x10000000, 0x14000000,
//        0x18000000, 0x1C000000, 0x60000000, 0x64000000, 0x00000000, 0x00000000,
//        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x20000000, 0x24000000,
//        0x28000000, 0x2C000000, 0x30000000, 0x34000000, 0x38000000, 0x3C000000,
//        0x68000000, 0x6C000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
//        0x00000000, 0x00000000, 0x40000000, 0x44000000, 0x48000000, 0x4C000000,
//        0x50000000, 0x54000000, 0x58000000, 0x5C000000, 0x70000000, 0x74000000,
//        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
//    ]
//
////#if DECLITEND
//    static func DFBYTE(_ df:, _ off:Int)   ((df)->bytes[DECBYTES-1-(off)])
//    static func DFWORD(df, _ off:Int)   ((df)->words[DECWORDS-1-(off)])
//    static func DFWWORD(dfw, _ off:Int) ((dfw)->words[DECWWORDS-1-(off)])
////#else
////  #define DFBYTE(df, off)   ((df)->bytes[off])
////  #define DFWORD(df, off)   ((df)->words[off])
////  #define DFWWORD(dfw, off) ((dfw)->words[off])
////#endif
//
//    static func UBTOUI(_ b : inout ArraySlice<UInt8>) -> UInt32 {
//        var uiwork: UInt32
//        memcpy(&uiwork, &b, 4)
//        return uiwork
//    }
//    static func UBFROMUI(_ b : inout ArraySlice<UInt8>, _ i: inout UInt32)  { memcpy(&b, &i, 4) }
//
//    static func EXPISSPECIAL(_ exp:Int) -> Bool { exp>=MinSp }
//    static func EXPISINF(_ exp:Int) -> Bool { exp==Inf }
//    static func EXPISNAN(_ exp:Int) -> Bool { exp==qNaN || exp==sNaN }
//    static func NUMISSPECIAL(_ num:BCDNum) -> Bool { EXPISSPECIAL(num.exponent) }
//
//    static let allnines = [UInt8](repeating: 9, count: Pmax)
//
//    struct DecFloat {
//
//    }
//
//    struct BCDNum {
//        var sign: UInt32
//        var exponent: Int
//        var msd: [UInt8]
//    }
//
//    /* ------------------------------------------------------------------ */
//    /* decFloatFromString -- conversion from numeric string               */
//    /*                                                                    */
//    /*  result  is the decFloat format number which gets the result of    */
//    /*          the conversion                                            */
//    /*  *string is the character string which should contain a valid      */
//    /*          number (which may be a special value), \0-terminated      */
//    /*          If there are too many significant digits in the           */
//    /*          coefficient it will be rounded.                           */
//    /*  set     is the context                                            */
//    /*  returns result                                                    */
//    /*                                                                    */
//    /* The length of the coefficient and the size of the exponent are     */
//    /* checked by this routine, so the correct error (Underflow or        */
//    /* Overflow) can be reported or rounding applied, as necessary.       */
//    /*                                                                    */
//    /* There is no limit to the coefficient length for finite inputs;     */
//    /* NaN payloads must be integers with no more than Pmax-1 digits.  */
//    /* Exponents may have up to nine significant digits.                  */
//    /*                                                                    */
//    /* If bad syntax is detected, the result will be a quiet NaN.         */
//    /* ------------------------------------------------------------------ */
//    static func floatFromString(_ result: inout DecFloat, _ string: String, _ set: inout DecContext) {
////      Int    digits;                   // count of digits in coefficient
////      const  char *dotchar=NULL;       // where dot was found [NULL if none]
////      const  char *cfirst=string;      // -> first character of decimal part
////      const  char *c;                  // work
////      uByte *ub;                       // ..
////      uInt   uiwork;                   // for macros
////      bcdnum num;                      // collects data for finishing
////      uInt   error=DEC_Conversion_syntax;      // assume the worst
////      uByte  buffer[ROUNDUP(DECSTRING+11, 8)]; // room for most coefficents,
////                                               // some common rounding, +3, & pad
////      #if DECTRACE
////      // printf("FromString %s ...\n", string);
////      #endif
//        var num: BCDNum
//        var str = string  // consumable
//        var dotchar = -1
//        var cfirst = 0
//        var error : DecContext.Status = .conversionSyntax //DecContext.conversionSyntax
//
//        while true {                             // once-only "loop"
//            num.sign = 0                         // assume non-negative
//            num.msd = [UInt8]() // MSD is here always
//            num.msd.reserveCapacity(string.count+11)
//
//            // detect and validate the coefficient, including any leading,
//            // trailing, or embedded "."
//            // [could test four-at-a-time here (saving 10% for decQuads),
//            // but that risks storage violation because the position of the
//            // terminator is unknown]
//            while str.count > 0 {              // -> input character
//                let c = str.removeFirst()
//                if let digit = c.wholeNumberValue {
//                    // "0" through "9" is good
//                    num.msd.append(UInt8(digit))
//                    continue
//                }
//                if str.count == 0 { break }              // most common non-digit
//                if c == "." {
//                    if dotchar >= 0 { break }    // not first "."
//                    dotchar = num.msd.count       // record offset into decimal part
//                    continue
//                }
//                if str.count == string.count-1 {   // first in string...
//                    if c == "-" {                  // valid - sign
//                        cfirst += 1
//                        num.sign = Sign
//                        continue
//                    }
//                    if c == "+" {                  // valid + sign
//                        cfirst += 1
//                        continue
//                    }
//                }
//                // *c is not a digit, terminator, or a valid +, -, or "."
//                break
//            } // c loop
//
//            if num.msd.count > 0 || dotchar >= 0 {              // had digits and/or dot
//    //            let clast = last-1;            // note last coefficient char position
//                var exp = 0                        // exponent accumulator
//                var expNegative = false
//                if str.count > 0 {                   // something follows the coefficient
//                    // had some digits and more to come; expect E[+|-]nnn now
//                    var c = str.removeFirst()
//                    var firstexp = ""           // exponent first non-zero
//                    if c.uppercased() != "E" { break }
//                    c = str.removeFirst()              // to (optional) sign
//                    if c == "-" || c == "+" { expNegative = c == "-"; c = str.removeFirst() }    // step over sign (c=clast+2)
//                    if str.count == 0 { break }            // no digits!  (e.g., "1.2E")
//                    while c == "0" { c = str.removeFirst() }           // skip leading zeros [even last]
//                    firstexp.append(c)                    // remember start [maybe "\0"]
//                    // gather exponent digits
//                    var count=1
//                    var edig=c.wholeNumberValue ?? 10
//                    if edig<=9 {                  // [check not bad or terminator]
//                        exp += edig               // avoid initial X10
//                        while true {
//                            c = str.removeFirst(); count+=1
//                            edig=c.wholeNumberValue ?? 10
//                            if edig>9 { break }
//                            exp=exp*10+edig
//                        }
//                    }
//                    // if not now on the "\0", *c must not be a digit
//                    if str.count == 0 { break }
//
//                    // (this next test must be after the syntax checks)
//                    // if definitely more than the possible digits for format then
//                    // the exponent may have wrapped, so simply set it to a certain
//                    // over/underflow value
//                    if count>MGDecimal128.EmaxD { exp = MGDecimal128.Emax*2 }
//                    if expNegative { exp = -exp } // was negative
//                } // exponent part}
//
//                if dotchar >= 0 {                 // had a "."
//                    if num.msd.isEmpty { break }   // was dot alone: bad syntax
//                    exp -= num.msd.count-dotchar   // adjust exponent
//                    // [the "." can now be ignored]
//                }
//                num.exponent=exp                 // exponent is good; store it
//
//                // Here when whole string has been inspected and syntax is good
//                // cfirst->first digit or dot, clast->last digit or dot
//                error = .clearFlags        // no error possible now
//            } else {
//                // only Infinities and NaNs are allowed, here
//                if str.isEmpty { break }           // nothing there is bad
//                num.msd.append(0)                  // default a coefficient of 0
//                if str.hasPrefix("inf") || str.hasPrefix("INF") {
//                    num.exponent=Int(Inf)
//                } else {                           // should be a NaN
//                    num.exponent=Int(qNaN)     // assume quiet NaN
//                    var c = str.removeFirst()
//                    if c == "s" || c == "S" {       // probably an sNaN
//                        num.exponent=Int(sNaN)   // effect the "s"
//                        c = str.removeFirst() // and step over it
//                    }
//                    if c != "N" && c != "n" { break }  // check caseless "NaN"
//                    c = str.removeFirst()
//                    if c != "a" && c != "A" { break }  // ..
//                    c = str.removeFirst()
//                    if c != "N" && c != "n" { break }  // ..
//
//                    // now either nothing, or nnnn payload (no dots), expected
//                    // -> start of integer, and skip leading 0s [including plain 0]
//                    while !str.isEmpty && str.first! == "0" { str.removeFirst() }
//                    if !str.isEmpty {            // not empty or all-0, payload
//                        // payload found; check all valid digits and copy to buffer as bcd8
//                        while !str.isEmpty {
//                            c = str.removeFirst()
//                            if let digit = c.wholeNumberValue { num.msd.append(UInt8(digit)) }
//                            else { break } // quit if not 0-9
//                            if num.msd.count==Pmax-1 { break }  // too many digits
//                        }
//                        if !str.isEmpty { break }         // not all digits, or too many
//                    }
//                } // NaN or sNaN
//                error = .clearFlags                   // syntax is OK
//            } // digits=0 (special expected)
//            break                              // drop out
//        }                                   // [for(;;) once-loop]
//
//        // decShowNum(&num, "fromStr");
//
//        if !error.isEmpty {
//            set.status.formUnion(error)
//            num.exponent=Int(qNaN)     // set up quiet NaN
//            num.sign=0;                // .. with 0 sign
//            num.msd.append(0)          // .. and coefficient
//            // decShowNum(&num, "oops");
//        }
//
//        // decShowNum(&num, "dffs");
//        finalize(&result, &num, &set);       // round, check, and lay out
//        // decFloatShow(result, "fromString");
//    } // decFloatFromString
//
//    static func finalize(_ df: inout DecFloat, _ num: inout BCDNum, _ set: inout DecContext) {
//        //      uByte *ub;                  // work
//        //      uInt   dpd;                 // ..
//        //      uInt   uiwork;              // for macros
//        //      uByte *umsd=num->msd;       // local copy
//        //      uByte *ulsd=num->lsd;       // ..
//        //      uInt   encode;              // encoding accumulator
//        //      Int    length;              // coefficient length
//
//        let clen=num.msd.count
//        let COEXTRA = 2                        // extra-long coefficent for Decimal 128
//        if (clen<1 || clen>Pmax*3+2+COEXTRA) {
//            print("decFinalize: suspect coefficient [length=\(clen)]")
//        }
//        if (num.sign != 0 && num.sign != Sign) {
//            print("decFinalize: bad sign [\(num.sign)]")
//        }
//        if (!EXPISSPECIAL(num.exponent) && (num.exponent > 1999999999 || num.exponent < -1999999999)) {
//            print("decFinalize: improbable exponent [\(num.exponent)]")
//        }
//        // decShowNum(num, "final");
//
//        // A special will have an "exponent" which is very positive and a
//        // coefficient < Pmax
//        var length=clen                // coefficient length
//
//        if !NUMISSPECIAL(num) {
//            // skip leading insignificant zeros to calculate an exact length
//            // [this is quite expensive]
//            var umsd = 0
//            if num.msd[0] == 0 {
//                while umsd+3<num.msd.count && UBTOUI(&num.msd[umsd...umsd+3]) == 0 { umsd+=4 }
//                while num.msd[umsd] == 0 && umsd<num.msd.count { umsd+=1 }
//                length=num.msd.count-umsd+1            // recalculate
//            }
//            var drop=max(length-Pmax, DECQTINY-num.exponent); // digits to be dropped
//            // drop can now be > digits for bottom-clamp (subnormal) cases
//            if (drop>0) {                            // rounding needed
//                // (decFloatQuantize has very similar code to this, so any
//                // changes may need to be made there, too)
//                var roundat:Int                        // -> re-round digit
//                var reround:Int                         // reround value
//                // printf("Rounding; drop=%ld\n", (LI)drop);
//
//                num.exponent+=drop;                   // always update exponent
//
//                // Three cases here:
//                //   1. new LSD is in coefficient (almost always)
//                //   2. new LSD is digit to left of coefficient (so MSD is
//                //      round-for-reround digit)
//                //   3. new LSD is to left of case 2 (whole coefficient is sticky)
//                // [duplicate check-stickies code to save a test]
//                // [by-digit check for stickies as runs of zeros are rare]
//                if (drop<length) {                     // NB lengths not addresses
//                    roundat=length-drop;
//                    reround=num.msd[roundat]
//                    for (ub=roundat+1; ub<=ulsd; ub++) {
//                        if (*ub!=0) {                      // non-zero to be discarded
//                            reround=DECSTICKYTAB[reround];   // apply sticky bit
//                            break;                           // [remainder don"t-care]
//                        }
//                    } // check stickies
//                    ulsd=roundat-1;                      // new LSD
//                } else {                                // edge case
//                    if (drop==length) {
//                        roundat = umsd;
//                        reround = *roundat;
//                    } else {
//                        roundat=umsd-1;
//                        reround=0;
//                    }
//                    for (ub=roundat+1; ub<=ulsd; ub++) {
//                        if (*ub!=0) {                      // non-zero to be discarded
//                            reround=DECSTICKYTAB[reround];   // apply sticky bit
//                            break;                           // [remainder don"t-care]
//                        }
//                    } // check stickies
//                    *umsd=0;                             // coefficient is a 0
//                    ulsd=umsd;                           // ..
//                }
//
//                if (reround != 0) {                      // discarding non-zero
//                    var bump=0
//                    set.status.insert(.inexact) //_Inexact;
//                    // if adjusted exponent [exp+digits-1] is < EMIN then num is
//                    // subnormal -- so raise Underflow
//                    if (num.exponent<Emin && (num.exponent+(ulsd-umsd+1)-1)<Emin) {
//                        set.status.insert(.underflow)
//
//                        // next decide whether increment of the coefficient is needed
//                        if set.roundMode == .halfEven {    // fastpath slowest case
//                            if (reround>5) {
//                                bump = 1               // >0.5 goes up
//                            } else if (reround==5) {   // exactly 0.5000 ..
//                                bump = *ulsd & 0x01;   // .. up iff [new] lsd is odd
//                            }
//                        } else {
//                            switch set.roundMode {
//                                case .down: //DEC_ROUND_DOWN:
//                                    // no change
//                                    break // r-d
//                                case .halfDown: //DEC_ROUND_HALF_DOWN:
//                                    if (reround>5) { bump=1 }
//                                case .halfUp: //DEC_ROUND_HALF_UP:
//                                    if (reround>=5) { bump=1 }
//                                case .up: // DEC_ROUND_UP:
//                                    if (reround>0) { bump=1 }
//                                case .ceiling: // DEC_ROUND_CEILING:
//                                    // same as _UP for positive numbers, and as _DOWN for negatives
//                                    if (num.sign == 0 && reround>0) { bump=1 }
//                                case .floor: // DEC_ROUND_FLOOR:
//                                    // same as _UP for negative numbers, and as _DOWN for positive
//                                    // [negative reround cannot occur on 0]
//                                    if (num.sign != 0 && reround>0) { bump=1 }
//                                case .r05Up: // DEC_ROUND_05UP:
//                                    if (reround>0) { // anything out there is "sticky"
//                                        // bump iff lsd=0 or 5; this cannot carry so it could be
//                                        // effected immediately with no bump -- but the code
//                                        // is clearer if this is done the same way as the others
//                                        if (*ulsd==0 || *ulsd==5) { bump=1 }
//                                    }
//                                default:      // e.g., DEC_ROUND_MAX
//                                    set.status.insert(.invalidContext)
//                                    print("Unknown rounding mode: \(set.roundMode)")
//                            } // switch (not r-h-e)
//                        }
//                        // printf("ReRound: %ld  bump: %ld\n", (LI)reround, (LI)bump);
//
//                        if (bump != 0) {                       // need increment
//                            // increment the coefficient; this might end up with 1000...
//                            // (after the all nines case)
//                            ub=ulsd;
//                            for(; ub-3>=umsd && UBTOUI(ub-3)==0x09090909; ub-=4)  {
//                                UBFROMUI(ub-3, 0);               // to 00000000
//                            }
//                            // [note ub could now be to left of msd, and it is not safe
//                            // to write to the the left of the msd]
//                            // now at most 3 digits left to non-9 (usually just the one)
//                            for (; ub>=umsd; *ub=0, ub--) {
//                                if (*ub==9) { continue }           // carry
//                                *ub+=1;
//                                break;
//                            }
//                            if (ub<umsd) {                     // had all-nines
//                                *umsd=1;                         // coefficient to 1000...
//                                // usually the 1000... coefficient can be used as-is
//                                if ((ulsd-umsd+1)==Pmax) {
//                                    num.exponent++;
//                                } else {
//                                    // if coefficient is shorter than Pmax then num is
//                                    // subnormal, so extend it; this is safe as drop>0
//                                    // (or, if the coefficient was supplied above, it could
//                                    // not be 9); this may make the result normal.
//                                    ulsd++;
//                                    *ulsd=0;
//                                    // [exponent unchanged]
//                                    if (num.exponent != DECQTINY) { // sanity check
//                                        print("decFinalize: bad all-nines extend [^\(num.exponent), %ld]",
//                                               (LI)num.exponent, (LI)(ulsd-umsd+1));
//                                    }
//                                } // subnormal extend
//                            } // had all-nines
//                        } // bump needed
//                    } // inexact rounding
//
//                    length=(ulsd-umsd+1);               // recalculate (may be <Pmax)
//                } // need round (drop>0)
//
//                // The coefficient will now fit and has final length unless overflow
//                // decShowNum(num, "rounded");
//
//                // if exponent is >=emax may have to clamp, overflow, or fold-down
//                if (num.exponent>Emax-(Pmax-1)) { // is edge case
//                    // printf("overflow checks...\n");
//                    if (*ulsd==0 && ulsd==umsd) {     // have zero
//                        num.exponent=Emax-(Pmax-1); // clamp to max
//                    } else if ((num.exponent+length-1)>Emax) { // > Nmax
//                        // Overflow -- these could go straight to encoding, here, but
//                        // instead num is adjusted to keep the code cleaner
//                        var needmax=0;                 // 1 for finite result
//                        set.status.formUnion([.overflow, .inexact]) //Overflow | DEC_Inexact);
//                        switch set.roundMode {
//                            case .down: //DEC_ROUND_DOWN:
//                                needmax=1;                  // never Infinity
//                            case .r05Up: // DEC_ROUND_05UP:
//                                needmax=1;                  // never Infinity
//                            case .ceiling: //DEC_ROUND_CEILING: {
//                                if num.sign != 0 { needmax=1 }  // Infinity iff non-negative
//                            case .floor: // DEC_ROUND_FLOOR: {
//                                if num.sign == 0 { needmax=1 }  // Infinity iff negative
//                            default: break;               // Infinity in all other cases
//                        }
//                        if (needmax != 0) {                 // easy .. set Infinity
//                            num.exponent=Int(Inf)
//                            *umsd=0;                      // be clean: coefficient to 0
//                            ulsd=umsd;                    // ..
//                        } else {                         // return Nmax
//                            umsd=allnines;                // use constant array
//                            ulsd=allnines+Pmax-1;
//                            num.exponent=Emax-(Pmax-1);
//                        }
//                    } else { // no overflow but non-zero and may have to fold-down
//                        let shift=num.exponent-(Emax-(Pmax-1));
//                        if (shift>0) {                  // fold-down needed
//                            // fold down needed; must copy to buffer in order to pad
//                            // with zeros safely; fortunately this is not the worst case
//                            // path because cannot have had a round
//                            uByte buffer[ROUNDUP(Pmax+3, 4)]; // [+3 allows uInt padding]
//                            uByte *s=umsd;                // source
//                            uByte *t=buffer;              // safe target
//                            uByte *tlsd=buffer+(ulsd-umsd)+shift; // target LSD
//                            // printf("folddown shift=%ld\n", (LI)shift);
//                            for (; s<=ulsd; s+=4, t+=4) { UBFROMUI(t, UBTOUI(s)) }
//                            for (t=tlsd-shift+1; t<=tlsd; t+=4) { UBFROMUI(t, 0); } // pad 0s
//                            num.exponent-=shift;
//                            umsd=buffer;
//                            ulsd=tlsd;
//                        }
//                    } // fold-down?
//                    length=(ulsd-umsd+1);               // recalculate length
//                } // high-end edge case
//            } // finite number
//
//            /*------------------------------------------------------------------*/
//            /* At this point the result will properly fit the decFloat          */
//            /* encoding, and it can be encoded with no possibility of error     */
//            /*------------------------------------------------------------------*/
//            // Following code does not alter coefficient (could be allnines array)
//
//            // fast path possible when Pmax digits
//            if (length==Pmax) {
//                return decFloatFromBCD(df, num.exponent, umsd, num.sign);
//            } // full-length
//
//            // slower path when not a full-length number; must care about length
//            // [coefficient length here will be < Pmax]
//            var encode:Int
//            if (!NUMISSPECIAL(num)) {             // is still finite
//                // encode the combination field and exponent continuation
//                let uexp=num.exponent+Bias // biased exponent
//                let code=(uexp>>EconL)<<4;      // top two bits of exp
//                // [msd==0]
//                // look up the combination field and make high word
//                encode=Int(DECCOMBFROM[code])          // indexed by (0-2)*16+msd
//                encode|=(uexp<<(32-6-EconL)) & 0x03ffffff; // exponent continuation
//            } else {
//                encode=num.exponent                // special [already in word]
//            }
//            encode|=Int(num.sign)                  // add sign
//
//            // private macro to extract a declet, n (where 0<=n<DECLETS and 0
//            // refers to the declet from the least significant three digits)
//            // and put the corresponding DPD code into dpd.  Access to umsd and
//            // ulsd (pointers to the most and least significant digit of the
//            // variable-length coefficient) is assumed, along with use of a
//            // working pointer, uInt *ub.
//            // As not full-length then chances are there are many leading zeros
//            // [and there may be a partial triad]
//            func getDPDt(_ dpd: inout Int, _ n:Int) {
//                ub=ulsd-(3*(n))-2;
//                if (ub<umsd-2) {
//                    dpd=0
//                } else if (ub>=umsd) {
//                    dpd=BCD2DPD[(*ub*256)+(*(ub+1)*16)+*(ub+2)]
//                } else {
//                    dpd=*(ub+2);
//                    if (ub+1==umsd) { dpd+=*(ub+1)*16; dpd=BCD2DPD[dpd] }
//                }
//            }
//
//            // place the declets in the encoding words and copy to result (df),
//            // according to endianness; in all cases complete the sign word
//            // first
//            var dpd = 0
//            if Pmax == 7 {
//                getDPDt(&dpd, 1);
//                encode|=dpd<<10;
//                getDPDt(&dpd, 0);
//                encode|=dpd;
//                DFWORD(df, 0)=encode;     // just the one word
//
//            } else if Pmax==16 {
//                getDPDt(&dpd, 4); encode|=dpd<<8;
//                getDPDt(&dpd, 3); encode|=dpd>>2;
//                DFWORD(df, 0)=encode;
//                encode=dpd<<30;
//                getDPDt(&dpd, 2); encode|=dpd<<20;
//                getDPDt(&dpd, 1); encode|=dpd<<10;
//                getDPDt(&dpd, 0); encode|=dpd;
//                DFWORD(df, 1)=encode;
//
//            } else if Pmax==34 {
//                getDPDt(&dpd,10); encode|=dpd<<4;
//                getDPDt(&dpd, 9); encode|=dpd>>6;
//                DFWORD(df, 0)=encode;
//
//                encode=dpd<<26;
//                getDPDt(&dpd, 8); encode|=dpd<<16;
//                getDPDt(&dpd, 7); encode|=dpd<<6;
//                getDPDt(&dpd, 6); encode|=dpd>>4;
//                DFWORD(df, 1)=encode;
//
//                encode=dpd<<28;
//                getDPDt(&dpd, 5); encode|=dpd<<18;
//                getDPDt(&dpd, 4); encode|=dpd<<8;
//                getDPDt(&dpd, 3); encode|=dpd>>2;
//                DFWORD(df, 2)=encode;
//
//                encode=dpd<<30;
//                getDPDt(&dpd, 2); encode|=dpd<<20;
//                getDPDt(&dpd, 1); encode|=dpd<<10;
//                getDPDt(&dpd, 0); encode|=dpd;
//                DFWORD(df, 3)=encode;
//            }
//
//            // printf("Status: %08lx\n", (LI)set.status);
//            // decFloatShow(df, "final2");
//        } // decFinalize
//
//}
