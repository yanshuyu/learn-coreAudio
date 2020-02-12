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
    
    private struct PlayerContext: CustomStringConvertible {
        var fileID: AudioFileID?
        var readIndex: Int64 = 0
        var totalPacksToRead: Int64 = 0
        var expectedNumPacksPerReadCircle: UInt32 = 0
        var aspdForReadedPacks: UnsafeMutablePointer<AudioStreamPacketDescription>?
        var aqBufferSize: UInt32 = 0
        var playToEnd = false
        var debugLogger: TextLogger?
        
        var description: String {
            var desc = ""
            let idStr = fileID == nil ? "nil": "\(fileID!)"
            let aspdStr = aspdForReadedPacks == nil ? "nil" : "\(aspdForReadedPacks!)"
            desc += "{\tfileID: " + idStr + "\n"
            desc += "\ttotalPacksToRead: \(totalPacksToRead)\n"
            desc += "\texpectedNumPacksPerReadCircle: \(expectedNumPacksPerReadCircle)\n"
            desc += "\tcurrentReadIndex: \(readIndex)\n"
            desc += "\taspdForReadedPacks: " + aspdStr + "\n"
            desc += "\taqBufferSize: \(aqBufferSize)\n"
            desc += "\tplayReachEnd: \(playToEnd)\t}"
            return desc
        }
    }
    
    private var audioQueue: AudioQueueRef?
    private let queueBufferCount = 3
    private var queueBuffersToFill: [AudioQueueBufferRef]?
    private var playerContext = PlayerContext()
    private var isPrepared = false
    
    public static let queueCallback: AudioQueueOutputCallback = { (inUserData, inAQ, inBuffer) in
        guard let userData = inUserData else {
            return
        }
        
        var playerContext = userData.bindMemory(to: CAAudioPlayer.PlayerContext.self, capacity: 1).pointee
        
        guard !playerContext.playToEnd, let af = playerContext.fileID else {
            return
        }
        
        var numPacksToRead = playerContext.expectedNumPacksPerReadCircle
        if playerContext.readIndex + Int64(numPacksToRead) > playerContext.totalPacksToRead {
            numPacksToRead = UInt32(playerContext.totalPacksToRead - playerContext.readIndex)
        }
        
        guard numPacksToRead > 0 else {
            playerContext.playToEnd = true
            return
        }
        
        playerContext.debugLogger?.write("[AudioQueueCB] try to read \(numPacksToRead) packets at index \(playerContext.readIndex)\n")
        
        var aqBufferSizeInBytes = playerContext.aqBufferSize
        var readReslut = AudioFileReadPacketData(af,
                                            false,
                                            &aqBufferSizeInBytes,
                                            playerContext.aspdForReadedPacks,
                                            playerContext.readIndex,
                                            &numPacksToRead,
                                            inBuffer.pointee.mAudioData)
        if readReslut == kAudioFileEndOfFileError {
            readReslut = noErr
        }
        
        if readReslut == noErr {
             playerContext.debugLogger?.write("[AudioQueueCB] success to read \(numPacksToRead) packets at index \(playerContext.readIndex)\n")
            let enqueueReslut = AudioQueueEnqueueBuffer(inAQ,
                                                inBuffer,
                                                playerContext.aspdForReadedPacks != nil ? numPacksToRead : 0,
                                                playerContext.aspdForReadedPacks)
            if enqueueReslut == noErr {
                playerContext.readIndex += Int64(numPacksToRead)
                playerContext.debugLogger?.write("[AudioQueueCB] enqueue buffer success at index \(playerContext.readIndex)\n")
            } else {
                playerContext.debugLogger?.write("[AudioQueueCB] enqueue buffer failed at index \(playerContext.readIndex), error: \(enqueueReslut)\n")

            }
            
        } else {
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
        // copy encoder magic cookie if any
        if let error = copyEncoderMagicCookieDataToQueue() {
            cleanup()
            throw error
        }
        
        //
        // create debug logger
        var pathComponents = url.pathComponents
        var dunmpFileName = pathComponents.removeLast()
        dunmpFileName.removeSubrange(dunmpFileName.lastIndex(of: ".")!..<dunmpFileName.endIndex)
        dunmpFileName.append("_dump.txt")
        pathComponents.append(dunmpFileName)
        let dumpFilePath = pathComponents.joined(separator: "/")
        self.playerContext.debugLogger = TextLogger(path: dumpFilePath)
        
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
        
        //
        // allocate audio queue buffers
        if let _ = computeAQBufferSize(iBufferDuration: 0.5) {
            self.playerContext.debugLogger?.write("player prepare success: false\n")
            return false
        }
        
        for _ in 0..<self.queueBufferCount {
            if playerContext.playToEnd {
                break
            }
            
            var aqBufferRef: AudioQueueBufferRef?
            if noErr != AudioQueueAllocateBuffer(self.audioQueue!,
                                                 self.playerContext.aqBufferSize,
                                                 &aqBufferRef) {
                self.isPrepared = false
                return false
            }
            
            CAAudioPlayer.queueCallback(&self.playerContext, self.audioQueue!, aqBufferRef!)
        }
        self.isPrepared = true
        
        self.playerContext.debugLogger?.write("player prepare success: true\n")
        
        return true
    }
    
    @discardableResult
    public func start() -> Bool {
        if !prepareToPlay() {
            return false
        }
        
        if let error = callSuccess(withCode: AudioQueueStart(self.audioQueue!, nil)) {
            return false
        }
        return true
    }
    
    @discardableResult
    public func pause() -> Bool {
        if let error = callSuccess(withCode: AudioQueuePause(self.audioQueue!)) {
            return false
        }
        return true
    }
    
    @discardableResult
    public func stop() -> Bool {
        if let error = callSuccess(withCode: AudioQueueStop(self.audioQueue!, true)) {
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
    
    private func computeAQBufferSize(iBufferDuration: Float64) -> CAAudioPlayerError? {
        // is vbr ftm ?
        var asbd = AudioStreamBasicDescription()
        var asbdPropertySize = UInt32(MemoryLayout.size(ofValue: asbd))
        if noErr != AudioQueueGetProperty(self.audioQueue!,
                                          kAudioQueueProperty_StreamDescription,
                                          &asbd,
                                          &asbdPropertySize) {
            return .queueError(reason: "Can't get kAudioQueueProperty_StreamDescription property")
        }
        self.playerContext.debugLogger?.write("playback fmt: {\(asbd)}\n")
        
        var isFmtVBR: UInt32 = 0
        var fmtVBRPropertySize = UInt32(MemoryLayout.size(ofValue: isFmtVBR))
        if noErr != AudioFormatGetProperty(kAudioFormatProperty_FormatIsVBR,
                                           UInt32(MemoryLayout.size(ofValue: asbd)),
                                           &asbd,
                                           &fmtVBRPropertySize,
                                           &isFmtVBR) {
            return .queueError(reason: "Can't get kAudioFormatProperty_FormatIsVBR property")
        }
        self.playerContext.debugLogger?.write("is vbr ftm: \(isFmtVBR)\n")
        
        let minimumBufferSize: UInt32 = 0x5000
        let maximumBufferSize: UInt32 = 0x10000
        var packSize = asbd.mBytesPerPacket
        
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
        
        self.playerContext.aqBufferSize = UInt32(asbd.mSampleRate * iBufferDuration) * packSize
        self.playerContext.aqBufferSize = min(self.playerContext.aqBufferSize, maximumBufferSize)
        self.playerContext.aqBufferSize = max(self.playerContext.aqBufferSize, minimumBufferSize)
        
        // allocate buffer to read asps for VBR fmt
        self.playerContext.expectedNumPacksPerReadCircle = self.playerContext.aqBufferSize / packSize
        if isFmtVBR != 0 {
            self.playerContext.aspdForReadedPacks = UnsafeMutablePointer<AudioStreamPacketDescription>.allocate(capacity: Int(self.playerContext.expectedNumPacksPerReadCircle))
        }
        
        self.playerContext.debugLogger?.write("player context: \(self.playerContext)\n")
        
        return nil
    }
    
    private func copyEncoderMagicCookieDataToQueue() -> CAAudioPlayerError? {
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
    
    private func cleanup() {
        //AudioQueueDispose() does this job ??
//        if let queueBffersToFill = self.queueBuffersToFill, queueBffersToFill.count > 0, let aq = self.audioQueue {
//            queueBffersToFill.forEach {
//                AudioQueueFreeBuffer(aq, $0)
//            }
//        }
        self.queueBuffersToFill = nil
    
        self.playerContext.aspdForReadedPacks?.deallocate()
        self.playerContext.aspdForReadedPacks = nil
        
        if let af = self.playerContext.fileID {
            AudioFileClose(af)
            self.playerContext.fileID = nil
        }
        
        if let aq = self.audioQueue {
            AudioQueueDispose(aq, true)
            self.audioQueue = nil
        }
    }
}



