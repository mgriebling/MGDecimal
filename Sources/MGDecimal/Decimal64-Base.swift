//
//  Decimal64.swift
//  
//
//  Created by Mike Griebling on 2022-03-12.
//

import Foundation

public struct Decimal64 : ExpressibleByStringLiteral, ExpressibleByFloatLiteral, CustomStringConvertible,
                          ExpressibleByIntegerLiteral {

    private static var enableStateOutput = false   // set to true to monitor variable state (i.e., invalid operations, etc.)
    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: - Decimal number storage
    var x: UInt64
    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: - Class State variables
    public static private(set) var state = Status.clearFlags
    public static private(set) var rounding = Rounding.toNearestOrEven
    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: - Initializers
    init(raw: UInt64) { x = raw } // only for internal use
    
    public init(stringLiteral value: String) {
        x = Decimal64.bid64_from_string(value, Decimal64.rounding, &Decimal64.state)
    }
    
    public init(floatLiteral value: Double) {
        x = Decimal64.double_to_bid64(value, Decimal64.rounding, &Decimal64.state)
    }
    
    public init(integerLiteral value: Int) {
        x = Decimal64.bid64_from_int64(Int64(value), Decimal64.rounding, &Decimal64.state)
    }
    
    public init(decimal32: Decimal32) {
        x = Decimal64.BID32_to_BID64(decimal32.x, &Decimal64.state)
    }
    
    public init(_ value: Decimal128) { x = Decimal128.bid128_to_bid64(value.x, Decimal64.rounding, &Decimal64.state) }
    public init(_ value: Decimal32) { x = Decimal32.bid32_to_bid64(value.x, &Decimal64.state) }
    
    var decimal32: Decimal32 {
        Decimal32(raw: Decimal64.BID64_to_BID32(x, Decimal64.rounding, &Decimal64.state))
    }
    
    public var description: String { Decimal64.bid64_to_string(x) }

}
