//
//  Int32+Extension.swift
//  02_caRecorderAndPlayer
//
//  Created by sy on 2020/5/31.
//  Copyright © 2020 sy. All rights reserved.
//

import Foundation


extension Int32 {
    public var is4CharaterCode: Bool {
        let firstByte = (self >> 24) & 0x000000ff
        let secondByte = (self >> 16) & 0x000000ff
        let thirdByte = (self >> 8) & 0x000000ff
        let fourthByte = self & 0x000000ff
        return isprint(firstByte) != 0
        && isprint(secondByte) != 0
        && isprint(thirdByte) != 0
        && isprint(fourthByte) != 0
    }
    
    public var fourCharaters: String? {
        if self.is4CharaterCode {
            let firstCharater = Character(Unicode.Scalar(UInt32(self >> 24) & 0x000000ff)!)
            let secondCharater = Character(Unicode.Scalar(UInt32(self >> 16) & 0x000000ff)!)
            let thirdCharater = Character(Unicode.Scalar(UInt32(self >> 8) & 0x000000ff)!)
            let fourthCharater = Character(Unicode.Scalar(UInt32(self & 0x000000ff))!)
            return String(firstCharater) + String(secondCharater) + String(thirdCharater) + String(fourthCharater)
        }
        return nil
    }
}
