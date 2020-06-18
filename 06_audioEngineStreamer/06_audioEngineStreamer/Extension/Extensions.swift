import Foundation
import AudioToolbox

extension AudioStreamBasicDescription: CustomDebugStringConvertible {
    public var debugDescription: String {
        let desc = """
        {\tformatID : \(self.mFormatID),
        sampleRate : \(self.mSampleRate)
        bitsPerChannel : \(self.mBitsPerChannel),
        channelsPerFrame : \(self.mChannelsPerFrame),
        bytesPerFrame : \(self.mBytesPerFrame),
        framePerPacket : \(self.mFramesPerPacket),
        bytesPerPacket : \(self.mBytesPerPacket)\t}
        """
        
        return desc
    }
}

extension AudioFileStreamPropertyID {
    public var description: String {
        switch self {
        case kAudioFileStreamProperty_ReadyToProducePackets:
            return "Ready to produce packets"
        case kAudioFileStreamProperty_FileFormat:
            return "File format"
        case kAudioFileStreamProperty_DataFormat:
            return "Data format"
        case kAudioFileStreamProperty_AudioDataByteCount:
            return "Byte count"
        case kAudioFileStreamProperty_AudioDataPacketCount:
            return "Packet count"
        case kAudioFileStreamProperty_DataOffset:
            return "Data offset"
        case kAudioFileStreamProperty_BitRate:
            return "Bit rate"
        case kAudioFileStreamProperty_FormatList:
            return "Format list"
        case kAudioFileStreamProperty_MagicCookieData:
            return "Magic cookie"
        case kAudioFileStreamProperty_MaximumPacketSize:
            return "Max packet size"
        case kAudioFileStreamProperty_ChannelLayout:
            return "Channel layout"
        case kAudioFileStreamProperty_PacketToFrame:
            return "Packet to frame"
        case kAudioFileStreamProperty_FrameToPacket:
            return "Frame to packet"
        case kAudioFileStreamProperty_PacketToByte:
            return "Packet to byte"
        case kAudioFileStreamProperty_ByteToPacket:
            return "Byte to packet"
        case kAudioFileStreamProperty_PacketTableInfo:
            return "Packet table"
        case kAudioFileStreamProperty_PacketSizeUpperBound:
            return "Packet size upper bound"
        case kAudioFileStreamProperty_AverageBytesPerPacket:
            return "Average bytes per packet"
        case kAudioFileStreamProperty_InfoDictionary:
            return "Info dictionary"
        default:
            return "Unknown"
        }
    }
}



func converterErrorStringDescription(_ status: OSStatus) -> String {
    switch status {
        case kAudioConverterErr_FormatNotSupported:
            return "Format not supported"
        case kAudioConverterErr_OperationNotSupported:
            return "Operation not supported"
        case kAudioConverterErr_PropertyNotSupported:
            return "Property not supported"
        case kAudioConverterErr_InvalidInputSize:
            return "Invalid input size"
        case kAudioConverterErr_InvalidOutputSize:
            return "Invalid output size"
        case kAudioConverterErr_BadPropertySizeError:
            return "Bad property size error"
        case kAudioConverterErr_RequiresPacketDescriptionsError:
            return "Requires packet descriptions"
        case kAudioConverterErr_InputSampleRateOutOfRange:
            return "Input sample rate out of range"
        case kAudioConverterErr_OutputSampleRateOutOfRange:
            return "Output sample rate out of range"
        #if os(iOS)
        case kAudioConverterErr_HardwareInUse:
            return "Hardware is in use"
        case kAudioConverterErr_NoHardwarePermission:
            return "No hardware permission"
        #endif
        default:
            return "Unspecified error"
    }
}
