//
//  CAAudioPlayer.swift
//  02_caRecorderAndPlayer
//
//  Created by sy on 2020/2/11.
//  Copyright © 2020 sy. All rights reserved.
//

import Foundation
import AudioToolbox

class CAAudioPlayer {
    enum CAAudioPlayerError: Error {
        case invaildDevice
        case fileNotFound
        case permissionError
        case unsupportedFileType
        case unsupportedDataFormat
        case queueError(reason: String)
        case unknowedError
    }
    
    public static let KCAAudioPlayerPlayToEndNotification = Notification.Name(rawValue: "CAAudioPlayerPlayToEndNotification")
    
    private class PlayerContext: CustomStringConvertible {
        var fileID: AudioFileID?
        var readIndex: Int64 = 0
        var totalPacksToRead: Int64 = 0
        var expectedNumPacksPerReadCircle: UInt32 = 0
        var aqBufferSize: UInt32 = 0
        var playToEnd = false
        var debugLogger: TextLogger?
        weak var player: CAAudioPlayer?
        
        var description: String {
            var desc = ""
            let idStr = fileID == nil ? "nil": "\(fileID!)"
            
            desc += "{\tfileID: " + idStr + "\n"
            desc += "\ttotalPacksToRead: \(totalPacksToRead)\n"
            desc += "\texpectedNumPacksPerReadCircle: \(expectedNumPacksPerReadCircle)\n"
            desc += "\tcurrentReadIndex: \(readIndex)\n"
            desc += "\taqBufferSize: \(aqBufferSize)\n"
            desc += "\tplayReachEnd: \(playToEnd)\t}"
            return desc
        }
    }
    
    private var audioQueue: AudioQueueRef?
    private let queueBufferCount = 3
    private var playerContext = PlayerContext()
    private var isPrepared = false
    private(set) var isPlaying = false
    private(set) var isPause = false
    
    public var volume: Float32 {
        get {
            var volume: Float32 = 1.0
            let result = AudioQueueGetParameter(self.audioQueue!,
                                   kAudioQueueParam_Volume,
                                   &volume)
            if result != noErr {
                print("Can't query volume from queue, error: \(result)")
            }
            return volume
        }
        
        set {
            var volume = newValue
            volume = min(1.0, volume)
            volume = max(0.0, volume)
            let result = AudioQueueSetParameter(self.audioQueue!,
                                   kAudioQueueParam_Volume,
                                   volume)
            if result != noErr {
                print("Can't set volume for queue, error: \(result)")
            }
        }
    }
    
    public var rate: Float32 {
        get {
            var rate: Float32 = 1.0
            let result = AudioQueueGetParameter(self.audioQueue!,
                                   kAudioQueueParam_PlayRate,
                                   &rate)
            if result != noErr {
                print("Can't query rate from queue, error: \(result)")
            }
            return rate
        }
        
        set {
            var rate = newValue
            rate = min(2.0, rate)
            rate = max(0.0, rate)
            let result = AudioQueueSetParameter(self.audioQueue!,
                                   kAudioQueueParam_PlayRate,
                                   rate)
            if result != noErr {
                print("Can't set rate for queue, error: \(result)")
            }
        }
    }
    
    
    
    public static let propertyProcCallback: AudioQueuePropertyListenerProc = { (inUserData, inAQ, inID) in
        if inID == kAudioQueueProperty_IsRunning {
            var isRunning: UInt32 = 0
            var propertySize = UInt32(MemoryLayout.size(ofValue: isRunning))
            if noErr == AudioQueueGetProperty(inAQ,
                                             inID,
                                             &isRunning,
                                             &propertySize) {
                let playerContext = inUserData!.bindMemory(to: PlayerContext.self, capacity: 1).pointee
                playerContext.player?.isPlaying = isRunning != 0 ? true : false
            }
        }
        
    }
    
    public static let queueCallback: AudioQueueOutputCallback = { (inUserData, inAQ, inBuffer) in
        var playerContext = inUserData!.bindMemory(to: CAAudioPlayer.PlayerContext.self, capacity: 1).pointee
        
        guard !playerContext.playToEnd, let af = playerContext.fileID else {
            return
        }
        
        var numPacksToRead = playerContext.expectedNumPacksPerReadCircle
        if playerContext.readIndex + Int64(numPacksToRead) > playerContext.totalPacksToRead {
            numPacksToRead = UInt32(playerContext.totalPacksToRead - playerContext.readIndex)
        }
        
        let finishPlayback = {
            playerContext.playToEnd = true
            AudioQueueStop(inAQ, false)
            NotificationCenter.default.post(name: CAAudioPlayer.KCAAudioPlayerPlayToEndNotification, object: playerContext.player)
            playerContext.debugLogger?.write("[AudioQueueCB] play back reach end, total play packets: \(playerContext.readIndex)")
        }
        
        guard numPacksToRead > 0 else {
            finishPlayback()
            return
        }
        
        playerContext.debugLogger?.write("[AudioQueueCB] try to read \(numPacksToRead) packets at index \(playerContext.readIndex)\n")
        
        var ioSizeInBytes = playerContext.aqBufferSize
        var readReslut = AudioFileReadPacketData(af,
                                            false,
                                            &ioSizeInBytes,
                                            inBuffer.pointee.mPacketDescriptions,
                                            playerContext.readIndex,
                                            &numPacksToRead,
                                            inBuffer.pointee.mAudioData)
        if numPacksToRead > 0 {
            playerContext.debugLogger?.write("[AudioQueueCB] success to read \(numPacksToRead) packets at index \(playerContext.readIndex)\n")
            inBuffer.pointee.mAudioDataByteSize = ioSizeInBytes
            inBuffer.pointee.mPacketDescriptionCount = numPacksToRead
            
            let enqueueReslut = AudioQueueEnqueueBuffer(inAQ,
                                                        inBuffer,
                                                        0,
                                                        nil)
            if enqueueReslut == noErr {
                playerContext.readIndex += Int64(numPacksToRead)
                playerContext.debugLogger?.write("[AudioQueueCB] enqueue buffer success at index \(playerContext.readIndex)\n")
            } else {
                playerContext.debugLogger?.write("[AudioQueueCB] enqueue buffer failed at index \(playerContext.readIndex), error: \(enqueueReslut)\n")
                
            }
        }
        
        if readReslut == kAudioFileEndOfFileError {
            finishPlayback()
            return
        }
        
        if readReslut != noErr {
            playerContext.debugLogger?.write("[AudioQueueCB] failed to read  packets at index \(playerContext.readIndex), error: \(readErr)\n")
        }
    }
    
    
    //
    // MARK: - constructor and descontrocter
    //
    init(url: URL) throws {
        // open audio file to get audio data format and total packs to read
        if let error = callSuccess(withCode: AudioFileOpenURL(url as CFURL,
                         .readPermission,
                         0,
                         &self.playerContext.fileID)) {
            throw error
        }
        
        var asbd = AudioStreamBasicDescription()
        var asbdPropertySize = UInt32(MemoryLayout.size(ofValue: asbd))
        if noErr != AudioFileGetProperty(self.playerContext.fileID!,
                                         kAudioFilePropertyDataFormat,
                                         &asbdPropertySize,
                                         &asbd){
            throw CAAudioPlayerError.unsupportedDataFormat
        }
        
        var packCountPropertySize = UInt32(MemoryLayout.size(ofValue: self.playerContext.totalPacksToRead))
        if noErr != AudioFileGetProperty(self.playerContext.fileID!,
                                         kAudioFilePropertyAudioDataPacketCount,
                                         &packCountPropertySize,
                                         &playerContext.totalPacksToRead) {
            throw CAAudioPlayerError.unsupportedDataFormat
        }
        
        
    
        if let error = callSuccess(withCode: AudioQueueNewOutput(&asbd,
                                                                 CAAudioPlayer.queueCallback,
                                                                 &self.playerContext,
                                                                 nil,
                                                                 nil,
                                                                 0,
                                                                 &self.audioQueue)) {
            throw error
        }
        
        //
        // set decoder magic cookie if any
        if let error = copyAudioFileMagicCookieDataToQueue() {
            cleanup()
            throw error
        }
        
        //
        // set channel layout
        if let error = copyAudioFileChannelLayoutToQueue() {
            cleanup()
            throw error
        }
        
        if noErr != AudioQueueAddPropertyListener(self.audioQueue!,
                                                  kAudioQueueProperty_IsRunning,
                                                  CAAudioPlayer.propertyProcCallback,
                                                  &self.playerContext) {
            throw CAAudioPlayerError.queueError(reason: "Can't add kAudioQueueProperty_IsRunning observer")
        }
        
        //
        // enable time pitch
        var enableTimePatch: UInt32 = 1
        let propertySize = UInt32(MemoryLayout.size(ofValue: enableTimePatch))
        AudioQueueSetProperty(self.audioQueue!,
                              kAudioQueueProperty_EnableTimePitch,
                              &enableTimePatch,
                              propertySize)
        
        //
        // create debug logger
        var pathComponents = url.pathComponents
        var dunmpFileName = pathComponents.removeLast()
        dunmpFileName.removeSubrange(dunmpFileName.lastIndex(of: ".")!..<dunmpFileName.endIndex)
        dunmpFileName.append("_dump.txt")
        pathComponents.append(dunmpFileName)
        let dumpFilePath = pathComponents.joined(separator: "/")
        self.playerContext.debugLogger = TextLogger(path: dumpFilePath)
        
        self.playerContext.player = self
        
    }
    
    deinit {
        cleanup()
    }
    
    //
    // MARK: - player control
    //
    @discardableResult
    public func prepareToPlay() -> Bool {
        guard !self.isPrepared else {
            return true
        }
        
        var asbd = AudioStreamBasicDescription()
        var asbdPropertySize = UInt32(MemoryLayout.size(ofValue: asbd))
        if noErr != AudioQueueGetProperty(self.audioQueue!,
                                          kAudioQueueProperty_StreamDescription,
                                          &asbd,
                                          &asbdPropertySize) {
            self.playerContext.debugLogger?.write("player prepare to play failed, reason: Can't get kAudioQueueProperty_StreamDescription property")
            return false
        }
        self.playerContext.debugLogger?.write("playback fmt: {\(asbd)}\n")
        
        //
        // allocate audio queue buffers
        if let _ = computeAQBufferSize(for: asbd, duration: 0.5) {
            self.playerContext.debugLogger?.write("player prepare failed, reason: Can't compute AQBufferSize")
            return false
        }
        
        self.playerContext.debugLogger?.write("player context: \(self.playerContext)\n")
        let isFmtVBR = asbd.mFramesPerPacket == 0 || asbd.mBytesPerPacket == 0
        
        for _ in 0..<self.queueBufferCount {
            var aqBufferRef: AudioQueueBufferRef?
            if noErr != AudioQueueAllocateBufferWithPacketDescriptions(self.audioQueue!,
                                                                       self.playerContext.aqBufferSize,
                                                                       isFmtVBR ? self.playerContext.expectedNumPacksPerReadCircle : 0,
                                                                       &aqBufferRef) {
                return false
            }
            
            if !playerContext.playToEnd {
                CAAudioPlayer.queueCallback(&self.playerContext, self.audioQueue!, aqBufferRef!)
            }
        }
        
        self.isPrepared = true
        self.playerContext.debugLogger?.write("player prepare success: true\n")
        
        return true
    }
    
    @discardableResult
    public func play() -> Bool {
        if !prepareToPlay() {
            return false
        }
        
        if let error = callSuccess(withCode: AudioQueueStart(self.audioQueue!, nil)) {
            return false
        }
        self.isPlaying = true
        self.isPause = false
        
        return true
    }
    
    @discardableResult
    public func pause() -> Bool {
        if let error = callSuccess(withCode: AudioQueuePause(self.audioQueue!)) {
            return false
        }
        self.isPause = true
        self.isPlaying = true
        
        return true
    }
    
    @discardableResult
    public func stop() -> Bool {
        if let error = callSuccess(withCode: AudioQueueStop(self.audioQueue!, false)) {
            return false
        }
        
        cleanup()
        return true
    }
    
    // MARK:- helper
    private func callSuccess(withCode: OSStatus) -> CAAudioPlayerError? {
        if withCode == noErr {
            return nil
        }
        
        switch withCode {
        case kAudioQueueErr_InvalidDevice:
            return .invaildDevice
        case kAudioFileFileNotFoundError, kAudioFileUnspecifiedError:
            return .fileNotFound
        case kAudioFilePermissionsError:
            return .permissionError
        case kAudioFileUnsupportedFileTypeError:
            return .unsupportedFileType
        case kAudioFileUnsupportedDataFormatError, kAudioQueueErr_CodecNotFound, kAudioQueueErr_InvalidCodecAccess, kAudioFormatUnsupportedDataFormatError:
            return .unsupportedDataFormat
        default:
            return .unknowedError
        }
    }
    
    private func computeAQBufferSize(for fmt: AudioStreamBasicDescription, duration: Float64) -> CAAudioPlayerError? {
        let minimumBufferSize: UInt32 = 0x4000
        var maximumBufferSize: UInt32 = 0x10000
        let frames = UInt32(ceil(fmt.mSampleRate * duration))
        var numPacks = frames
        var packSize = fmt.mBytesPerPacket
        
        if fmt.mFramesPerPacket > 0 {
            numPacks = frames / fmt.mFramesPerPacket
        }
        
        if packSize == 0  {
            var maxPackSize: UInt32 = 0
            var maxPackPropertySize = UInt32(MemoryLayout.size(ofValue: maxPackSize))
            if noErr != AudioFileGetProperty(self.playerContext.fileID!,
                                             kAudioFilePropertyPacketSizeUpperBound,
                                             &maxPackPropertySize,
                                             &maxPackSize) {
                return .queueError(reason: "Can't get kAudioFilePropertyPacketSizeUpperBound property")
            }
            packSize = maxPackSize
        }
        
        if packSize > maximumBufferSize {
            maximumBufferSize = packSize
        }
        
        self.playerContext.aqBufferSize = numPacks * packSize
        self.playerContext.aqBufferSize = min(self.playerContext.aqBufferSize, maximumBufferSize)
        self.playerContext.aqBufferSize = max(self.playerContext.aqBufferSize, minimumBufferSize)
        
        // allocate buffer to read asps for VBR fmt
        self.playerContext.expectedNumPacksPerReadCircle = self.playerContext.aqBufferSize / packSize
        
        return nil
    }
    
    private func copyAudioFileMagicCookieDataToQueue() -> CAAudioPlayerError? {
        var mcdSize: UInt32 = 0
        var mcdPropertSize = UInt32(MemoryLayout.size(ofValue: mcdSize))
        let result = AudioFileGetPropertyInfo(self.playerContext.fileID!,
                                             kAudioFilePropertyMagicCookieData,
                                             &mcdSize,
                                             nil)
        if result == noErr && mcdSize > 0 {
            let mcd = UnsafeMutableRawPointer.allocate(byteCount: Int(mcdSize), alignment: 0)
            defer {
                mcd.deallocate()
            }
            if noErr != AudioFileGetProperty(self.playerContext.fileID!,
                                             kAudioFilePropertyMagicCookieData,
                                             &mcdSize,
                                             mcd) {
                return CAAudioPlayerError.unsupportedDataFormat
            }
            
            if noErr != AudioQueueSetProperty(self.audioQueue!,
                                              kAudioQueueProperty_MagicCookie,
                                              mcd,
                                              mcdSize) {
                return CAAudioPlayerError.unsupportedDataFormat
            }
        }
        
        return nil
    }
    
    
    private func copyAudioFileChannelLayoutToQueue() -> CAAudioPlayerError? {
        var acloSize: UInt32 = 0
        var result = AudioFileGetPropertyInfo(self.playerContext.fileID!,
                                              kAudioFilePropertyChannelLayout,
                                              &acloSize,
                                              nil)
        if result == noErr && acloSize > 0 {
            var acloData = UnsafeMutableRawPointer.allocate(byteCount: Int(acloSize), alignment: 0)
            defer {
                acloData.deallocate()
            }
            if noErr != AudioFileGetProperty(self.playerContext.fileID!,
                                             kAudioFilePropertyChannelLayout,
                                             &acloSize,
                                             &acloData) {
                return CAAudioPlayerError.unsupportedDataFormat
            }
            
            if noErr != AudioQueueSetProperty(self.audioQueue!,
                                              kAudioQueueProperty_ChannelLayout,
                                              &acloData,
                                              acloSize) {
                return CAAudioPlayerError.unsupportedDataFormat
            }
            
        }
        
        return nil
    }
    
    
    private func cleanup() {
        self.isPlaying = false
        self.isPrepared = false
        
        if let af = self.playerContext.fileID {
            AudioFileClose(af)
            self.playerContext.fileID = nil
        }
        
        if let aq = self.audioQueue {
            AudioQueueRemovePropertyListener(self.audioQueue!,
                                               kAudioQueueProperty_IsRunning,
                                               CAAudioPlayer.propertyProcCallback,
                                               &self.playerContext)
            AudioQueueDispose(aq, true)
            self.audioQueue = nil
        }
        
        self.playerContext = PlayerContext()
    }
}



