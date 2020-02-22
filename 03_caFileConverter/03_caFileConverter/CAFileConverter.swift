//
//  CAFileConverter.swift
//  03_caFileConverter
//
//  Created by sy on 2020/2/20.
//  Copyright © 2020 sy. All rights reserved.
//

import Foundation
import AudioToolbox

class CAFileConverter {
    static let KConvertionDoneNotification = Notification.Name("CAFileConverter.KConvertionDoneNotification")
    static let KConvertionCanneledNotification = Notification.Name("CAFileConverter.KConvertionCanneledNotification")
    static let KConvertionErrorNotification = Notification.Name("CAFileConverter.KConvertionErrorNotification")
    static let KConvertionInterruptionNotification = Notification.Name("CAFileConverter.KConvertionInterruptionNotification")

    enum CAFileConverterError: Error {
        case FilePermissionError
        case UnsupportedFileTypeError
        case UnsupportedDataFormatError
        case OtherError
    }
    
    private class ConvertOperation: Operation {
        weak var converter: CAFileConverter?
        
        init(converter: CAFileConverter?) {
            self.converter = converter
        }
        
        override func main() {
            guard let cvt = self.converter else {
                return
            }
            
            if self.isCancelled {
                cvt.isCanceled = true
                return
            }

            while true {
                if self.isCancelled {
                    cvt.isCanceled = true
                    return
                }
                var ioNumberPack: UInt32 = UInt32(cvt.converterUserData.dstBufferSizeInPack)
                var outBufferList = AudioBufferList()
                outBufferList.mNumberBuffers = 1
                outBufferList.mBuffers.mData = cvt.converterUserData.dstPacksBuffer
                outBufferList.mBuffers.mDataByteSize = UInt32(cvt.converterUserData.dstBufferSizeInByte)
                outBufferList.mBuffers.mNumberChannels = cvt.converterUserData.dstFmt.mChannelsPerFrame
                
                var result = AudioConverterFillComplexBuffer(cvt.converter!,
                                                CAFileConverter.inputDataProc,
                                                &cvt.converterUserData,
                                                &ioNumberPack,
                                                &outBufferList,
                                                cvt.converterUserData.dstPacksDescBuffer)
        
                // handle interruption
//                if result == kAudioConverterErr_HardwareInUse {
//
//                }
                
                if ioNumberPack == 0 {
                    result = noErr
                    cvt.isDone = true
                    return
                }
                
                if result != noErr {
                    cvt.error = result
                    return
                }
                
                // write converted packs to dst file
                let writeBytes = outBufferList.mBuffers.mDataByteSize
                result = AudioFileWritePackets(cvt.converterUserData.dstFileID!,
                                      false,
                                      writeBytes,
                                      cvt.converterUserData.dstPacksDescBuffer,
                                      cvt.converterUserData.dstFileWriteIndex,
                                      &ioNumberPack,
                                      outBufferList.mBuffers.mData!)
                if result == noErr {
                    cvt.converterUserData.dstFileWriteIndex += Int64(ioNumberPack)
                    cvt.debugLogger?.write("[Convertion CB] write \(ioNumberPack) packs success, total packs: \(cvt.converterUserData.dstFileWriteIndex)\n")
                } else {
                    cvt.debugLogger?.write("[Convertion CB] try to write \(ioNumberPack) packs at index \(cvt.converterUserData.dstFileWriteIndex) failed.\n")
                    cvt.error = result
                    return
                }
                
            }
        }
    }
    
    private class ConverterUserData {
        var srcFmt = AudioStreamBasicDescription()
        var srcFileID: AudioFileID?
        var srcFileReadIndex: Int64 = 0
        var srcPacksBuffer: UnsafeMutableRawPointer?
        var srcPacksDescBuffer: UnsafeMutablePointer<AudioStreamPacketDescription>?
        var srcBufferSizeInPack: Int64 = 0
        var srcBufferSizeInByte: Int64 = 0
        
        var dstFmt = AudioStreamBasicDescription()
        var dstFileID: AudioFileID?
        var dstFileWriteIndex: Int64 = 0
        var dstPacksBuffer: UnsafeMutableRawPointer?
        var dstPacksDescBuffer: UnsafeMutablePointer<AudioStreamPacketDescription>?
        var dstBufferSizeInPack: Int64 = 0
        var dstBufferSizeInByte: Int64 = 0
        
        var debugLogger: TextLogger?
        
        deinit {
            dispose()
        }
        
        func dispose() {
            if let _ = self.srcFileID {
                AudioFileClose(self.srcFileID!)
                self.srcFileID = nil
            }
            
            if let _ = self.dstFileID {
                AudioFileClose(self.dstFileID!)
                self.dstFileID = nil
            }
            
            self.srcPacksBuffer?.deallocate()
            self.srcPacksBuffer = nil
            self.srcPacksDescBuffer?.deallocate()
            self.srcPacksDescBuffer = nil
            self.srcBufferSizeInPack = 0
            self.srcBufferSizeInByte = 0
            self.srcFmt = AudioStreamBasicDescription()
            
            self.dstPacksBuffer?.deallocate()
            self.dstPacksBuffer = nil
            self.dstPacksDescBuffer?.deallocate()
            self.dstPacksDescBuffer = nil
            self.dstBufferSizeInPack = 0
            self.dstBufferSizeInByte = 0
            self.dstFmt = AudioStreamBasicDescription()
        }
    }
    
    private var dstURL: URL
    private var converter: AudioConverterRef?
    private var converterUserData = ConverterUserData()
    private var isPrepared = false
    
    private(set) var canResumeFromInterruption = true
    private(set) var isCanceled = false {
        didSet {
            if self.isCanceled {
                NotificationCenter.default.post(name: CAFileConverter.KConvertionCanneledNotification, object: self)
                debugLogger?.write("convertion is cancelled.\n")
            }
        }
    }
    private(set) var isDone = false {
        didSet {
            if self.isDone {
                pullMagicCookieData(from: self.converter!, to: self.converterUserData.dstFileID!)
                NotificationCenter.default.post(name: CAFileConverter.KConvertionDoneNotification, object: self)
                debugLogger?.write("concertion is done.\n")
            }
        }
    }
    private var currentConvertOp: ConvertOperation?
    private var error: OSStatus = noErr {
        didSet {
            if self.error != noErr {
                NotificationCenter.default.post(name: CAFileConverter.KConvertionErrorNotification,
                                                object: self,
                                                userInfo: ["code": self.error])
                debugLogger?.write("convertion error: \(self.error)\n")
            }
        }
    }
    private var debugLogger: TextLogger?
    
    
    //
    //MARK: - constructor & destructor
    //
    init(srcURL: URL, dstURL: URL, dstFormat: AudioFormatID, sampleRate: Float64 = 0) throws {
        self.dstURL = dstURL
        self.debugLogger = createLogFileAlongside(with: dstURL)
        self.converterUserData.debugLogger = self.debugLogger
        
        // open source file to get src format
        if let error = callSuccess(withCode: AudioFileOpenURL(srcURL as CFURL,
                         .readPermission,
                         0,
                         &self.converterUserData.srcFileID)) {
            throw error
        }
        
        var propertySize = UInt32(MemoryLayout.size(ofValue: self.converterUserData.srcFmt))
        if noErr != AudioFileGetProperty(self.converterUserData.srcFileID!,
                                         kAudioFilePropertyDataFormat,
                                         &propertySize,
                                         &self.converterUserData.srcFmt) {
            cleanUp()
            throw CAFileConverterError.UnsupportedDataFormatError
        }
        
        // config dst format
        self.converterUserData.dstFmt.mFormatID = dstFormat
        self.converterUserData.dstFmt.mSampleRate = sampleRate == 0 ? self.converterUserData.srcFmt.mSampleRate : sampleRate
        self.converterUserData.dstFmt.mChannelsPerFrame = self.converterUserData.srcFmt.mChannelsPerFrame
        
        if dstFormat == kAudioFormatLinearPCM {
            self.converterUserData.dstFmt.mBitsPerChannel = 16
            self.converterUserData.dstFmt.mBytesPerFrame = self.converterUserData.dstFmt.mBitsPerChannel * self.converterUserData.dstFmt.mChannelsPerFrame / 8
            self.converterUserData.dstFmt.mFramesPerPacket = 1
            self.converterUserData.dstFmt.mBytesPerPacket = self.converterUserData.dstFmt.mBytesPerFrame
            self.converterUserData.dstFmt.mFormatFlags = kAudioFormatFlagIsBigEndian | kAudioFormatFlagIsPacked | kAudioFormatFlagIsSignedInteger
        } else { // compressioned fmt
            if self.converterUserData.dstFmt.mFormatID == kAudioFormatiLBC {
                self.converterUserData.dstFmt.mChannelsPerFrame = 1
            }
            propertySize = UInt32(MemoryLayout.size(ofValue: self.converterUserData.dstFmt))
            if noErr != AudioFormatGetProperty(kAudioFormatProperty_FormatInfo,
                                   0,
                                   nil,
                                   &propertySize,
                                   &self.converterUserData.dstFmt) {
                cleanUp()
                throw CAFileConverterError.UnsupportedDataFormatError
            }
        }

        if let error = callSuccess(withCode: AudioConverterNew(&self.converterUserData.srcFmt,
                                                               &self.converterUserData.dstFmt,
                                                               &self.converter)) {
            cleanUp()
            throw error
        }
        
        // get converter's src format and dst format
        propertySize = UInt32(MemoryLayout.size(ofValue: self.converterUserData.srcFmt))
        AudioConverterGetProperty(self.converter!,
                                  kAudioConverterCurrentInputStreamDescription,
                                  &propertySize,
                                  &self.converterUserData.srcFmt)
        propertySize = UInt32(MemoryLayout.size(ofValue: self.converterUserData.dstFmt))
        AudioConverterGetProperty(self.converter!,
                                  kAudioConverterCurrentOutputStreamDescription,
                                  &propertySize,
                                  &self.converterUserData.dstFmt)

        // can resume from interruption?
        var canResume: UInt32 = 1
        propertySize = UInt32(MemoryLayout.size(ofValue: canResume))
//        AudioConverterGetProperty(self.converter!,
//                                  kAudioConverterPropertyCanResumeFromInterruption,
//                                  &propertySize,
//                                  &canResume)
        self.canResumeFromInterruption = canResume != 0
       
        self.debugLogger?.write("converter init success, src format: {\t\(self.converterUserData.srcFmt)\t}\n\tdst format: {\t\(self.converterUserData.dstFmt)\t}\n")
    }
    
    deinit {
        cleanUp()
    }
    
    public static var inputDataProc: AudioConverterComplexInputDataProc = { (inConverter, ioNumberDataPackets, ioDataBUfferList, outDataPacketDescription, inUserData) -> OSStatus in
        let cvtSettings = inUserData!.bindMemory(to: ConverterUserData.self, capacity: 1).pointee
        
        if ioNumberDataPackets.pointee > cvtSettings.srcBufferSizeInPack {
            ioNumberDataPackets.pointee = UInt32(cvtSettings.srcBufferSizeInPack)
        }
        
        var ioNumberBytes = UInt32(cvtSettings.srcBufferSizeInByte)
        var result = AudioFileReadPacketData(cvtSettings.srcFileID!,
                                             false,
                                             &ioNumberBytes,
                                             cvtSettings.srcPacksDescBuffer,
                                             cvtSettings.srcFileReadIndex,
                                             ioNumberDataPackets,
                                             cvtSettings.srcPacksBuffer)
        if result == eofErr {
            result = noErr
        }
        
        if result != noErr {
            return result
        }
        
        ioDataBUfferList.pointee.mNumberBuffers = 1
        ioDataBUfferList.pointee.mBuffers.mData = cvtSettings.srcPacksBuffer
        ioDataBUfferList.pointee.mBuffers.mDataByteSize = ioNumberBytes
        ioDataBUfferList.pointee.mBuffers.mNumberChannels = cvtSettings.srcFmt.mChannelsPerFrame
        if let packDesc = outDataPacketDescription {
            packDesc.pointee = cvtSettings.srcPacksDescBuffer
        }
        
        cvtSettings.srcFileReadIndex += Int64(ioNumberDataPackets.pointee)
        
        return noErr
    }
    
    //
    //MARK: - Converter controll API
    //
    @discardableResult
    public func prepareToConvert() -> Bool {
        if !self.isPrepared {
            // copy src file magic cookie if any
            let copyInputMagicCookieSuccess = pushMagicCookieData(from: self.converterUserData.srcFileID!, to: self.converter!)
            debugLogger?.write("copyInputMagicCookieSuccess: \(copyInputMagicCookieSuccess).\n")
            
            // copy channel layout if any
            let copyInputChannelLayoutSuccess = pushChannelLayout(from: self.converterUserData.srcFileID!, to: self.converter!)
            debugLogger?.write("copyInputChannelLayoutSuccess: \(copyInputChannelLayoutSuccess).\n")
            
            // create dst file for writting converted data
            let createDstFileSuccess = createAudioFile(at: self.dstURL)
            debugLogger?.write("createDstFileSuccess: \(createDstFileSuccess).\n")
            
            // copy magic cookie from converter to dst file if any
            let copyOutputMagicCookieSuccess = pullMagicCookieData(from: self.converter!, to: self.converterUserData.dstFileID!)
            debugLogger?.write("copyOutputMagicCookieSuccess: \(copyOutputMagicCookieSuccess).\n")
            
            let copyOutputLayoutChannelSuccess = pullChannelLayout(from: self.converter!, to: self.converterUserData.dstFileID!)
            debugLogger?.write("copyOutputLayoutChannelSuccess: \(copyOutputLayoutChannelSuccess).\n")
            
            // allocate input/output buffers
            var allocateSrcBufferSuccess = true
            if self.converterUserData.srcPacksBuffer == nil {
                var maxPackSize: UInt32 = 0
                var propertySize = UInt32(MemoryLayout.size(ofValue: maxPackSize))
                if noErr != AudioFileGetProperty(self.converterUserData.srcFileID!,
                                                 kAudioFilePropertyPacketSizeUpperBound,
                                                 &propertySize,
                                                 &maxPackSize) {
                    allocateSrcBufferSuccess = false
                } else {
                    computePacketsBuffer(iFormat: self.converterUserData.srcFmt, iMaxPackSize: maxPackSize, iDuration: 0.5, oBufferSize: &self.converterUserData.srcBufferSizeInByte, oPackCount: &self.converterUserData.srcBufferSizeInPack)
                    self.converterUserData.srcPacksBuffer = UnsafeMutableRawPointer.allocate(byteCount: Int(self.converterUserData.srcBufferSizeInByte), alignment: 0)
                    if self.converterUserData.srcFmt.mBytesPerPacket == 0 { // VBR format
                        self.converterUserData.srcPacksDescBuffer = UnsafeMutablePointer<AudioStreamPacketDescription>.allocate(capacity: Int(self.converterUserData.srcBufferSizeInPack))
                    }
                }
            }
            debugLogger?.write("allocateSrcBufferSuccess: \(allocateSrcBufferSuccess).\n")
            if allocateSrcBufferSuccess {
                debugLogger?.write("srcBufferSizeInByte: \(self.converterUserData.srcBufferSizeInByte), srcBufferSizeInPack: \(self.converterUserData.srcBufferSizeInPack).\n")
            }
            
            var allocateDstBufferSuccess = true
            if self.converterUserData.dstPacksBuffer == nil {
                var maxPackSize: UInt32 = 0
                var propertySize = UInt32(MemoryLayout.size(ofValue: maxPackSize))
                if noErr != AudioConverterGetProperty(self.converter!,
                                                      kAudioConverterPropertyMaximumOutputPacketSize,
                                                      &propertySize,
                                                      &maxPackSize) {
                    allocateDstBufferSuccess = false
                } else {
                    computePacketsBuffer(iFormat: self.converterUserData.dstFmt, iMaxPackSize: maxPackSize, iDuration: 0.5, oBufferSize: &self.converterUserData.dstBufferSizeInByte, oPackCount: &self.converterUserData.dstBufferSizeInPack)
                    self.converterUserData.dstPacksBuffer = UnsafeMutableRawPointer.allocate(byteCount: Int(self.converterUserData.dstBufferSizeInByte), alignment: 0)
                    if self.converterUserData.dstFmt.mBytesPerPacket == 0 { // VBR format
                        self.converterUserData.dstPacksDescBuffer = UnsafeMutablePointer<AudioStreamPacketDescription>.allocate(capacity: Int(self.converterUserData.dstBufferSizeInPack))
                    }
                }
            }
            debugLogger?.write("allocateDstBufferSuccess: \(allocateDstBufferSuccess).\n")
            if allocateDstBufferSuccess {
                debugLogger?.write("dstBufferSizeInByte: \(self.converterUserData.dstBufferSizeInByte), dstBufferSizeInPack: \(self.converterUserData.dstBufferSizeInPack).\n")
            }
            
            self.isPrepared = copyInputMagicCookieSuccess
                && copyInputChannelLayoutSuccess
                && createDstFileSuccess
                && copyOutputMagicCookieSuccess
                && copyOutputLayoutChannelSuccess
                && allocateSrcBufferSuccess
                && allocateDstBufferSuccess
            
            debugLogger?.write("prepare to convert success: \(self.isPrepared).\n")
        }
        
        return self.isPrepared
    }
    
    @discardableResult
    public func start(using queue: OperationQueue) -> Bool {
        if !self.isPrepared {
            prepareToConvert()
        }
        
        if self.isPrepared {
            let convertOp = ConvertOperation(converter: self)
            queue.addOperation(convertOp)
            self.currentConvertOp = convertOp
        }
        
        return self.isPrepared
    }
    
    
    public func stop() {
        if let _ = self.currentConvertOp {
            self.currentConvertOp!.cancel()
            self.currentConvertOp = nil
        }
    }
    
    
    public class func avalibleEncoderFormatIDs() -> [AudioFormatID] {
        var fmtIDArraySize: UInt32 = 0
        if noErr == AudioFormatGetPropertyInfo(kAudioFormatProperty_EncodeFormatIDs,
                                   0,
                                   nil,
                                   &fmtIDArraySize) {
            var fmtIDArray = [AudioFormatID](repeating: 0, count: Int(fmtIDArraySize) / MemoryLayout<AudioFormatID>.size)
            if noErr == AudioFormatGetProperty(kAudioFormatProperty_EncodeFormatIDs,
                                               0,
                                               nil,
                                               &fmtIDArraySize,
                                               &fmtIDArray) {
                return fmtIDArray
            }
        }
        return []
    }
    
    public class func avalibleDecoderFormatIDs() -> [AudioFormatID] {
        var fmtIDArraySize: UInt32 = 0
        if noErr == AudioFormatGetPropertyInfo(kAudioFormatProperty_DecodeFormatIDs,
                                               0,
                                               nil,
                                               &fmtIDArraySize) {
            var fmtIDArray = [AudioFormatID](repeating: 0, count: Int(fmtIDArraySize) / MemoryLayout<AudioFormatID>.size)
            if noErr == AudioFormatGetProperty(kAudioFormatProperty_DecodeFormatIDs,
                                               0,
                                               nil,
                                               &fmtIDArraySize,
                                               &fmtIDArray) {
                return fmtIDArray
            }
        }
        return []
    }
    
    public class func isValideConvert(from srcFmt: AudioFormatID, to dstFmt: AudioFormatID) -> Bool {
        let encoderFmtIDs = avalibleEncoderFormatIDs()
        let decoderFmtIDs = avalibleDecoderFormatIDs()
        return decoderFmtIDs.contains(srcFmt) && encoderFmtIDs.contains(dstFmt)
    }
    
    //
    //MARK: - Helper
    //
    private func callSuccess(withCode: OSStatus) -> CAFileConverterError? {
        guard withCode != noErr else {
            return nil
        }
        print("error code: \(withCode)")
        switch withCode {
        case kAudioFileUnsupportedFileTypeError:
            return .UnsupportedFileTypeError
        case kAudioFileUnsupportedDataFormatError, kAudioConverterErr_FormatNotSupported, kAudioConverterErr_OperationNotSupported:
            return .UnsupportedDataFormatError
        case kAudioFilePermissionsError:
            return .FilePermissionError
            
        default:
            return .OtherError
        }
    }
    
    
    private func pushMagicCookieData(from file: AudioFileID, to converter: AudioConverterRef) -> Bool {
        var magicCookieDataSize: UInt32 = 0
        if noErr == AudioFileGetPropertyInfo(file,
                                             kAudioFilePropertyMagicCookieData,
                                             &magicCookieDataSize,
                                             nil) && magicCookieDataSize > 0 {
            var magicCookieData  = UnsafeMutableRawPointer.allocate(byteCount: Int(magicCookieDataSize), alignment: 0)
            defer {
                magicCookieData.deallocate()
            }
            
            if noErr == AudioFileGetProperty(file,
                                             kAudioFilePropertyMagicCookieData,
                                             &magicCookieDataSize,
                                             magicCookieData) {
                let result = AudioConverterSetProperty(converter,
                                                       kAudioConverterDecompressionMagicCookie,
                                                       magicCookieDataSize,
                                                       magicCookieData)
                return result == noErr
            }
            
            return false
        }
        
        return true
    }
    
    @discardableResult
    private func pullMagicCookieData(from converter: AudioConverterRef, to file: AudioFileID) -> Bool {
        var magicCookieSize: UInt32 = 0
        if noErr == AudioConverterGetPropertyInfo(converter,
                                                  kAudioConverterCompressionMagicCookie,
                                                  &magicCookieSize,
                                                  nil) && magicCookieSize > 0 {
            var magicCookie = UnsafeMutableRawPointer.allocate(byteCount: Int(magicCookieSize), alignment: 0)
            defer {
                magicCookie.deallocate()
            }
            
            if noErr == AudioConverterGetProperty(converter,
                                                  kAudioConverterCompressionMagicCookie,
                                                  &magicCookieSize,
                                                  magicCookie) {
                let result = AudioFileSetProperty(file,
                                                  kAudioFilePropertyMagicCookieData,
                                                  magicCookieSize,
                                                  magicCookie)
                return result == noErr
            }
            
            return false
        }
        return true
    }
    
    private func pushChannelLayout(from file: AudioFileID, to converter: AudioConverterRef) -> Bool {
        var channelLayoutSize: UInt32 = 0
        if noErr == AudioFileGetPropertyInfo(file,
                                 kAudioFilePropertyChannelLayout,
                                 &channelLayoutSize,
                                 nil) && channelLayoutSize > 0 {
            var channelLayout = UnsafeMutableRawPointer.allocate(byteCount: Int(channelLayoutSize), alignment: 0)
            defer {
                channelLayout.deallocate()
            }
            
            if noErr == AudioFileGetProperty(file,
                                             kAudioFilePropertyChannelLayout,
                                             &channelLayoutSize,
                                             channelLayout) {
                let result = AudioConverterSetProperty(converter,
                                                       kAudioConverterInputChannelLayout,
                                                       channelLayoutSize,
                                                       channelLayout)
                return result == noErr
            }
            
            return false
        }
        
        return true
    }
    
    private func pullChannelLayout(from converter: AudioConverterRef, to file: AudioFileID) -> Bool {
        var channelLayoutSize: UInt32 = 0
        if noErr ==  AudioConverterGetPropertyInfo(converter,
                                      kAudioConverterOutputChannelLayout,
                                      &channelLayoutSize,
                                      nil) && channelLayoutSize > 0 {
            var channelLayout = UnsafeMutableRawPointer.allocate(byteCount: Int(channelLayoutSize), alignment: 0)
            defer {
                channelLayout.deallocate()
            }
            
            if noErr == AudioConverterGetProperty(converter,
                                                  kAudioConverterOutputChannelLayout,
                                                  &channelLayoutSize,
                                                  channelLayout) {
                let result = AudioFileSetProperty(file,
                                                  kAudioFilePropertyChannelLayout,
                                                  channelLayoutSize,
                                                  channelLayout)
                return result == noErr
            }
            
            return false
        }
        return true
    }
    
    private func createAudioFile(at url: URL) -> Bool {
        if let fileTypeID = audioFileTypeID(with: url) {
            let result = AudioFileCreateWithURL(url as CFURL,
                                                fileTypeID,
                                                &self.converterUserData.dstFmt,
                                                [.eraseFile],
                                                &self.converterUserData.dstFileID)
            return result == noErr
        }
        return false
    }
    
    private func computePacketsBuffer(iFormat: AudioStreamBasicDescription, iMaxPackSize: UInt32, iDuration: Float64, oBufferSize: inout Int64, oPackCount: inout Int64) {
        let frameCount = Int64(iFormat.mSampleRate * iDuration)
        var packCount = frameCount
        var packSize = iFormat.mBytesPerPacket
        
        if iFormat.mFramesPerPacket > 0 {
            packCount = frameCount / Int64(iFormat.mFramesPerPacket)
        }
        
        if packSize == 0 {
            packSize = iMaxPackSize
        }
        
        oBufferSize = packCount * Int64(packSize)
        oPackCount = packCount
    }
    
    private func audioFileTypeID(with url: URL) -> AudioFileTypeID? {
         switch url.pathExtension {
         case "caf":
             return kAudioFileCAFType
         case "aac":
             return kAudioFileAAC_ADTSType
         case "mp3":
             return kAudioFileMP3Type
         case "flac":
             return kAudioFileFLACType
         case "wave":
             return kAudioFileWAVEType
         case "aif":
             return kAudioFileAIFFType
         case "m4a":
             return kAudioFileM4AType
         default:
             return nil
         }
     }
     
    
    private func cleanUp() {
        self.converterUserData.dispose()
        
        if let _ = self.converter {
            AudioConverterDispose(self.converter!)
            self.converter = nil
        }
        
    }
    
    
    private func createLogFileAlongside(with url: URL) -> TextLogger? {
        var pathComponents = url.pathComponents
        var dunmpFileName = pathComponents.removeLast()
        dunmpFileName.removeSubrange(dunmpFileName.lastIndex(of: ".")!..<dunmpFileName.endIndex)
        dunmpFileName.append("_dump.txt")
        pathComponents.append(dunmpFileName)
        let dumpFilePath = pathComponents.joined(separator: "/")
        return TextLogger(path: dumpFilePath)
    }
}


extension AudioStreamBasicDescription: CustomStringConvertible {
    public var description: String {
        var desc = ""
        desc += "formatId: \(self.mFormatID)\n"
        desc += "sampleRate: \(self.mSampleRate)\n"
        desc += "bitsPerChannel: \(self.mBitsPerChannel)\n"
        desc += "channelsPerFrame: \(self.mChannelsPerFrame)\n"
        desc += "bytesPerFrame: \(self.mBytesPerFrame)\n"
        desc += "framesPerPack: \(self.mFramesPerPacket)\n"
        desc += "bytesPerPack: \(self.mBytesPerPacket)"
        return desc
    }
}

