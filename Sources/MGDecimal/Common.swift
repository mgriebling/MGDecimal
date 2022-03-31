//
//  File.swift
//  
//
//  Created by Mike Griebling on 2022-03-21.
//

import Foundation

func addDecimalPointAndExponent(_ ps:String, _ exponent:Int, _ maxDigits:Int) -> String {
    var digits = ps.count
    var ps = ps
    var exponent_x = exponent
    if exponent_x == 0 {
        ps.insert(".", at: ps.index(ps.startIndex, offsetBy: exponent_x+1))
    } else if abs(exponent_x) > maxDigits {
        ps.insert(".", at: ps.index(after: ps.startIndex))
        ps += "e"
        if exponent_x < 0 {
            ps += "-"
            exponent_x = -exponent_x
        } else {
            ps += "+"
        }
        ps += String(exponent_x)
    } else if digits <= exponent_x {
        // format the number without an exponent
        while digits <= exponent_x {
            // pad the number with zeros
            ps += "0"; digits += 1
        }
    } else if exponent_x < 0 {
        while exponent_x < -1 {
            // insert leading zeros
            ps = "0" + ps; exponent_x += 1
        }
        ps = "0." + ps
    } else {
        // insert the decimal point
        ps.insert(".", at: ps.index(ps.startIndex, offsetBy: exponent_x+1))
        if ps.hasSuffix(".") { ps.removeLast() }
    }
    return ps
}
