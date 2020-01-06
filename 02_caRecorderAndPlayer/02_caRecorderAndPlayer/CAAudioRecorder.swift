//
//  CAAudioRecorder.swift
//  02_caRecorderAndPlayer
//
//  Created by sy on 2019/12/26.
//  Copyright © 2019 sy. All rights reserved.
//
import Foundation
import AudioToolbox

protocol CAAudioRecorderDelegate: AnyObject {
    func audioRecorder(_ recorder: CAAudioRecorder, prepareSuccess: Bool, error: Error?)
    func audioRecorder(_ recorder: CAAudioRecorder, startSucces: Bool, error: Error?)
    func audioRecorder(_ recorder: CAAudioRecorder, pauseSuccess: Bool, error: Error?)
    func addioRecorder(_ recorder: CAAudioRecorder, stopSuccess: Bool, error: Error?)
    func audioRecorder(_ recorder: CAAudioRecorder, finishSuccess: Bool, outputFileURL: URL?, error: Error?)
}


class CAAudioRecorder {
    private struct RecorderContext {
        var isRecording: Bool
        var audioFile: AudioFileID
        var writtenPackCount: Int64
    }
    
    private var recorderContext: RecorderContext?
    public weak var delegate: CAAudioRecorderDelegate?
    
    private var audioQueue: AudioQueueRef?
    private let audioQueueBufferCount = 3
    private let audioBufferDuration: TimeInterval = 0.5
    private var audioFile: AudioFileID?
    private var audioFileURL: URL?
    private var audioQueueCallback: AudioQueueInputCallback = { (inUserData, inAQ, inAQBuffer, inStartTime, inNumberASPD, inASPD) in
        if let userData = inUserData {
            let recorderContextPtr = userData.bindMemory(to: RecorderContext?.self, capacity: 1)
            if recorderContextPtr.pointee != nil {
                if inNumberASPD > 0 {
                    var numberASPD = inNumberASPD
                    let result = AudioFileWritePackets(recorderContextPtr.pointee!.audioFile,
                                                       false,
                                                       inAQBuffer.pointee.mAudioDataByteSize,
                                                       inASPD,
                                                       recorderContextPtr.pointee!.writtenPackCount,
                                                       &numberASPD,
                                                       inAQBuffer.pointee.mAudioData)
                    if result == noErr {
                        recorderContextPtr.pointee!.writtenPackCount += Int64(numberASPD)
                        print("success written \(numberASPD) audio packets, total written \(recorderContextPtr.pointee!.writtenPackCount) packets")
                    } else {
                        print("AudioFileWritePackets (index: \(recorderContextPtr.pointee!.writtenPackCount), Error: \(result.fourCharaters ?? "unknow")")
                    }
                }
                
                if recorderContextPtr.pointee!.isRecording {
                    let result = AudioQueueEnqueueBuffer(inAQ,
                                                         inAQBuffer,
                                                         0,
                                                         nil)
                    if result != noErr {
                        print("AudioQueueEnqueueBuffer at pack index: \(recorderContextPtr.pointee!.writtenPackCount) Failed, Error: \(result.fourCharaters ?? "unkown")")
                    }
                }
            }
        }
    }
    
    private var _isRecording: Bool = false
    private(set) var isRecording: Bool {
        get {
            return self._isRecording
        }
        set {
            self.recorderContext?.isRecording = newValue
            self._isRecording = newValue
        }
    }
    private(set) var isPausing: Bool = false
    
    private var audioStreamBasicDesc: AudioStreamBasicDescription? {
        guard let _ = self.audioQueue else {
            return nil
        }
        
        var asbd = AudioStreamBasicDescription()
        var asbdSz = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        if let _ = checkError(code: AudioQueueGetProperty(self.audioQueue!,
                                                              kAudioQueueProperty_StreamDescription,
                                                              &asbd,
                                                              &asbdSz), message: "") {
            return nil
        }
        return asbd
    }
    
    private var magicCookieDataDesc: (UnsafeMutableRawPointer,UInt32)? {
        guard let _ = self.audioQueue else {
            return nil
        }
        
        var magicCookieSz: UInt32 = 0
        if let _ = checkError(code: AudioQueueGetPropertySize(self.audioQueue!,
                                                              kAudioQueueProperty_MagicCookie,
                                                              &magicCookieSz),
                              message: "") {
            return nil
        }
        
        let magicCookieData = UnsafeMutableRawPointer.allocate(byteCount: Int(magicCookieSz), alignment: 0)
        if let _ = checkError(code: AudioQueueGetProperty(self.audioQueue!,
                                                          kAudioQueueProperty_MagicCookie,
                                                          magicCookieData,
                                                          &magicCookieSz),
                              message: "") {
            magicCookieData.deallocate()
            return nil
        }
        return (magicCookieData, magicCookieSz)
    }

    
    public init(standardFormatWithChannelCount: UInt32) throws {
        //
        // descrip audio format
        var asbd = AudioStreamBasicDescription()
        asbd.mFormatID = kAudioFormatMPEG4AAC
        asbd.mChannelsPerFrame = standardFormatWithChannelCount
        do {
            asbd.mSampleRate = try getDefualtInputDeviceSampleRate()
        } catch {
            throw error
        }
        
        // using audio format service to fill rest of fileds of asbd
        var asbdSz = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        if let error = checkError(code: AudioFormatGetProperty(kAudioFormatProperty_FormatInfo,
                                                               0,
                                                               nil,
                                                               &asbdSz,
                                                               &asbd),
                                  message: "AudioFormatGetProperty( auto filling asbd ) Error") {
            throw error
            
        }
        
        //
        //  create audio queue
        if let error = checkError(code: AudioQueueNewInput(&asbd,
                                                           self.audioQueueCallback,
                                                           &self.recorderContext,
                                                           nil,
                                                           nil,
                                                           0,
                                                           &self.audioQueue), message: "AudioQueueNewInput Error") {
            throw error
            
        }
        
        //
        // allocate audio queue buffers
        var bufferSz: UInt32 = 0
        do {
            bufferSz = try computeAudioQueueBufferSize()
            //bufferSz = try getDefaultInputDeviceBufferSize()
        } catch {
            throw error
        }
        for _ in 0..<self.audioQueueBufferCount {
            var audioQueueBuffer: AudioQueueBufferRef?
            if let error = checkError(code: AudioQueueAllocateBuffer(self.audioQueue!,
                                                                 bufferSz,
                                                                 &audioQueueBuffer), message: "AudioQueueAllocateBuffer Error") {
                throw error
            }
            
            if let error = checkError(code: AudioQueueEnqueueBuffer(self.audioQueue!,
                                                                    audioQueueBuffer!,
                                                                    0,
                                                                    nil), message: "AudioQueueEnqueueBuffer Error") {
                throw error
            }
        }
        
    }
    
    deinit {
        if let queue = self.audioQueue {
            AudioQueueDispose(queue, true)
        }
        if let file = self.audioFile {
            AudioFileClose(file)
        }
    }
    
    //
    // MARK: - audio recorder control
    //
    public func prepareToRecord() -> Bool {
        guard self.audioFile == nil else {
            self.delegate?.audioRecorder(self, prepareSuccess: true, error: nil)
            return true
        }
        
        //
        // create file for recording
        var asbd = self.audioStreamBasicDesc
        guard let _ = asbd else {
            return false
        }
        let filePath = (NSTemporaryDirectory() as NSString).appendingPathComponent(UUID().uuidString + ".m4a")
        self.audioFileURL = URL(fileURLWithPath: filePath)
        if let e = checkError(code: AudioFileCreateWithURL(self.audioFileURL! as CFURL,
                                                           kAudioFileM4AType,
                                                           &asbd!,
                                                           [.eraseFile],
                                                           &self.audioFile), message: "AudioFileCreateWithURL Error") {
            self.delegate?.audioRecorder(self, prepareSuccess: false, error: e)
            return false
        }
        
        //
        // copy audio queue's audio format converter magic cookie to created audio file
        if !copyMagicCookieDataToAduioFile() {
            let error = NSError(domain: "CAAudioRecorder", code: 0, userInfo: [NSLocalizedDescriptionKey:"copyMagicCookieDataToAduioFile Failed"])
            self.delegate?.audioRecorder(self, prepareSuccess: false, error: error)
            clearAudioFile()
            return false
        }
        
        self.recorderContext = RecorderContext(isRecording: false, audioFile: self.audioFile!, writtenPackCount: 0)
        self.delegate?.audioRecorder(self, prepareSuccess: true, error: nil)
        return true
    }
    
    @discardableResult
    public func start() -> Bool {
        if !self.prepareToRecord() {
            return false
        }
        
        if let error = checkError(code: AudioQueueStart(self.audioQueue!, nil), message: "") {
            self.delegate?.audioRecorder(self, startSucces: false, error: error)
            return false
        }
        
        self.isRecording = true
        self.isPausing = false
        self.delegate?.audioRecorder(self, startSucces: true, error: nil)
        return true
    }
    
    public func pause() {
        if let error = checkError(code: AudioQueuePause(self.audioQueue!), message: "AudioQueuePause Error") {
            self.delegate?.audioRecorder(self, pauseSuccess: false, error: error)
            return
        }
        self.isRecording = false
        self.isPausing = true
        self.delegate?.audioRecorder(self, pauseSuccess: true, error: nil)
    }
    
    public func stop() {
        if let error = checkError(code: AudioQueueStop(self.audioQueue!, true), message: "AudioQueueStop Error") {
            self.delegate?.addioRecorder(self, stopSuccess: false, error: error)
            return
        }
        self.delegate?.addioRecorder(self, stopSuccess: true, error: nil)
        self.isRecording = false
        self.isPausing = false
        
        if !copyMagicCookieDataToAduioFile() {
            let error = NSError(domain: "CAAudioRecorder", code: 0, userInfo: [NSLocalizedDescriptionKey:"copyMagicCookieDataToAduioFile Failed"])
            self.delegate?.audioRecorder(self, finishSuccess: false, outputFileURL: nil, error: error)
            return
        }
        
        self.delegate?.audioRecorder(self, finishSuccess: true, outputFileURL: self.audioFileURL, error: nil)
    }
    
    //
    // MARK: - helper
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
    
    //
    // delect current audio file
    private func clearAudioFile() {
        guard let file = self.audioFile,
            let fileURL = self.audioFileURL else {
                return
        }
        AudioFileClose(file)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.removeItem(at: fileURL)
        }
        
        self.audioFileURL = nil
        self.audioFile = nil
    }
    
    //
    // copy audio queue's audio converter magic cookie data to audio file
    @discardableResult
    private func copyMagicCookieDataToAduioFile() -> Bool {
        guard let mcdd = self.magicCookieDataDesc,
            let _ = self.audioFile else {
                return false
        }
        var magicCookieData = mcdd.0
        var magicCookieDataSz = mcdd.1
        defer {
            magicCookieData.deallocate()
        }
        
        if let e = checkError(code: AudioFileSetProperty(self.audioFile!,
                                                         kAudioFilePropertyMagicCookieData,
                                                         magicCookieDataSz,
                                                         magicCookieData), message: "copyMagicCookieDataToAduioFile Error") {
            print(e.localizedDescription)
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
    private func getDefaultInputDeviceBufferSize() throws -> UInt32 {
        var deviceId: AudioDeviceID = 0
        var propertySz: UInt32 = UInt32(MemoryLayout<AudioDeviceID>.size)
        var aopa = AudioObjectPropertyAddress()
        aopa.mSelector = kAudioHardwarePropertyDefaultInputDevice
        aopa.mScope = kAudioObjectPropertyScopeGlobal
        aopa.mElement = kAudioObjectPropertyElementMaster
        if let e = checkError(code: AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                                               &aopa,
                                                               0,
                                                               nil,
                                                               &propertySz,
                                                               &deviceId), message: "getDefaultInputDeviceBufferSize (query device)") {
            throw e
        }
        
        var bufferSz: UInt32 = 0
        propertySz = UInt32(MemoryLayout<UInt32>.size)
        aopa.mSelector = kAudioDevicePropertyBufferSize
        aopa.mScope = kAudioObjectPropertyScopeGlobal
        aopa.mElement = kAudioObjectPropertyElementMaster
        if let e = checkError(code: AudioObjectGetPropertyData(deviceId,
                                                               &aopa,
                                                               0,
                                                               nil,
                                                               &propertySz,
                                                               &bufferSz), message: "getDefaultInputDeviceBufferSize (query buffer size)") {
            throw e
        }
        
        return bufferSz
    }
    
    //
    // compute audio queue buffer size base on audio format
    private func computeAudioQueueBufferSize() throws -> UInt32 {
        guard let asbd = self.audioStreamBasicDesc else {
            throw NSError(domain: "CARecorderDomain", code: 0, userInfo: [NSLocalizedDescriptionKey:"computeAudioQueueBufferSize Error (Can't get audioStreamBasicDesc object)"])
        }
        
        let frameCount = UInt32(ceil(asbd.mSampleRate * self.audioBufferDuration))
        if asbd.mBytesPerFrame > 0 {
            return asbd.mBytesPerFrame * frameCount
        }
        
        let framesPerPack = asbd.mFramesPerPacket > 0 ? asbd.mFramesPerPacket : 1
        var packCount = frameCount / framesPerPack
        packCount = packCount > 0 ? packCount : 1
        
        var packSize = asbd.mBytesPerPacket
        if packSize == 0 {
            var propertySz = UInt32(MemoryLayout<UInt32>.size)
            if let error = checkError(code: AudioQueueGetProperty(self.audioQueue!,
                                                                  kAudioQueueProperty_MaximumOutputPacketSize,
                                                                  &packSize,
                                                                  &propertySz),message: "computeAudioQueueBufferSize Error (Can't get maxPeckSize property)") {
                throw error
            }
        }
        
        return packCount * packSize
    }
    
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
    func audioRecorder(_ recorder: CAAudioRecorder, prepareSuccess: Bool, error: Error?) { }
    func audioRecorder(_ recorder: CAAudioRecorder, startSucces: Bool, error: Error?) { }
    func audioRecorder(_ recorder: CAAudioRecorder, pauseSuccess: Bool, error: Error?) { }
    func addioRecorder(_ recorder: CAAudioRecorder, stopSuccess: Bool, error: Error?) { }
    func audioRecorder(_ recorder: CAAudioRecorder, finishSuccess: Bool, outputFileURL: URL?, error: Error?) { }
}
