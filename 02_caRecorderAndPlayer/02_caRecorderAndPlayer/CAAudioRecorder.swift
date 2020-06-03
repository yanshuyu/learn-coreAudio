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
    
    public class RecorderContext {
        weak var recorder: CAAudioRecorder?
        var outputFileID: AudioFileID?
        var outputFileWriteIndex: Int64 = 0
        
        // dumo info for debuging
        var debugLogger: TextLogger?
    }

    public weak var delegate: CAAudioRecorderDelegate?
    private var audioQueue: AudioQueueRef?
    private let audioQueueBufferCount = 3    
    private var outputFileID: AudioFileID? {
        get {
            return self.recorderContext.outputFileID
        }
        set {
            self.recorderContext.outputFileID = newValue
        }
    }
    private var outputFileURL: URL?
    private var recorderContext = RecorderContext()
    private(set) var isPaused: Bool = false
    private(set) var isRecording: Bool = false 
    private var asbdInQueue = AudioStreamBasicDescription()
    
    private var standardUncompressedFmt: AudioStreamBasicDescription {
        var asbd = AudioStreamBasicDescription()
        asbd.mFormatID = kAudioFormatLinearPCM
        asbd.mBitsPerChannel = 16
        asbd.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsBigEndian | kAudioFormatFlagIsPacked
        asbd.mChannelsPerFrame = 1
        asbd.mBytesPerFrame = asbd.mBitsPerChannel / 8 * asbd.mChannelsPerFrame
        asbd.mFramesPerPacket = 1
        asbd.mBytesPerPacket = asbd.mBytesPerFrame
        asbd.mSampleRate = 44100
        return asbd
    }
    
    private var standardCompressedFmt: AudioStreamBasicDescription {
        var asbd = AudioStreamBasicDescription()
        asbd.mFormatID = kAudioFormatMPEG4AAC
        //asbd.mChannelsPerFrame = 1
        //asbd.mSampleRate = 44100
        return asbd
    }

    //
    // MARK:- constructors and unconstructor
    //
    public init(uncompressedFormatSettings: [String:Any]?, outputFileURL: URL) throws {
        self.outputFileURL = outputFileURL
        
        self.recorderContext.debugLogger = createLogFileAlongside(with: outputFileURL)
        //
        // descrip audio data format
        var asbd = self.standardUncompressedFmt
        asbd.mSampleRate = (try? getDefualtInputDeviceSampleRate()) ?? 44100
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
            asbd.mFormatFlags = userFmtFlags != 0 ? (userFmtFlags | kAudioFormatFlagIsPacked) : asbd.mFormatFlags
        }

        do {
            try self.asbdInQueue = setupAudioQueue(with: &asbd)
        } catch {
            throw error
        }
        
        self.recorderContext.debugLogger?.write("setup audio queue success.\n")
        self.recorderContext.debugLogger?.write("audio queue asbd: {\t\(asbdInQueue)\t}\n")
        
        do {
            try setupAudioQueueBuffers()
        } catch  {
            throw error
        }
        
        self.recorderContext.debugLogger?.write("setup audio buffer success.\n")
    }
        
    
    public init(compressedFormatSettings: [String:Any]?, outputFileURL: URL) throws {
        self.outputFileURL = outputFileURL
        self.recorderContext.recorder = self
        self.recorderContext.debugLogger = createLogFileAlongside(with: outputFileURL)

        
        var asbd = self.standardCompressedFmt
        asbd.mSampleRate = (try? getDefualtInputDeviceSampleRate()) ?? 0.0
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
        self.recorderContext.debugLogger?.write("preferred fmt: {\t\(asbd)\t\n}")
        
        do {
            try self.asbdInQueue = setupAudioQueue(with: &asbd)
        } catch  {
            throw error
        }
        
        self.recorderContext.debugLogger?.write("setup audio queue success.\n")
        self.recorderContext.debugLogger?.write("audio queue fmt: {\t\(asbdInQueue)\t}\n")
        
        do {
            try setupAudioQueueBuffers()
        } catch  {
            throw error
        }
        
        self.recorderContext.debugLogger?.write("setup audio buffer success.\n")
    }
    
    
    deinit {
        cleanup()
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
        guard let fileTypeID = audioFileFormatID(with: self.outputFileURL!) else {
            self.delegate?.audioRecorder(self, prepareSuccess: false, error: CAAudioRecordeError.fileFormatError(reason: "Can't create output file, unspported file format"))
            return false
        }
      
        if let error = callSuccess(withCode: AudioFileCreateWithURL(self.outputFileURL! as CFURL,
                                                                    fileTypeID,
                                                                    &self.asbdInQueue,
                                                                    [.eraseFile],
                                                                    &self.outputFileID)) {
            self.delegate?.audioRecorder(self, prepareSuccess: false, error: error)
            return false
        }
        
        //
        // copy encoder magic cookie to file if any
        if !copyEncoderMagicCookieData(from: self.audioQueue!, to: self.outputFileID!) {
            self.delegate?.audioRecorder(self, prepareSuccess: false, error: CAAudioRecordeError.codecError(reason: "Can't write encoder magic cookie to file"))
            return false
        }
        
        self.delegate?.audioRecorder(self, prepareSuccess: true, error: nil)
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
        if let error = callSuccess(withCode: AudioQueueStop(self.audioQueue!, false)) {
            self.delegate?.addioRecorder(self, stopSuccess: false, error: error)
            return false
        }

        self.isRecording = false
        self.isPaused = false
        self.delegate?.addioRecorder(self, stopSuccess: true, error: nil)
        
        if !copyEncoderMagicCookieData(from: self.audioQueue!, to: self.outputFileID!) {
            self.delegate?.audioRecorder(self, finishSuccess: false, error: CAAudioRecordeError.codecError(reason: "Can't write encoder magic cookie data to file"))
        }
        
        cleanup()
        self.delegate?.audioRecorder(self, finishSuccess: true, error: nil)
 
        return true
    }

   
    //
    // clean up
    private func cleanup() {
        self.outputFileURL = nil
        self.asbdInQueue = AudioStreamBasicDescription()
        self.recorderContext = RecorderContext()
        
        if let file = self.outputFileID {
            AudioFileClose(file)
            self.outputFileID = nil
        }
        
        if let queue = self.audioQueue {
            AudioQueueDispose(queue, true)
            self.audioQueue = nil
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


fileprivate func audioQueueInputCallback(inUserData: UnsafeMutableRawPointer?,
                           inQueue: AudioQueueRef,
                           inBuffer: AudioQueueBufferRef,
                           inStartTime: UnsafePointer<AudioTimeStamp>,
                           inNumPackets: UInt32,
                           inPacketDesc: UnsafePointer<AudioStreamPacketDescription>?) {
    let recorderContext = inUserData!.bindMemory(to: CAAudioRecorder.RecorderContext.self, capacity: 1).pointee
    guard let recorder = recorderContext.recorder else { return }
         guard let outputFileID = recorderContext.outputFileID else { return }
         
         if inNumPackets > 0 {
             recorderContext.debugLogger?.write("[AudioQueueCB] try to write \t\(inNumPackets) \tpackets at index: \t\(recorderContext.outputFileWriteIndex)\t, time: \(inStartTime.pointee.mHostTime)\n")
             var ioNumberPacks = inNumPackets
             let result = AudioFileWritePackets(outputFileID,
                                                false,
                                                inBuffer.pointee.mAudioDataByteSize,
                                                inPacketDesc,
                                                recorderContext.outputFileWriteIndex,
                                                &ioNumberPacks,
                                                inBuffer.pointee.mAudioData)
             if result == noErr {
                 recorderContext.outputFileWriteIndex += Int64(ioNumberPacks)
                 recorderContext.debugLogger?.write("[AudioQueueCB] success to write \t\(ioNumberPacks)\t audio packets, total written \t\(recorderContext.outputFileWriteIndex)\t packets\n")
             } else {
                 recorderContext.debugLogger?.write("[AudioQueueCB] failed to WritePackets (at index: \t\(recorderContext.outputFileWriteIndex)\t, error code: \(result)\n")
             }
    
         }
         
         if recorder.isRecording {
             let result = AudioQueueEnqueueBuffer(inQueue,
                                                  inBuffer,
                                                  0,
                                                  nil)
             if result != noErr {
                 recorderContext.debugLogger?.write("[AudioQueueCB] failed to enqueueBuffer (at pack index: \t\(recorderContext.outputFileWriteIndex)\t, error code: \(result)\n")
             }
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



extension CAAudioRecorder {
    //
    // MARK: - helper
    //
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
                return .bufferError(reason: "buffer is empty or buffer size is invalided")
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
    @discardableResult
    private func setupAudioQueue(with format: inout AudioStreamBasicDescription) throws -> AudioStreamBasicDescription {
        
        var result = AudioQueueNewInput(&format,
                                        audioQueueInputCallback(inUserData:inQueue:inBuffer:inStartTime:inNumPackets:inPacketDesc:),
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
        
        // get asbd in created queue
        var asbdIQ = AudioStreamBasicDescription()
        var asbdPropertySize = UInt32(MemoryLayout.size(ofValue: asbdIQ))
        if noErr != AudioQueueGetProperty(self.audioQueue!,
                                          kAudioQueueProperty_StreamDescription,
                                          &asbdIQ,
                                          &asbdPropertySize) {
            throw CAAudioRecordeError.dataFormatError(reason: "Can't get asbd in audio queue")
        }
        
        return asbdIQ
    }
    
    //
    // setup audioqueue buffers
    private func setupAudioQueueBuffers() throws {
        guard let bufferSize = computeQueueBufferSize(withFormat: self.asbdInQueue, duration: 0.5, inQueue: self.audioQueue!) else {
            throw CAAudioRecordeError.bufferError(reason: "Can't compute queue buffer size")
        }
        for _ in 0..<self.audioQueueBufferCount {
            var queueBufferRef: AudioQueueBufferRef?
            var result = AudioQueueAllocateBuffer(self.audioQueue!,
                                                  bufferSize,
                                                  &queueBufferRef)
            if result == kAudio_ParamError {
                result = kAudioQueueErr_BufferEmpty
            }
            
            if let error = callSuccess(withCode: result) {
                cleanup()
                throw error
            }
            
            if let error = callSuccess(withCode: AudioQueueEnqueueBuffer(self.audioQueue!,
                                                                         queueBufferRef!,
                                                                         0,
                                                                         nil)) {
                cleanup()
                throw error
            }
        }
    }
    
    private func computeQueueBufferSize(withFormat fmt: AudioStreamBasicDescription, duration: Float64, inQueue: AudioQueueRef) -> UInt32? {
        let frames = UInt32(ceil(fmt.mSampleRate * duration))
        if fmt.mBytesPerFrame > 0 {
            return fmt.mBytesPerFrame * frames
        }
        
        var packSize = fmt.mBytesPerPacket
        var propertySize = UInt32(MemoryLayout.size(ofValue: packSize))
        if packSize == 0 {
            if noErr != AudioQueueGetProperty(inQueue,
                                              kAudioQueueProperty_MaximumOutputPacketSize,
                                              &packSize,
                                              &propertySize) {
                return nil
            }
        }
        
        var numPacks = frames
        if fmt.mFramesPerPacket > 0 {
            numPacks = frames / fmt.mFramesPerPacket
        }
        numPacks = numPacks > 0 ? numPacks : 1
        
        return numPacks * packSize
    }
    
    //
    // copy audio queue's audio converter magic cookie data to audio file
    @discardableResult
    private func copyEncoderMagicCookieData(from queue: AudioQueueRef, to file: AudioFileID) -> Bool {
        var magicCookSize: UInt32 = 0
        if noErr == AudioQueueGetPropertySize(queue,
                                              kAudioQueueProperty_MagicCookie,
                                              &magicCookSize) && magicCookSize > 0 { // does have some magic cookie
            var magicCookDataBuffer = UnsafeMutableRawPointer.allocate(byteCount: Int(magicCookSize), alignment: 0)
            defer {
                magicCookDataBuffer.deallocate()
            }
            
            if noErr == AudioQueueGetProperty(queue,
                                              kAudioQueueProperty_MagicCookie,
                                              magicCookDataBuffer,
                                              &magicCookSize) && magicCookSize > 0 {
                if noErr == AudioFileSetProperty(file,
                                                 kAudioFilePropertyMagicCookieData,
                                                 magicCookSize,
                                                 magicCookDataBuffer) {
                    return true
                }
                return false
            }
            return false
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
        if noErr != AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                               &aopa,
                                               0,
                                               nil,
                                               &propertySz,
                                               &audioDevice) {
            throw CAAudioRecordeError.hardwareError(reason: "Can't get default input device")
        }
        
        aopa.mSelector = kAudioDevicePropertyNominalSampleRate
        aopa.mScope = kAudioObjectPropertyScopeGlobal
        aopa.mElement = kAudioObjectPropertyElementMaster
        propertySz = UInt32(MemoryLayout<Float64>.size)
        
        var sampleRate: Float64 = 0
        if noErr != AudioObjectGetPropertyData(audioDevice,
                                               &aopa,
                                               0,
                                               nil,
                                               &propertySz,
                                               &sampleRate) {
            throw CAAudioRecordeError.hardwareError(reason: "Can't get default input device's sample rate")
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


