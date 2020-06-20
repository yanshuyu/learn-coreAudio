import Foundation
import AVFoundation
import AudioToolbox
import os.log



public class StreamParsingServices: NSObject, ParsingServices {
    deinit {
        if let magicCookieData = self.magicCookieData {
            magicCookieData.data?.deallocate()
        }
        if let fileStream = self.streamID {
            AudioFileStreamClose(fileStream)
        }
    }
    
    fileprivate var logger = OSLog(subsystem: "com.audioStreamEngine.sy", category: "parsing")
    
    public var dataFormat: AVAudioFormat?
    
    public var dataByteCount: UInt64?
    
    public var dataPacketCount: UInt64?
    
    public var maximumPacketSize: UInt32?
    
    public var packSizeUpperBound: UInt32?
    
    public var magicCookieData: (data: UnsafeRawPointer?, size: Int)?
    
    public var channelLayout: AVAudioChannelLayout?
    
    public var isReadyToProducePacket: Bool = false
    
    public var parsedPackets: [(packetData: Data, packetDesc: AudioStreamPacketDescription?)] = []
    
    fileprivate var streamID: AudioFileStreamID?
    
    public func parseData(_ data: Data) throws {
        if self.streamID == nil {
            let clientData = Unmanaged.passUnretained(self).toOpaque()
            let result = AudioFileStreamOpen(clientData,
                                             streamPropertyListenerProc(_:_:_:_:),
                                             streamPacketsProc(_:_:_:_:_:),
                                             kAudioFileMP3Type,
                                             &self.streamID)
            guard result == noErr else {
    
                os_log(.error,log: self.logger, "parser can't open stream, error code: %i", result)
                throw ParsingError.canNotOpenStream(result)
            }
        }
        
        
        try data.withUnsafeBytes { (bytes) -> Void in
            let result = AudioFileStreamParseBytes(self.streamID!, UInt32(data.count), bytes.baseAddress, [])
            guard result == noErr else {
                switch result {
                    case kAudioFileStreamError_UnsupportedFileType:
                        os_log(.error, log: self.logger, "parser got kAudioFileStreamError_UnsupportedFileType error")
                        throw ParsingError.unsupportedFileType
                    
                    case kAudioFileStreamError_UnsupportedDataFormat:
                        os_log(.error, log: self.logger, "parser got kAudioFileStreamError_UnsupportedDataFormat error")
                        throw ParsingError.unsupportedDataFormat
                    
                    case kAudioFileStreamError_InvalidFile:
                        os_log(.error, log: self.logger, "parser got kAudioFileStreamError_InvalidFile error")
                        throw ParsingError.invalidFile
                    
                    case kAudioFileStreamError_DataUnavailable:
                        os_log(.error, log: self.logger, "parser got kAudioFileStreamError_DataUnavailable error")
                        throw ParsingError.dataUnavailable
                    
                    default:
                        os_log(.error, log: self.logger, "parser got os error: %i", result)
                        throw ParsingError.otherError(result)
                }
            }
        }
    }
    
    public func timeIntervalForFrameTime(_ frame: AVAudioFramePosition) -> TimeInterval? {
        guard let totalFrameCount = self.dataFrameCount, let duration = self.duration else {
            return nil
        }
        
        let ratio = Double(frame) / Double(totalFrameCount)
        return duration * ratio
    }
    
    public func frameTimeForTimeInterval(_ time: TimeInterval) -> AVAudioFramePosition? {
        guard let totalFrameCount = self.dataFrameCount, let duration = self.duration else {
            return nil
        }
        let ratio = time / duration
        return AVAudioFramePosition(Double(totalFrameCount) * ratio)
    }
    
    public func packetForTimeInterval(_ time: TimeInterval) -> AVAudioPacketCount? {
        if let frames = frameTimeForTimeInterval(time), let dataFormat = self.dataFormat, let totalPackCount = self.dataPacketCount {
            let packetIdx = min(max(Int64(0), frames / Int64(dataFormat.streamDescription.pointee.mFramesPerPacket)), Int64(totalPackCount))
            return AVAudioPacketCount(packetIdx)
        }
        return nil
    }
}


fileprivate func streamPropertyListenerProc(_ inClientData: UnsafeMutableRawPointer,
                                        _ inAudioFileStream: AudioFileStreamID,
                                        _ inPropertyID: AudioFileStreamPropertyID,
                                        _ ioFlags: UnsafeMutablePointer<AudioFileStreamPropertyFlags>) {
let streamParser = Unmanaged<StreamParsingServices>.fromOpaque(inClientData).takeUnretainedValue()
switch inPropertyID {
    case kAudioFileStreamProperty_DataFormat:
        var fmt = AudioStreamBasicDescription()
        let result = getFileStreamPropertyValue(&fmt, streamID: inAudioFileStream, propertyID: inPropertyID)
        if noErr == result {
            streamParser.dataFormat = AVAudioFormat(streamDescription: &fmt)
            os_log(.debug, log: streamParser.logger, "parser got stream data format: %@", fmt.debugDescription)
        } else {
            os_log(.error, log: streamParser.logger, "[%@-%@-%i] failed to parsing stream data format, error: %i", #file, #function, #line, result)
        }
        break
    
    case kAudioFileStreamProperty_AudioDataByteCount:
        var dataByteCount: UInt64 = 0
        let result = getFileStreamPropertyValue(&dataByteCount, streamID: inAudioFileStream, propertyID: inPropertyID)
        if noErr == result {
            streamParser.dataByteCount = dataByteCount
            os_log(.debug, log: streamParser.logger, "parser got stream data byte count: %i", dataByteCount)
        } else {
            os_log(.error, log: streamParser.logger, "[%@-%@-%i] failed to parsing stream data byte count, error: %i", #file, #function, #line, result)
        }
        break
    
    case kAudioFileStreamProperty_AudioDataPacketCount:
        var dataPackCount: UInt64 = 0
        let result = getFileStreamPropertyValue(&dataPackCount, streamID: inAudioFileStream, propertyID: inPropertyID)
        if noErr == result {
            streamParser.dataPacketCount = dataPackCount
            os_log(.debug, log: streamParser.logger, "parser got stream data packet count: %i", dataPackCount)
        } else {
            os_log(.error, log: streamParser.logger, "[%@-%@-%i] failed to parsing stream data packet count, error: %i", #file, #function, #line, result)
        }
        break
    
    case kAudioFileStreamProperty_MaximumPacketSize:
        var maxPackSize: UInt32 = 0
        let result = getFileStreamPropertyValue(&maxPackSize, streamID: inAudioFileStream, propertyID: inPropertyID)
        if noErr ==  result {
            streamParser.maximumPacketSize = maxPackSize
            os_log(.debug, log: streamParser.logger, "parser get stream data maximum packet size: %i", maxPackSize)
        } else {
            os_log(.error, log: streamParser.logger, "[%@-%@-%i] failed to parsing stream data maximum packet size, error: %i", #file, #function, #line, result)
        }
        break
    
    case kAudioFileStreamProperty_PacketSizeUpperBound:
        var packSizeUpperBound: UInt32 = 0
        let result = getFileStreamPropertyValue(&packSizeUpperBound, streamID: inAudioFileStream, propertyID: inPropertyID)
        if noErr == result {
            streamParser.packSizeUpperBound = packSizeUpperBound
            os_log(.debug, log: streamParser.logger, "parser got stream data packet size upper bound: %i", packSizeUpperBound)
        } else {
            os_log(.error, log: streamParser.logger, "[%@-%@-%i] failed to parsing stream data packet size upper bound, error: %i", #file, #function, #line, result)
        }
        break
    
    case kAudioFileStreamProperty_MagicCookieData:
        var dataSize: UInt32 = 0
        var result = AudioFileStreamGetPropertyInfo(inAudioFileStream, inPropertyID, &dataSize, nil)
        if noErr == result {
            let magicCookieData = UnsafeMutableRawPointer.allocate(byteCount: Int(dataSize), alignment: 0)
            result = AudioFileStreamGetProperty(inAudioFileStream, inPropertyID, &dataSize, magicCookieData)
            if noErr == result {
                streamParser.magicCookieData = (data: UnsafeRawPointer(magicCookieData), size: Int(dataSize))
                os_log(.debug, log: streamParser.logger, "parser got stream magic cookie data, size: %i", dataSize)
            } else {
                magicCookieData.deallocate()
            }
        }
        
        if result != noErr {
            os_log(.error, log: streamParser.logger, "[%@-%@-%i] failed to parsing stream magic cookie data, error: %i", #file, #function, #line, result)
        }
        break
    
    case kAudioFileStreamProperty_ChannelLayout:
        var channelLayout = AudioChannelLayout()
        let result = getFileStreamPropertyValue(&channelLayout, streamID: inAudioFileStream, propertyID: inPropertyID)
        if noErr == result {
            streamParser.channelLayout = AVAudioChannelLayout(layout: &channelLayout)
            os_log(.debug, log: streamParser.logger, "parser got stream channel layout")
        } else {
            os_log(.error, log: streamParser.logger, "[%@-%@-%i] failed to parsing stream channel layout, error: %i", #file, #function, #line, result)
        }
        break
    
    case kAudioFileStreamProperty_ReadyToProducePackets:
        var isReady: UInt32 = 0
        let result = getFileStreamPropertyValue(&isReady, streamID: inAudioFileStream, propertyID: inPropertyID)
        if result == noErr {
            streamParser.isReadyToProducePacket = isReady != 0
            os_log(.debug, log: streamParser.logger, "parser got stream ready to produce packet: %i", isReady)
        } else {
            os_log(.error, log: streamParser.logger, "[%@-%@-%i] failed to parsing stream ready to produce packet, error: %i", #file, #function, #line, result)
        }
        break
    
    default:
        os_log(.debug, log: streamParser.logger, "parser got file stream property: %@", inPropertyID.description)
        break
}

}


fileprivate func streamPacketsProc(_ inClientData: UnsafeMutableRawPointer,
                                   _ inNumberBytes: UInt32,
                                   _ inNumberPackets: UInt32,
                                   _ inInputData: UnsafeRawPointer,
                                   _ inPacketDescriptions: UnsafeMutablePointer<AudioStreamPacketDescription>) {
    let streamParser = Unmanaged<StreamParsingServices>.fromOpaque(inClientData).takeUnretainedValue()
    let inPacketDescriptionsOptional: UnsafeMutablePointer<AudioStreamPacketDescription>? = inPacketDescriptions
    
    if let inPacketDescriptionsUnwrap = inPacketDescriptionsOptional {
        for i in 0..<inNumberPackets {
            let packDesc = inPacketDescriptionsUnwrap.advanced(by: Int(i)).pointee
            let packData = Data(bytes: inInputData.advanced(by: Int(packDesc.mStartOffset)), count: Int(packDesc.mDataByteSize))
            streamParser.parsedPackets.append((packetData: packData, packetDesc: packDesc))
        }
    } else {
        guard let streamFmt = streamParser.dataFormat?.streamDescription.pointee else {
            os_log(.error, log: streamParser.logger, "[%@-%@-%@] parser failed due to missing data format", #file, #function, #line)
            return
        }
        
        let packSize = streamFmt.mBytesPerPacket
        for i in 0 ..< inNumberPackets {
            let packOffset = i * packSize
            let packData = Data(bytes: inInputData.advanced(by: Int(packOffset)), count: Int(packSize))
            streamParser.parsedPackets.append((packetData: packData, packetDesc: nil))
        }
        
    }
    
    os_log(.debug, log: streamParser.logger, "parser got %i packets, total parsed packets: %i",inNumberPackets, streamParser.parsedPackets.count)
}

@discardableResult
fileprivate func getFileStreamPropertyValue<T>(_ value: inout T, streamID: AudioFileStreamID, propertyID: AudioFileStreamPropertyID) -> OSStatus {
    var result = noErr
    var propertySize: UInt32 = 0
    result = AudioFileStreamGetPropertyInfo(streamID, propertyID, &propertySize, nil)
   
    guard result == noErr else {
        return result
    }
    
    return AudioFileStreamGetProperty(streamID, propertyID, &propertySize, &value)
}

