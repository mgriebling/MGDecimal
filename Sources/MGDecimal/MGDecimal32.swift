//
//  File.swift
//  
//
//  Created by Mike Griebling on 2022-03-07.
//

import Foundation

public struct BID32 : CustomStringConvertible, ExpressibleByStringLiteral, ExpressibleByIntegerLiteral,
               ExpressibleByFloatLiteral {
    
    var x : UInt32   // 32-bit decimal number is stored here
    
    static public private(set) var state : Status = .clearFlags
    static public private(set) var rounding : RoundingType = .halfEven
    
    public init(raw: UInt32) { x = raw } // only for internal use
    
    public init(integerLiteral value: Int) {
        self = BID32.int64_to_BID32(Int64(value), BID32.rounding, &BID32.state)
        if !BID32.state.isEmpty { print("Warning: \(BID32.state)"); BID32.state = .clearFlags }
    }
    
    public init(floatLiteral value: Double) {
        self.init(raw: 0)
        
    }

    public init(stringLiteral value: String) {
        var x = BID32(raw: 0)
        BID32.bid32_from_string(&x, value, BID32.rounding, &BID32.state)
        if !BID32.state.isEmpty { print("Warning: \(BID32.state)"); BID32.state = .clearFlags }
        self.x = x.x
    }

    public var description: String {
        var res = ""
        BID32.bid32_to_string(&res, self, BID32.rounding, BID32.state)
        return res
    }
    
}
