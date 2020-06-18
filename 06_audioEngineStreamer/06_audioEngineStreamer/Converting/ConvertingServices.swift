//
//  ConvertingServices.swift
//  06_audioEngineStreamer
//
//  Created by sy on 2020/6/17.
//  Copyright © 2020 sy. All rights reserved.
//

import Foundation
import AVFoundation

public protocol ConvertingServices: AnyObject {
    var parser: ParsingServices? { get }
    var sourceFormat: AVAudioFormat? { get }
    var targetFormat: AVAudioFormat { get }
    var readOffset: AVAudioPacketCount { get }
    var isConvertingCompeleted: Bool { get }
    var canResumeFromInterruption: Bool { get }
    
    init(_ format: AVAudioFormat, _ parser: ParsingServices) throws
    func convert(_ frames: AVAudioFrameCount) throws -> AVAudioPCMBuffer
    func seek(to packet: AVAudioPacketCount)
}



extension ConvertingServices {
    public var sourceFormat: AVAudioFormat? {
        return self.parser!.dataFormat
    }
    
    public var canResumeFromInterruption: Bool {
        return false
    }
}
