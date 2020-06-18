import Foundation
import AVFoundation
import AudioToolbox

public protocol ParsingServices: AnyObject {
    var dataFormat: AVAudioFormat? { get }
    var dataByteCount: UInt64? { get }
    var dataFrameCount: UInt64? { get }
    var dataPacketCount: UInt64? { get }
    var maximumPacketSize: UInt32? { get }
    var packSizeUpperBound: UInt32? { get }
    var magicCookieData: (data: UnsafeRawPointer?, size: Int)? { get }
    var channelLayout: AVAudioChannelLayout? { get }
    
    var isParsingCompeleted: Bool { get }
    var isReadyToProducePacket: Bool { get }
    var duration: TimeInterval? { get }
    var parsedPackets: [(packetData: Data, packetDesc: AudioStreamPacketDescription?)] { get }
    
    func parseData(_ data: Data) throws
}


extension ParsingServices {
    public var dataFrameCount: UInt64? {
        guard let fmt = self.dataFormat ,
            let totalPackets = self.dataPacketCount else {
            return nil
        }
        
        return UInt64(fmt.streamDescription.pointee.mFramesPerPacket) * totalPackets
    }
    
    public var duration: TimeInterval? {
        guard let fmt = self.dataFormat,
            let totalFrames = self.dataFrameCount else {
            return nil
        }
        
        return Double(totalFrames) / fmt.sampleRate
    }
    
    public var isParsingCompeleted: Bool {
        if let  totalPackCount = self.dataPacketCount {
            return self.parsedPackets.count >= totalPackCount
        }
        return false
    }
    
}
