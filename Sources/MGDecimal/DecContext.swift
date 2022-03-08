//
//  DecContext.swift
//  DecNumber
//
//  Created by Mike Griebling on 2021-12-16.
//  Copyright © 2021 Computer Inspirations. All rights reserved.
//

import Foundation

public enum Rounding: Codable {
    case ceiling    /* round towards +infinity         */
    case floor      /* round towards -infinity         */
    case down       /* round towards 0 (truncate)      */
    case up         /* round away from 0               */
    case halfEven   /* 0.5 rounds to nearest even      */
    case halfDown   /* 0.5 rounds toward 0             */
    case halfUp     /* 0.5 rounds away from 0          */
}

public struct Status: OptionSet, CustomStringConvertible {
    public let rawValue: Int32
    
    /* IEEE extended flags only */
    private static let DEC_Conversion_syntax    = 0x00000001
    private static let DEC_Division_by_zero     = 0x00000002
    private static let DEC_Division_impossible  = 0x00000004
    private static let DEC_Division_undefined   = 0x00000008
    private static let DEC_Insufficient_storage = 0x00000010 /* [when malloc fails]  */
    private static let DEC_Inexact              = 0x00000020
    private static let DEC_Invalid_context      = 0x00000040
    private static let DEC_Invalid_operation    = 0x00000080
    private static let DEC_Lost_digits          = 0x00000100
    private static let DEC_Overflow             = 0x00000200
    private static let DEC_Clamped              = 0x00000400
    private static let DEC_Rounded              = 0x00000800
    private static let DEC_Subnormal            = 0x00001000
    private static let DEC_Underflow            = 0x00002000
    
    public static let conversionSyntax    = Status(rawValue: Int32(DEC_Conversion_syntax))
    public static let divisionByZero      = Status(rawValue: Int32(DEC_Division_by_zero))
    public static let divisionImpossible  = Status(rawValue: Int32(DEC_Division_impossible))
    public static let divisionUndefined   = Status(rawValue: Int32(DEC_Division_undefined))
    public static let insufficientStorage = Status(rawValue: Int32(DEC_Insufficient_storage))
    public static let inexact             = Status(rawValue: Int32(DEC_Inexact))
    public static let invalidContext      = Status(rawValue: Int32(DEC_Invalid_context))
    public static let lostDigits          = Status(rawValue: Int32(DEC_Lost_digits))
    public static let invalidOperation    = Status(rawValue: Int32(DEC_Invalid_operation))
    public static let overflow            = Status(rawValue: Int32(DEC_Overflow))
    public static let clamped             = Status(rawValue: Int32(DEC_Clamped))
    public static let rounded             = Status(rawValue: Int32(DEC_Rounded))
    public static let subnormal           = Status(rawValue: Int32(DEC_Subnormal))
    public static let underflow           = Status(rawValue: Int32(DEC_Underflow))
    public static let clearFlags          = Status([])
    
    public static let errorFlags = Status(rawValue: Int32(DEC_Division_by_zero | DEC_Overflow |
        DEC_Underflow | DEC_Conversion_syntax | DEC_Division_impossible |
        DEC_Division_undefined | DEC_Insufficient_storage | DEC_Invalid_context | DEC_Invalid_operation))
    public static let informationFlags = Status(rawValue: Int32(DEC_Clamped | DEC_Rounded |
        DEC_Inexact | DEC_Lost_digits))
    
    public init(rawValue: Int32) { self.rawValue = rawValue }
    
    public var hasError: Bool { !Status.errorFlags.intersection(self).isEmpty }
    public var hasInfo: Bool { !Status.informationFlags.intersection(self).isEmpty }
    
    public var description: String {
        var str = ""
        if self.contains(.conversionSyntax)    { str += "Conversion syntax, "}
        if self.contains(.divisionByZero)      { str += "Division by zero, " }
        if self.contains(.divisionImpossible)  { str += "Division impossible, "}
        if self.contains(.divisionUndefined)   { str += "Division undefined, "}
        if self.contains(.insufficientStorage) { str += "Insufficient storage, " }
        if self.contains(.inexact)             { str += "Inexact number, " }
        if self.contains(.invalidContext)      { str += "Invalid context, " }
        if self.contains(.invalidOperation)    { str += "Invalid operation, " }
        if self.contains(.lostDigits)          { str += "Lost digits, " }
        if self.contains(.overflow)            { str += "Overflow, " }
        if self.contains(.clamped)             { str += "Clamped, " }
        if self.contains(.rounded)             { str += "Rounded, " }
        if self.contains(.subnormal)           { str += "Subnormal, " }
        if self.contains(.underflow)           { str += "Underflow, " }
        if str.hasSuffix(", ") { str.removeLast(2) }
        return str
    }
}

public struct DecContext {
    
    public enum ContextInitType: Codable {
        case base       // ANSI X3.274 arithmetic subset: digits = 9, emax = 999999999, round = halfUp, status = 0, all traps
        case dec32      // IEEE 754 rules: digits = 7, emax = 96, emin = -95, round = halfEven, status = 0, no traps
        case dec64      // IEEE 754 rules: digits = 16, emax = 384, emin = -383, round = halfEven, status = 0, no traps
        case dec128     // IEEE 754 rules: digits = 34, emax = 6144, emin = -6143, round = halfEven, status = 0, no traps
    }

    public var statusString: String { status.description }
    
    // access to states
    public var roundMode: Rounding
    public var status: Status
    public var minExponent: Int
    public var maxExponent: Int
    public var clamp: Bool
    public var extended: Bool
    public var digits: Int
    
    init(initKind: ContextInitType) {
        status = []               // cleared
        roundMode = .halfEven     // 0.5 rises
        switch initKind {
            case .base:
                digits = 9                // 9 digits
                maxExponent =  999999999  // 9-digit exponents
                minExponent = -999999999  // .. balanced
                clamp = false             // no clamping
                extended = false
            case .dec32:
                digits = 7
                maxExponent =  96
                minExponent = -95
                clamp = true              // clamp exponents
                extended = true           // set
            case .dec64:
                digits=16
                maxExponent =  384
                minExponent = -383
                clamp = true              // clamp exponents
                extended = true           // set
            case .dec128:
                digits = 34
                maxExponent =  6144
                minExponent = -6143
                clamp = true              // clamp exponents
                extended = true           // set
        }
    }
    
}
