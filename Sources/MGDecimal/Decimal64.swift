//
//  Decimal64.swift
//  
//
//  Created by Mike Griebling on 2022-03-12.
//

import Foundation

public struct Decimal64 {
    
    var x: UInt64
    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: - Class State variables
    public static private(set) var state : Status = .clearFlags
    public static private(set) var rounding : Rounding = .halfEven
    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////
    // MARK: - Initializers
    public init(raw: UInt64) { x = raw } // only for internal use
    public init(decimal32: Decimal32) {
        x = Decimal64.BID32_to_BID64(decimal32.x, &Decimal64.state)
    }
    
    var decimal32: Decimal32 {
        Decimal32(raw: Decimal64.BID64_to_BID32(x, Decimal64.rounding, &Decimal64.state))
    }
    
}
