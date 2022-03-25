//
//  File.swift
//  
//
//  Created by Mike Griebling on 2022-03-24.
//

import Foundation

public struct UInt128 : Equatable {
    
    var w = [UInt64](repeating: 0, count: 2)
    
    init() { }
    init(w: [UInt64]) { self.w = w }
    init(upper:UInt64, lower:UInt64) { w[1]=upper; w[0]=lower }
    
}
