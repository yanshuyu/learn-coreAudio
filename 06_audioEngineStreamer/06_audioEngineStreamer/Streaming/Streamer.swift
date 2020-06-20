//
//  AudioStreamer.swift
//  06_audioEngineStreamer
//
//  Created by sy on 2020/6/18.
//  Copyright © 2020 sy. All rights reserved.
//

import Foundation
import AVFoundation

public enum EngineError: Error {
    case missingStreamFormat
    case failToStart(Error)
}


public class Streamer: NSObject, StreamingServices {
    public var delegate: StreamingServicesDelegate?
    
    fileprivate var _streamURL: URL? = nil
    
    public  var streamURL: URL? {
        set {
            replaceStreamURL(newValue)
        }
        get {
            return self._streamURL
        }
    }
    
    public var streamFormat: AVAudioFormat? {
        return AVAudioFormat(commonFormat: .pcmFormatFloat32,
                             sampleRate: 44100,
                             channels: 2,
                             interleaved: false)
    }
    
    public fileprivate(set) var isReady: Bool = false {
        didSet {
            if !oldValue && self.isReady {
                DispatchQueue.main.async { [weak self] in
                    guard let strongSelf = self else { return }
                    strongSelf.delegate?.streamBecomeReady(strongSelf)
                }
            }
        }
    }
    
    public var isFinish: Bool {
        return self.isScheduleCompelet && self.isBufferEmpty
    }
    
    public var useCache: Bool {
        set {
            self.downloader.useCache = newValue
        }
        get {
            return self.downloader.useCache
        }
    }
    
    public fileprivate(set) var status: StreamStatus = .stop {
        didSet {
            DispatchQueue.main.async { [weak self] in
                guard let strongSelf = self else { return }
                strongSelf.delegate?.stream(strongSelf, didChange: strongSelf.status)
            }
        }
    }
    
    public var error: StreamError? {
        didSet {
            if self.error != nil {
                DispatchQueue.main.async { [weak self] in
                    guard let strongSelf = self else { return }
                    strongSelf.delegate?.stream(strongSelf, didRevice: strongSelf.error)
                }
            }
        }
    }
    
    
    public var duration: TimeInterval? {
        return self.parser.duration
    }
    
    public var volume: Float {
        set {
            let vol = max(min(newValue, 1), 0)
            self.engine.mainMixerNode.outputVolume = vol
        }
        get {
            return self.engine.mainMixerNode.outputVolume
        }
    }
    
    public fileprivate(set) var scheduleFrameCount: AVAudioFrameCount
    
    public var currentTime: TimeInterval {
        return self.seekOffsetTime + self.renderOffsetTime
    }
    fileprivate var seekOffsetTime: TimeInterval = 0
    
    public var bufferTime: TimeInterval {
        guard let _ = self.duration else {
            return 0
        }
        return self.duration! * Double(self.bufferProgress)
    }
    

    
    fileprivate var player = AVAudioPlayerNode()
    fileprivate var engine = AVAudioEngine()
    
    fileprivate var downloader: DownloadingServices = StreamDownloadServices()
    fileprivate var parser: ParsingServices = StreamParsingServices()
    fileprivate var converter: ConvertingServices?
    fileprivate var scheduleTimer: Timer?
    
    fileprivate var needResumePlayback = false
    fileprivate var renderOffsetTime: TimeInterval = 0
    fileprivate var bufferProgress: Float = 0
    fileprivate var isScheduleCompelet: Bool {
        if let _ = self.converter {
            return self.converter!.isConvertingCompeleted
        }
        return false
    }
    
    fileprivate var isBufferEmpty: Bool {
        return self.pcmBuffers.count <= 0
    }
    fileprivate var pcmBuffers: Set<AVAudioPCMBuffer> = []
   
    
    
    public init(_ url: URL? = nil, _ scheduleFrameCount: AVAudioFrameCount = 22050) {
        self.scheduleFrameCount = scheduleFrameCount
        super.init()
        self.attachNodes()
        self.connectNodes()
        self.engine.prepare()
        self.scheduleTimer = Timer.scheduledTimer(timeInterval: TimeInterval(Double(self.scheduleFrameCount) / Double(44100) * 0.5),
                                                  target: self,
                                                  selector: #selector(scheudleNextAudioBuffer),
                                                  userInfo: nil,
                                                  repeats: true)
        replaceStreamURL(url)
    }
    
    deinit {
        self.downloader.stop()
        self.scheduleTimer?.invalidate()
        stop()
    }
    
    
    //
    // MARK: - Engine configuration
    //
    public func attachNodes() {
        self.engine.attach(self.player)
        
    }
    
    public func connectNodes() {
        self.engine.connect(self.player, to: self.engine.mainMixerNode, format: nil)
    }
    
 
    
    //
    // MARK: - Playback control
    //
    @discardableResult
    public func play() -> Bool {
        switch self.status {
            case .playing:
                return true
            case .error:
                return false

            default :
                break
        }
        
        if self.isFinish {
            return false
        }
        
        if !self.isReady {
            self.status = .pause(.notReady)
            self.needResumePlayback = true
            return false
        }
        
        if self.isBufferEmpty {
            self.status = .pause(.buffering)
            self.needResumePlayback = true
            return false
        }
    
        return doPlay()
    }
    
    public func pause() {
        switch self.status {
            case .error, .pause(.manually), .stop:
                return
            default:
                break
        }
        
        self.player.pause()
        self.status = .pause(.manually)
        self.needResumePlayback = false
    }
    
    
    public func stop() {
        if case StreamStatus.stop = self.status {
            return
        }
        
        self.downloader.stop()
        self.player.stop()
        self.engine.stop()
        self.status = .stop
        self.needResumePlayback = false
    }
    
    @discardableResult
    public func seek(to time: TimeInterval) -> Bool {
        guard let converter = self.converter else {
            return false
        }
        
        if case StreamStatus.error = self.status {
            return false
        }
        
        if case StreamStatus.playing = self.status {
            self.needResumePlayback = true
        }
        
        self.player.stop()
        if !converter.seek(to: time) {
            return false
        }
        
        self.pcmBuffers.removeAll()
        self.seekOffsetTime = time
        self.renderOffsetTime = 0
        return true
    }
    
}


extension Streamer {
    @objc fileprivate func scheudleNextAudioBuffer() {
        if case StreamStatus.error = self.status {
            return
        }
        
        if let nodeRenderTime =  self.player.lastRenderTime,
            let playerRenderTime = self.player.playerTime(forNodeTime: nodeRenderTime) {
            self.renderOffsetTime = Double(playerRenderTime.sampleTime) / playerRenderTime.sampleRate
        }

        if self.isFinish && self.engine.isRunning {
            DispatchQueue.main.async { [weak self] in
                guard let strongSelf = self else { return }
                strongSelf.delegate?.streamDidFinish(strongSelf)
            }
            self.stop()
            return
        }
        
        guard let streamConverter = self.converter, !self.isScheduleCompelet else {
                 return
         }
        
        if case StreamStatus.playing = self.status {
            if self.isBufferEmpty {
                self.status = .pause(.buffering)
                self.needResumePlayback = true
            }
        }
        
        do {
            let nextPCMBuffer = try streamConverter.convert(self.scheduleFrameCount)
            self.pcmBuffers.insert(nextPCMBuffer)
            
            self.player.scheduleBuffer(nextPCMBuffer) { [weak self] in
                guard let strongSelf = self else {
                    return
                }
                strongSelf.pcmBuffers.remove(nextPCMBuffer)
                if strongSelf.isBufferEmpty {
                    strongSelf.status = .pause(.buffering)
                }
            }
            
            if !self.isReady {
                self.status = .pause(.waitToPlay)
                self.isReady = true
            }
            
            if case StreamStatus.pause(.buffering) = self.status {
                self.status = .pause(.waitToPlay)
            }
            
            if self.needResumePlayback {
                play()
            }
            
        } catch ConvertingError.failedToAllocatePCMBuffer {
            self.error = StreamError(domain: StreamErrorDomain,
                                     subDomain: StramErrorConvertingSubDomain,
                                     error: ConvertingError.failedToAllocatePCMBuffer)
            self.status = .error
            
        } catch ConvertingError.formatNotSupported {
            self.error = StreamError(domain: StreamErrorDomain,
                                     subDomain: StramErrorConvertingSubDomain,
                                     error: ConvertingError.formatNotSupported)
            self.status = .error
            
        } catch ConvertingError.hardwareWasOccupied {
            self.error = StreamError(domain: StreamErrorDomain,
                                     subDomain: StramErrorConvertingSubDomain,
                                     error: ConvertingError.hardwareWasOccupied)
            self.status = .error
            
        } catch ConvertingError.invailedParser {
            self.error = StreamError(domain: StreamErrorDomain,
                                     subDomain: StramErrorConvertingSubDomain,
                                     error: ConvertingError.invailedParser)
            self.status = .error
            
        } catch ConvertingError.noAvaliableHardware {
            self.error = StreamError(domain: StreamErrorDomain,
                                     subDomain: StramErrorConvertingSubDomain,
                                     error: ConvertingError.noAvaliableHardware)
            self.status = .error
            
        } catch ConvertingError.otherError(let osStatus) {
            self.error = StreamError(domain: StreamErrorDomain,
                                     subDomain: StramErrorConvertingSubDomain,
                                     error: ConvertingError.otherError(osStatus))
            self.status = .error
        } catch ConvertingError.noEnoughData {
            
        } catch ConvertingError.endOfStream {
               
                   
        } catch {
            self.error = StreamError(domain: StreamErrorDomain,
                                     subDomain: nil)
            self.status = .error
        }
        
     }
    
    
     fileprivate func replaceStreamURL(_ url: URL?) {
        reset()
        
        self._streamURL = url
        guard let _ = self._streamURL else {
            return
        }
       
        self.downloader.url = self._streamURL
        self.downloader.delegate = self
        self.status = .pause(.notReady)
        self.downloader.start()
    }
    
    private func reset() {
        if self.player.isPlaying {
            self.player.pause()
        }
        self.downloader.stop()
        self.parser = StreamParsingServices()
        self.converter = nil
        self.pcmBuffers.removeAll()
        self.needResumePlayback = false
        self.isReady = false
        self.error = nil
        self.seekOffsetTime = 0
        self.renderOffsetTime = 0
    }

    @discardableResult
    fileprivate func doPlay() -> Bool {
        do {
            if !self.engine.isRunning {
                try self.engine.start()
            }
            self.player.play()

        } catch {
            self.error = StreamError(domain: StreamErrorDomain,
                                     subDomain: StramErrorEngineSubDomain,
                                     error: EngineError.failToStart(error))
            self.status = .error
            return false
        }

        self.status = .playing
        self.needResumePlayback = false

        return true
    }

}


extension Streamer: DownloadingServicesDelegate {
    public func downloadingServices(_ services: DownloadingServices, didChangeStatus: DownloadingStatus) {
        
    }
    
    public func downloadingServices(_ services: DownloadingServices, didFinishWithError: Error?) {
        if self.downloader.status == .failed {
            self.error = StreamError(domain: StreamErrorDomain, subDomain: StramErrorDownloadingSubDomain, error: didFinishWithError)
            self.status = .error
        }
    }
    
    public func downloadingServices(_ services: DownloadingServices, didReviceData: Data, progress: Float) {
        // parsing audio binary data chunk by chunk
        do {
            try self.parser.parseData(didReviceData)
            self.bufferProgress = progress
            
        } catch ParsingError.canNotOpenStream(let OSStatus) {
            self.error = StreamError(domain: StreamErrorDomain,
                                     subDomain: StramErrorParsingSubDomain,
                                     error: ParsingError.canNotOpenStream(OSStatus))
            self.status = .error
            return
            
        } catch ParsingError.invalidFile {
            self.error = StreamError(domain: StreamErrorDomain,
                                     subDomain: StramErrorParsingSubDomain,
                                     error: ParsingError.invalidFile)
            self.status = .error
            return
            
        } catch ParsingError.otherError(let osStatus) {
            self.error = StreamError(domain: StreamErrorDomain,
                                     subDomain: StramErrorParsingSubDomain,
                                     error: ParsingError.otherError(osStatus))
            self.status = .error
            return
            
        } catch ParsingError.dataUnavailable {
            
            
        } catch {
            self.error = StreamError(domain: StreamErrorDomain, subDomain: nil)
            self.status = .error
            return
        }
        
        // create converter when parser parse enough data
        if self.parser.isReadyToProducePacket && self.converter == nil {
            if let _ = self.parser.dataFormat {
                if self.streamFormat == nil {
                    self.error = StreamError(domain: StreamErrorDomain,
                                             subDomain: StramErrorEngineSubDomain,
                                             error: EngineError.missingStreamFormat)
                    self.status = .error
                    return
                }
                
                do {
                    self.converter =  try StreamConvertingServices(self.streamFormat!, self.parser)
                } catch ConvertingError.invailedParser {
                    self.error = StreamError(domain: StreamErrorDomain,
                                             subDomain: StramErrorConvertingSubDomain,
                                             error: ConvertingError.invailedParser)
                    self.status = .error
                    
                } catch ConvertingError.formatNotSupported {
                    self.error = StreamError(domain: StreamErrorDomain,
                                             subDomain: StramErrorConvertingSubDomain,
                                             error: ConvertingError.formatNotSupported)
                    self.status = .error
                    
                } catch ConvertingError.noAvaliableHardware {
                    self.error = StreamError(domain: StreamErrorDomain,
                                             subDomain: StramErrorConvertingSubDomain,
                                             error: ConvertingError.noAvaliableHardware)
                    self.status = .error
                    
                } catch ConvertingError.otherError(let osStatus) {
                    self.error = StreamError(domain: StreamErrorDomain,
                                             subDomain: StramErrorConvertingSubDomain,
                                             error: ConvertingError.otherError(osStatus))
                    self.status = .error
                    
                } catch {
                    self.error = StreamError(domain: StreamErrorDomain, subDomain: nil)
                    self.status = .error
                }
            }
        }
    }
    
    
}
