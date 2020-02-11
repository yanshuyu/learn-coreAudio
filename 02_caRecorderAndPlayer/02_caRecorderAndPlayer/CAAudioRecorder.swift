//
//  CAAudioRecorder.swift
//  02_caRecorderAndPlayer
//
//  Created by sy on 2019/12/26.
//  Copyright © 2019 sy. All rights reserved.
//
import Foundation
import AudioToolbox
import AVFoundation

protocol CAAudioRecorderDelegate: AnyObject {
    func audioRecorder(_ recorder: CAAudioRecorder, prepareSuccess: Bool, error: CAAudioRecorder.CAAudioRecordeError?)
    func audioRecorder(_ recorder: CAAudioRecorder, startSucces: Bool, error: CAAudioRecorder.CAAudioRecordeError?)
    func audioRecorder(_ recorder: CAAudioRecorder, pauseSuccess: Bool, error: CAAudioRecorder.CAAudioRecordeError?)
    func addioRecorder(_ recorder: CAAudioRecorder, stopSuccess: Bool, error: CAAudioRecorder.CAAudioRecordeError?)
    func audioRecorder(_ recorder: CAAudioRecorder, finishSuccess: Bool, outputFileURL: URL?, error: CAAudioRecorder.CAAudioRecordeError?)
}


class CAAudioRecorder {
    public enum CAAudioRecordeError: Error {
        case dataFormatError(reason: String)
        case fileFormatError(reason: String)
        case codecError(reason: String)
        case hardwareError(reason: String)
        case bufferError(reason: String)
        case queueError(reason: String)
        case permissionError(reason: String)
        case unknowedError
    }
    
    private struct RecorderContext {
        var outputFileID: AudioFileID?
        var outputFileWriteIndex: Int64 = 0
        var isRecording: Bool = false
        
        // dumo info for debuging
        var dumpLogger: TextLogger?
    }

    public weak var delegate: CAAudioRecorderDelegate?
    
    private var audioQueue: AudioQueueRef?
    private let audioQueueBufferCount = 3    
    private var outputFileID: AudioFileID?
    private var outputFileURL: URL?
    private var recorderContext = RecorderContext()
    private var audioQueueCallback: AudioQueueInputCallback = { (inUserData, inAQ, inAQBuffer, inStartTime, inNumberASPD, inASPD) in
        let recorderContextPtr = inUserData!.bindMemory(to: RecorderContext.self, capacity: 1)
        guard let outputFileID = recorderContextPtr.pointee.outputFileID else {
            return
        }
        
        if recorderContextPtr.pointee.isRecording {
            if inNumberASPD > 0 {
                var ioNumberPacks = inNumberASPD
                let result = AudioFileWritePackets(outputFileID,
                                                   false,
                                                   inAQBuffer.pointee.mAudioDataByteSize,
                                                   inASPD,
                                                   recorderContextPtr.pointee.outputFileWriteIndex,
                                                   &ioNumberPacks,
                                                   inAQBuffer.pointee.mAudioData)
                if result == noErr {
                    recorderContextPtr.pointee.outputFileWriteIndex += Int64(ioNumberPacks)
                    recorderContextPtr.pointee.dumpLogger?.write("[audio queue callback] success written \(ioNumberPacks) audio packets, total written \(recorderContextPtr.pointee.outputFileWriteIndex) packets\n")
                } else {
                    recorderContextPtr.pointee.dumpLogger?.write("[audio queue callback] failed to WritePackets (at index: \(recorderContextPtr.pointee.outputFileWriteIndex), error code: \(result)\n")
                }
            }
            
            let result = AudioQueueEnqueueBuffer(inAQ,
                                                 inAQBuffer,
                                                 0,
                                                 nil)
            if result != noErr {
                recorderContextPtr.pointee.dumpLogger?.write("[audio queue callback] failed to enqueueBuffer (at pack index: \(recorderContextPtr.pointee.outputFileWriteIndex), error code: \(result)\n")
            }
        }
    }
    
    private(set) var isPaused: Bool = false
    private(set) var isRecording: Bool = false {
        didSet {
            self.recorderContext.isRecording = self.isRecording
        }
    }

    
    private var audioStreamBasicDesc: AudioStreamBasicDescription? {
        guard let _ = self.audioQueue else {
            return nil
        }
        
        var asbd = AudioStreamBasicDescription()
        var asbdSz = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        if noErr != AudioQueueGetProperty(self.audioQueue!,
                                          kAudioQueueProperty_StreamDescription,
                                          &asbd,
                                          &asbdSz){
            return nil
        }
        
        return asbd
    }
    
    private var standardUncompressedFmt: AudioStreamBasicDescription {
        var asbd = AudioStreamBasicDescription()
        asbd.mFormatID = kAudioFormatLinearPCM
        asbd.mBitsPerChannel = 16
        asbd.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsBigEndian | kAudioFormatFlagIsPacked
        asbd.mChannelsPerFrame = 2
        asbd.mBytesPerFrame = 4
        asbd.mFramesPerPacket = 1
        asbd.mBytesPerPacket = 4
        asbd.mSampleRate = 0
        return asbd
    }
    
    private var standardCompressedFmt: AudioStreamBasicDescription {
        var asbd = AudioStreamBasicDescription()
        asbd.mFormatID = kAudioFormatMPEG4AAC
        asbd.mChannelsPerFrame = 2
        asbd.mSampleRate = 44100
        return asbd
    }

    //
    // MARK:- constructors and unconstructor
    //
    public init(uncompressedFormatSettings: [String:Any]?, outputFileURL: URL) throws {
        self.outputFileURL = outputFileURL
        //
        // descrip audio data format
        var asbd = self.standardUncompressedFmt
        if let userSettings = uncompressedFormatSettings {
            if let bitDepth = userSettings[AVLinearPCMBitDepthKey] as? UInt32 {
                asbd.mBitsPerChannel = bitDepth
                asbd.mBytesPerFrame = (bitDepth / 8) * asbd.mChannelsPerFrame
                asbd.mBytesPerPacket = asbd.mBytesPerFrame
            }
            
            var userFmtFlags: AudioFormatFlags = 0
            if let isBigendianFlag = userSettings[AVLinearPCMIsBigEndianKey] as? Bool, isBigendianFlag {
                userFmtFlags = userFmtFlags | kAudioFormatFlagIsBigEndian
            }
            if let isFloatFlag = userSettings[AVLinearPCMIsFloatKey] as? Bool {
                userFmtFlags = isFloatFlag ? (userFmtFlags | kAudioFormatFlagIsFloat) : (userFmtFlags | kAudioFormatFlagIsSignedInteger)
            }
            if let isNonInterleaved = userSettings[AVLinearPCMIsNonInterleaved] as? Bool, isNonInterleaved {
                userFmtFlags = userFmtFlags | kAudioFormatFlagIsNonInterleaved
            }
            asbd.mFormatFlags = userFmtFlags != 0 ? userFmtFlags : asbd.mFormatFlags
        }
    
        do {
            try setupAudioQueue(with: &asbd)
        } catch {
            throw error
        }
        print("setup audio queue success.")
        
        var asbdInQueue = self.audioStreamBasicDesc
        if asbdInQueue != nil {
            print("audio queue asbd: {\t\(asbdInQueue!)\n}")
            
            do {
                try setupAudioQueueBuffers(with: &asbdInQueue!)
            } catch  {
                throw error
            }
        } else {
            throw CAAudioRecordeError.dataFormatError(reason: "Can't get kAudioQueueProperty_StreamDescription of audio queue")
        }
        print("setup audio buffer success.")
    }
        
    
    public init(compressedFormatSettings: [String:Any]?, outputFileURL: URL) throws {
        self.outputFileURL = outputFileURL
        
        var asbd = self.standardCompressedFmt
        if let userSettings = compressedFormatSettings {
            if let ftmID = userSettings[AVFormatIDKey] as? UInt32 {
                asbd.mFormatID = ftmID
            }
            if let sampleRate = userSettings[AVSampleRateKey] as? Float64 {
                asbd.mSampleRate = sampleRate
            }
            if let channelCount = userSettings[AVNumberOfChannelsKey] as? UInt32 {
                asbd.mChannelsPerFrame = channelCount
            }
        }
        
        // fill out asbd struct using audio format services api
        var asbdPropertySz = UInt32(MemoryLayout.size(ofValue: asbd))
        if noErr != AudioFormatGetProperty(kAudioFormatProperty_FormatInfo,
                                           0,
                                           nil,
                                           &asbdPropertySz,
                                           &asbd) {
            throw CAAudioRecordeError.dataFormatError(reason: "can't fill out asbd strut using audio format services api")
        }
        
        do {
            try setupAudioQueue(with: &asbd)
        } catch  {
            throw error
        }
        print("setup audio queue success.")
        
        var asbdInQueue = self.audioStreamBasicDesc
        if asbdInQueue != nil {
            print("audio queue asbd: {\t\(asbdInQueue!)\n}")
            
            do {
                try setupAudioQueueBuffers(with: &asbdInQueue!)
            } catch  {
                throw error
            }
        } else {
            throw CAAudioRecordeError.dataFormatError(reason: "Can't get kAudioQueueProperty_StreamDescription of audio queue")
        }
        print("setup audio buffer success.")
    }
    
    
    deinit {
        if let queue = self.audioQueue {
            AudioQueueDispose(queue, true)
        }
        if let file = self.outputFileID {
            AudioFileClose(file)
        }
    }
    
    //
    // MARK: - audio recorder control
    //
    @discardableResult
    public func prepareToRecord() -> Bool {
        guard self.outputFileID == nil else {
            self.delegate?.audioRecorder(self, prepareSuccess: true, error: nil)
            return true
        }
        
        //
        // create output file for recording
        var asbd = self.audioStreamBasicDesc
        guard let _ = asbd else {
            self.delegate?.audioRecorder(self, prepareSuccess: false, error: CAAudioRecordeError.dataFormatError(reason: "Can't get kAudioQueueProperty_StreamDescription of audio queue"))
            return false
        }
        
        guard let fileTypeID = audioFileFormatID(with: self.outputFileURL!) else {
            self.delegate?.audioRecorder(self, prepareSuccess: false, error: CAAudioRecordeError.fileFormatError(reason: "Can't create output file, unspported file format"))
            return false
        }
      
        if let error = callSuccess(withCode: AudioFileCreateWithURL(self.outputFileURL! as CFURL,
                                                                    fileTypeID,
                                                                    &asbd!,
                                                                    [.eraseFile],
                                                                    &self.outputFileID)) {
            self.delegate?.audioRecorder(self, prepareSuccess: false, error: error)
            return false
        }
        
        self.recorderContext.outputFileID = self.outputFileID
        self.delegate?.audioRecorder(self, prepareSuccess: true, error: nil)
        
        //
        // create dump file
        var pathComponents = self.outputFileURL!.pathComponents
        var dunmpFileName = pathComponents.removeLast()
        dunmpFileName.removeSubrange(dunmpFileName.lastIndex(of: ".")!..<dunmpFileName.endIndex)
        dunmpFileName.append("_dump.txt")
        pathComponents.append(dunmpFileName)
        let dumpFilePath = pathComponents.joined(separator: "/")
        self.recorderContext.dumpLogger = TextLogger(path: dumpFilePath)
        
        return true
    }
    
    @discardableResult
    public func start() -> Bool {
        if self.outputFileID == nil {
            if !prepareToRecord() {
                return false
            }
        }

        if let error = callSuccess(withCode: AudioQueueStart(self.audioQueue!, nil)) {
            self.delegate?.audioRecorder(self, startSucces: false, error: error)
            return false
        }

        self.isRecording = true
        self.isPaused = false
        self.delegate?.audioRecorder(self, startSucces: true, error: nil)
        return true
    }

    @discardableResult
    public func pause() -> Bool {
        if let error = callSuccess(withCode: AudioQueuePause(self.audioQueue!)) {
            self.delegate?.audioRecorder(self, pauseSuccess: false, error: error)
            return false
        }
        self.isRecording = false
        self.isPaused = true
        self.delegate?.audioRecorder(self, pauseSuccess: true, error: nil)
        return true
    }
    
    @discardableResult
    public func stop() -> Bool {
        if let error = callSuccess(withCode: AudioQueueStop(self.audioQueue!, true)) {
            self.delegate?.addioRecorder(self, stopSuccess: false, error: error)
            return false
        }

        self.isRecording = false
        self.isPaused = false
        self.delegate?.addioRecorder(self, stopSuccess: true, error: nil)
        
        if !copyMagicCookieDataToOutputAduioFile() {
            self.delegate?.audioRecorder(self, finishSuccess: false, outputFileURL: nil, error: CAAudioRecordeError.fileFormatError(reason: "Can't success to write magic cookie data to output file"))
        }
        
        AudioFileClose(self.outputFileID!)
        self.delegate?.audioRecorder(self, finishSuccess: true, outputFileURL: self.outputFileURL!, error: nil)
        
        return true
    }

    //
    // MARK: - helper
    //
    private func checkError(code: OSStatus, message: String) -> NSError? {
        guard code != noErr else {
            return nil
        }
        
        let errorCode = code.is4CharaterCode ? code.fourCharaters! : "\(code)"
        let errorDesc = String(format: "%s (%s)", message, errorCode)
        return NSError(domain: "CAAudioRecorder",
                       code: Int(code),
                       userInfo: [NSLocalizedDescriptionKey:errorDesc])
    }
    
    private func callSuccess(withCode: OSStatus) -> CAAudioRecordeError? {
        guard withCode != noErr else {
            return nil
        }
        print(withCode)
        switch withCode {
        case kAudioFormatUnsupportedDataFormatError:
            return .dataFormatError(reason: "unspported data format")
            
        case kAudioFileUnsupportedFileTypeError:
            return .fileFormatError(reason: "unspported file type")
        case kAudioFileUnsupportedDataFormatError:
            return .fileFormatError(reason: "data format is uncompatible with file type")
        case kAudioFilePermissionsError:
            return .permissionError(reason: "file permission error")
            
        case kAudioQueueErr_CodecNotFound:
            return .codecError(reason: "codec not found")
        case kAudioQueueErr_InvalidCodecAccess:
            return .codecError(reason: "can't access codec")
            
        case kAudioQueueErr_BufferEmpty:
            return .bufferError(reason: "buffer is empty")
        case kAudioQueueErr_InvalidBuffer:
            return .bufferError(reason: "buffer not belong to queue")
        case kAudioQueueErr_RecordUnderrun:
            return .bufferError(reason: "no enqueue buffer to store data")
            
            
        case kAudioQueueErr_Permissions:
            return .queueError(reason: "queue permisson error")
        case kAudioQueueErr_InvalidQueueType:
            return .queueError(reason: "queue type is wrong")
        case kAudioQueueErr_QueueInvalidated:
            return .queueError(reason: "queue is invalidated")
        case kAudioQueueErr_EnqueueDuringReset:
            return .queueError(reason: "can't enqueue buffer becuase queue is reset, or stop, or dispose now")
        case kAudioQueueErr_DisposalPending:
            return .queueError(reason: "queue is appendly dispose asynchronously")
            
            
        case kAudioQueueErr_InvalidDevice:
            return .hardwareError(reason: "invailed device")
        case kAudioQueueErr_CannotStart:
            return .hardwareError(reason: "can't not start")
        case kAudioQueueErr_CannotStartYet:
            return .hardwareError(reason: "hardware confiugrating, can't not start yet")

            
        default:
            return .unknowedError
        }
    }
    
    //
    // return audio file format base on file extension
    private func audioFileFormatID(with url: URL) -> AudioFileTypeID? {
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
    
    
    //
    // setup audio queue
    private func setupAudioQueue(with format: inout AudioStreamBasicDescription) throws {
        var result = AudioQueueNewInput(&format,
                                        self.audioQueueCallback,
                                        &self.recorderContext,
                                        nil,
                                        nil,
                                        0,
                                        &self.audioQueue)
        if result ==  kAudio_ParamError {
            result = kAudioFormatUnsupportedDataFormatError
        }
        if let error = callSuccess(withCode: result) {
            throw error
        }
    }
    
    //
    // setup audioqueue buffers
    private func setupAudioQueueBuffers(with format: inout AudioStreamBasicDescription) throws {
        var packSize = format.mBytesPerPacket
        var maxPackSizePropertySz = UInt32(MemoryLayout.size(ofValue: packSize))
        if packSize == 0 {
            if noErr != AudioQueueGetProperty(self.audioQueue!,
                                              kAudioQueueProperty_MaximumOutputPacketSize,
                                              &packSize,
                                              &maxPackSizePropertySz) {
                throw CAAudioRecordeError.bufferError(reason: "can't allocate buffer becuase failed to determine VBR fmt max pack size")
            }
        }
        
        let minimumBufferSize: UInt32 = 0x50000
        let expectedBufferDuration: Float64 = 0.5
        var bufferSize: UInt32 = UInt32(format.mSampleRate * expectedBufferDuration * Float64(packSize))
        bufferSize = max(bufferSize, minimumBufferSize)
        print("buffer size: \(bufferSize)")
    
        for _ in 0..<self.audioQueueBufferCount {
            var queueBufferRef: AudioQueueBufferRef?
            let result = AudioQueueAllocateBuffer(self.audioQueue!,
                                                  bufferSize,
                                                  &queueBufferRef)
            if result == kAudio_ParamError {
                defer {
                     AudioQueueDispose(self.audioQueue!, true)
                 }
                throw CAAudioRecordeError.bufferError(reason: "buffer size error")
            }
            
            if let error = callSuccess(withCode: result) {
                defer {
                    AudioQueueDispose(self.audioQueue!, true)
                }
                throw error
            }
            
            if let error = callSuccess(withCode: AudioQueueEnqueueBuffer(self.audioQueue!,
                                                                         queueBufferRef!,
                                                                         0,
                                                                         nil)) {
                defer {
                    AudioQueueDispose(self.audioQueue!, true)
                }
                throw error
            }
        }
    }
    
    
    //
    // copy audio queue's audio converter magic cookie data to audio file
    @discardableResult
    private func copyMagicCookieDataToOutputAduioFile() -> Bool {
        guard let audioQueue = self.audioQueue,
            let outputFileID = self.outputFileID else {
                return false
        }
        
        var magicCookSize: UInt32 = 0
        if noErr == AudioQueueGetPropertySize(audioQueue,
                                              kAudioQueueProperty_MagicCookie,
                                              &magicCookSize) && magicCookSize > 0 {
            var magicCookDataBuffer = UnsafeMutableRawPointer.allocate(byteCount: Int(magicCookSize), alignment: 0)
            defer {
                magicCookDataBuffer.deallocate()
            }
            if noErr == AudioQueueGetProperty(audioQueue,
                                              kAudioQueueProperty_MagicCookie,
                                              magicCookDataBuffer,
                                              &magicCookSize) && magicCookSize > 0 {
                if noErr != AudioFileSetProperty(outputFileID,
                                                 kAudioFilePropertyMagicCookieData,
                                                 magicCookSize,
                                                 magicCookDataBuffer) {
                    return false
                }
                
            }
        }
        
        return true
    }
    
    //
    // get default input device's defalut sample rate
    private func getDefualtInputDeviceSampleRate() throws -> Float64 {
        var audioDevice: AudioDeviceID = 0
        var propertySz = UInt32(MemoryLayout<AudioDeviceID>.size)
        var aopa = AudioObjectPropertyAddress()
        aopa.mSelector = kAudioHardwarePropertyDefaultInputDevice
        aopa.mScope = kAudioObjectPropertyScopeGlobal
        aopa.mElement = kAudioObjectPropertyElementMaster
        if let e = checkError(code: AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                                               &aopa,
                                                               0,
                                                               nil,
                                                               &propertySz,
                                                               &audioDevice), message: "getDefualtInputDevice Error") {
            throw e
        }

        aopa.mSelector = kAudioDevicePropertyNominalSampleRate
        aopa.mScope = kAudioObjectPropertyScopeGlobal
        aopa.mElement = kAudioObjectPropertyElementMaster
        propertySz = UInt32(MemoryLayout<Float64>.size)
        
        var sampleRate: Float64 = 0
        if let e = checkError(code: AudioObjectGetPropertyData(audioDevice,
                                                               &aopa,
                                                               0,
                                                               nil,
                                                               &propertySz,
                                                               &sampleRate), message: "getDefalutInputDeviceNormalSampleRate Error") {
            throw e
        }

        return sampleRate
    }
    
    //
    // get default input device's buffer size
//    private func getDefaultInputDeviceBufferSize() throws -> UInt32 {
//        var deviceId: AudioDeviceID = 0
//        var propertySz: UInt32 = UInt32(MemoryLayout<AudioDeviceID>.size)
//        var aopa = AudioObjectPropertyAddress()
//        aopa.mSelector = kAudioHardwarePropertyDefaultInputDevice
//        aopa.mScope = kAudioObjectPropertyScopeGlobal
//        aopa.mElement = kAudioObjectPropertyElementMaster
//        if let e = checkError(code: AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
//                                                               &aopa,
//                                                               0,
//                                                               nil,
//                                                               &propertySz,
//                                                               &deviceId), message: "getDefaultInputDeviceBufferSize (query device)") {
//            throw e
//        }
//
//        var bufferSz: UInt32 = 0
//        propertySz = UInt32(MemoryLayout<UInt32>.size)
//        aopa.mSelector = kAudioDevicePropertyBufferSize
//        aopa.mScope = kAudioObjectPropertyScopeGlobal
//        aopa.mElement = kAudioObjectPropertyElementMaster
//        if let e = checkError(code: AudioObjectGetPropertyData(deviceId,
//                                                               &aopa,
//                                                               0,
//                                                               nil,
//                                                               &propertySz,
//                                                               &bufferSz), message: "getDefaultInputDeviceBufferSize (query buffer size)") {
//            throw e
//        }
//
//        return bufferSz
//    }

    
}


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





extension CAAudioRecorderDelegate {
    func audioRecorder(_ recorder: CAAudioRecorder, prepareSuccess: Bool, error: CAAudioRecorder.CAAudioRecordeError?){}
    func audioRecorder(_ recorder: CAAudioRecorder, startSucces: Bool, error: CAAudioRecorder.CAAudioRecordeError?){}
    func audioRecorder(_ recorder: CAAudioRecorder, pauseSuccess: Bool, error: CAAudioRecorder.CAAudioRecordeError?){}
    func addioRecorder(_ recorder: CAAudioRecorder, stopSuccess: Bool, error: CAAudioRecorder.CAAudioRecordeError?){}
    func audioRecorder(_ recorder: CAAudioRecorder, finishSuccess: Bool, outputFileURL: URL?, error: CAAudioRecorder.CAAudioRecordeError?){}
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
