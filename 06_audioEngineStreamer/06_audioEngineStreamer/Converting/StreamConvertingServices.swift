//
//  StreamConvertingServices.swift
//  06_audioEngineStreamer
//
//  Created by sy on 2020/6/17.
//  Copyright © 2020 sy. All rights reserved.
//

import Foundation
import AVFoundation
import AudioToolbox
import os.log


let StreamConvertingServicesError_ParserMissingDataFormat: OSStatus = 932332581
let StreamConvertingServicesError_EndOfStream: OSStatus = 932332582
let StreamConvertingServicesError_NoEnoughData: OSStatus = 932332583

public class StreamConvertingServices: NSObject, ConvertingServices {
    public enum StreamConvertingServicesError: Error {
        case noAvaliableHardware
        case hardwareWasOccupied
        case invailedParser
        case parserMissDataFormat
        case formatNotSupported
        case failedToAllocatePCMBuffer
        case noEnoughData
        case endOfStream
        case otherError(OSStatus)
    }
    
    public weak var parser: ParsingServices?
    
    public var targetFormat: AVAudioFormat
    
    public fileprivate(set) var readOffset: AVAudioPacketCount = 0
    
    public var totalPacketCount: AVAudioPacketCount?  {
        return  self.parser!.dataPacketCount != nil ? AVAudioPacketCount(self.parser!.dataPacketCount!) : nil
    }
    
    public var avaliablePacketCount: AVAudioPacketCount {
        return AVAudioPacketCount(self.parser!.parsedPackets.count)
    }
    
    public var isConvertingCompeleted: Bool {
        if let _ = self.totalPacketCount {
            return self.readOffset >= self.totalPacketCount! - 1
        }
        return false
    }
    
    fileprivate var logger: OSLog = OSLog(subsystem: "com.audioStreamEngine.sy", category: "converting")
    fileprivate var converter: AudioConverterRef?
    
    public private(set) var canResumeFromInterruption: Bool = false
    
    fileprivate var packetBuffer: UnsafeMutableRawPointer?
    fileprivate var packetDescBuffer: UnsafeMutablePointer<AudioStreamPacketDescription>?
    
    public required init(_ format: AVAudioFormat, _ parser: ParsingServices) throws {
        guard parser.isReadyToProducePacket else {
            os_log(.error, "[converting] failed to create converter because parser is not ready")
            throw StreamConvertingServicesError.invailedParser
        }
        
        guard let _ = parser.dataFormat else {
            os_log(.error, "[converting] failed to create converter because parser is missing data format")
            throw StreamConvertingServicesError.parserMissDataFormat
        }
        
        var converter: AudioConverterRef?
        let result = AudioConverterNew(parser.dataFormat!.streamDescription,
                                       format.streamDescription,
                                       &converter)
        guard result == noErr else {
            if result == kAudioConverterErr_FormatNotSupported {
                os_log(.error, "[converting] failed to create converter because formats is unconvertable")
                throw StreamConvertingServicesError.formatNotSupported
            } else if result == kAudioConverterErr_NoHardwarePermission {
                os_log(.error, "[converting] failed to create converter because no avaliable hardware")
                throw StreamConvertingServicesError.noAvaliableHardware
            }
            os_log(.error, "[converting] failed to create converter, error code: %i, desc: %@", result, converterErrorStringDescription(result))
            throw StreamConvertingServicesError.otherError(result)
        }
        
        // initailze converter
        if let _ = parser.magicCookieData {
            if noErr != AudioConverterSetProperty(converter!,
                                      kAudioConverterDecompressionMagicCookie,
                                      UInt32(parser.magicCookieData!.size),
                                      parser.magicCookieData!.data!) {
               os_log(.error, "[converting] failed set kAudioConverterDecompressionMagicCookie, os error: %i", result)
            }
            os_log(.debug, "[converting] success set kAudioConverterDecompressionMagicCookie")
        }
        
        if let _ = parser.channelLayout {
            if noErr != AudioConverterSetProperty(converter!,
                                                  kAudioConverterInputChannelLayout,
                                                  UInt32(MemoryLayout<AudioChannelLayout>.size),
                                                  parser.channelLayout!.layout) {
                os_log(.error, "[converting] failed set kAudioConverterInputChannelLayout, os error: %i", result)
            }
            os_log(.debug, "[converting] success set kAudioConverterInputChannelLayout")
        }
        
        if let channelLayout = format.channelLayout {
            if noErr != AudioConverterSetProperty(converter!,
                                                  kAudioConverterOutputChannelLayout,
                                                  UInt32(MemoryLayout<AudioChannelLayout>.size),
                                                  channelLayout.layout) {
                os_log(.error, "[converting] failed set kAudioConverterOutputChannelLayout, os error: %i", result)
            }
            os_log(.debug, "[converting] success set kAudioConverterOutputChannelLayout")
        }
        
        var canResume: UInt32 = 0
        var propertySize: UInt32 = UInt32(MemoryLayout.size(ofValue: canResume))
        if noErr == AudioConverterGetProperty(converter!,
                                              kAudioConverterPropertyCanResumeFromInterruption,
                                              &propertySize,
                                              &canResume) {
            self.canResumeFromInterruption = canResume == 1
            os_log(.debug, "[converting] can resume from interruption: %i", canResume)
        }
        
        self.targetFormat = format
        self.parser = parser
        self.converter = converter
        super.init()
    }
    
    public convenience init (_ format: AVAudioFormat, _ parser: ParsingServices, _ startOfRead: AVAudioPacketCount) throws {
        try self.init(format, parser)
        self.readOffset = startOfRead
    }
    
    deinit {
        if let _ = self.converter {
            AudioConverterDispose(self.converter!)
            self.converter = nil
        }
        self.packetBuffer?.deallocate()
        self.packetDescBuffer?.deallocate()
    }
    
    public func convert(_ frames: AVAudioFrameCount) throws -> AVAudioPCMBuffer {
        guard !self.isConvertingCompeleted else {
            os_log(.error, log:self.logger, "end of stream")
            throw StreamConvertingServicesError.endOfStream
        }
        
        guard self.readOffset < self.avaliablePacketCount else {
            os_log(.error, log:self.logger, "no enough packets to convert")
            throw StreamConvertingServicesError.noEnoughData
        }
        
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: self.targetFormat, frameCapacity: frames) else {
            os_log(.error, log:self.logger, "can not allocate pcm buffer")
            throw StreamConvertingServicesError.failedToAllocatePCMBuffer
        }
        pcmBuffer.frameLength = frames //!!!!!!!!!!!!!!!!!!!!!!!!!! warning warning warning
                                        // you must set this property before using the buffer. The length must be less than or equal to the frameCapacity of the buffer

        let framesPerPacket = self.targetFormat.streamDescription.pointee.mFramesPerPacket
        var outputPacketCount: UInt32 = frames / framesPerPacket
        let userData = Unmanaged.passUnretained(self).toOpaque()
        
        let result = AudioConverterFillComplexBuffer(self.converter!,
                                                     converterInputDataProc(_:_:_:_:_:),
                                                     userData,
                                                     &outputPacketCount,
                                                     pcmBuffer.mutableAudioBufferList,
                                                     nil)
        
        if result != noErr {
            switch result {
                case kAudioConverterErr_FormatNotSupported:
                    os_log(.error, log:self.logger, "got convert error kAudioConverterErr_FormatNotSupported")
                    throw StreamConvertingServicesError.formatNotSupported
                
                case kAudioConverterErr_HardwareInUse:
                    os_log(.error, log:self.logger, "got convert error kAudioConverterErr_HardwareInUse")
                    throw StreamConvertingServicesError.hardwareWasOccupied
                
                case StreamConvertingServicesError_ParserMissingDataFormat:
                    os_log(.error, log:self.logger, "got convert error StreamConvertingServicesError_ParserMissingDataFormat")
                    throw StreamConvertingServicesError.parserMissDataFormat
                
                case StreamConvertingServicesError_NoEnoughData:
                    os_log(.error, log:self.logger, "got convert error StreamConvertingServicesError_NoEnoughData")
                    throw StreamConvertingServicesError.noEnoughData
                
                case StreamConvertingServicesError_EndOfStream:
                    os_log(.error, log:self.logger, "got convert error StreamConvertingServicesError_EndOfStream")
                    throw StreamConvertingServicesError.endOfStream
                
                default:
                    os_log(.error, log:self.logger, "got convert error code: %i, desc: %@", result, converterErrorStringDescription(result))
                    throw StreamConvertingServicesError.otherError(result)
            }
            
        }
        
        os_log(.debug, log: self.logger, "success to convert %i packets, %i frames", outputPacketCount,outputPacketCount * framesPerPacket)
        
        pcmBuffer.frameLength = outputPacketCount * framesPerPacket
        return pcmBuffer
    }
    
    public func seek(to packet: AVAudioPacketCount) {
        
    }
    
}


fileprivate func converterInputDataProc(_ inAudioConverter: AudioConverterRef,
                                        _ ioNumberDataPackets: UnsafeMutablePointer<UInt32>,
                                        _ ioData: UnsafeMutablePointer<AudioBufferList>,
                                        _ outDataPacketDescription: UnsafeMutablePointer<UnsafeMutablePointer<AudioStreamPacketDescription>?>?,
                                        _ inUserData: UnsafeMutableRawPointer?) -> OSStatus {
    let converter = Unmanaged<StreamConvertingServices>.fromOpaque(inUserData!).takeUnretainedValue()

    guard let srcFmt = converter.parser!.dataFormat else {
        ioNumberDataPackets.pointee = 0
        return StreamConvertingServicesError_ParserMissingDataFormat
    }

    guard !converter.isConvertingCompeleted else {
        ioNumberDataPackets.pointee = 0
        return StreamConvertingServicesError_EndOfStream
    }
    
    guard converter.readOffset < converter.avaliablePacketCount else {
        ioNumberDataPackets.pointee = 0
        return StreamConvertingServicesError_NoEnoughData
    }
    
    // calculate maximum packet size and allocate buffer
    if converter.packetBuffer == nil {
        var maxPacketSize: UInt32 = 0
        maxPacketSize = converter.parser?.packSizeUpperBound ?? maxPacketSize
        maxPacketSize = converter.parser?.maximumPacketSize ?? maxPacketSize
        maxPacketSize = maxPacketSize == 0 ? 1024 * 1024 : maxPacketSize
        converter.packetBuffer = UnsafeMutableRawPointer.allocate(byteCount: Int(maxPacketSize), alignment: 0)
    }
    
    // copy packet bytes
    let packet = converter.parser!.parsedPackets[Int(converter.readOffset)]
    let packetSize = packet.packetData.count
    
    packet.packetData.withUnsafeBytes({ converter.packetBuffer!.copyMemory(from: $0.baseAddress!, byteCount: packetSize) })
    
    ioData.pointee.mNumberBuffers = 1
    ioData.pointee.mBuffers.mData = converter.packetBuffer
    ioData.pointee.mBuffers.mDataByteSize = UInt32(packetSize)
    ioData.pointee.mBuffers.mNumberChannels = srcFmt.streamDescription.pointee.mChannelsPerFrame
    

    // copy packet description
    if let packetDesc = packet.packetDesc {
        if converter.packetDescBuffer == nil {
            converter.packetDescBuffer = UnsafeMutablePointer<AudioStreamPacketDescription>.allocate(capacity: 1)
        }
        converter.packetDescBuffer?.pointee.mStartOffset = 0
        converter.packetDescBuffer?.pointee.mDataByteSize = packetDesc.mDataByteSize
        converter.packetDescBuffer?.pointee.mVariableFramesInPacket = packetDesc.mVariableFramesInPacket
        outDataPacketDescription?.pointee = converter.packetDescBuffer
    }
    
    os_log(.debug, log: converter.logger, "reading packet: %i, packet size: %i, variable frames in packet: %i", converter.readOffset, packetSize, packet.packetDesc?.mVariableFramesInPacket ?? 0)
    
    converter.readOffset += 1
    ioNumberDataPackets.pointee = 1
   
    return noErr
}
