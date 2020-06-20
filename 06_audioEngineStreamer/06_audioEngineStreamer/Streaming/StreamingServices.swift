//
//  StreamingServices.swift
//  06_audioEngineStreamer
//
//  Created by sy on 2020/6/18.
//  Copyright © 2020 sy. All rights reserved.
//

import Foundation
import AVFoundation

let StreamErrorDomain: String = "StreamErrorDomain"
let StramErrorDownloadingSubDomain: String = "StramErrorDownloadingSubdomain"
let StramErrorParsingSubDomain: String = "StramErrorParsingSubdomain"
let StramErrorConvertingSubDomain: String = "StramErrorConvertingSubdomain"
let StramErrorEngineSubDomain: String = "StramErrorEngineSubDomain"


public protocol StreamingServicesDelegate: AnyObject {
    func streamBecomeReady(_ stream: StreamingServices)
    func streamDidFinish(_ stream: StreamingServices)
    func stream(_ stream: StreamingServices, didChange status: StreamStatus)
    func stream(_ stream: StreamingServices, didRevice error: Error?)
}


public enum StreamStatus {
    public enum PauseReason {
        case notReady
        case buffering
        case waitToPlay
        case manually
    }
    
    case playing
    case pause(PauseReason)
    case stop
    case error
}



public class StreamError: NSError {
    var subDomain: String?
    var error: Error?
    
    init(domain: String, subDomain: String?, error: Error? = nil) {
        self.subDomain = subDomain
        self.error = error
        super.init(domain: domain, code: 0, userInfo: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override var localizedDescription: String {
        let errorDesc = """
{
        domain: \(self.domain),
        subDomain: \(self.subDomain ?? "nil"),
        error: \(self.error?.localizedDescription ?? "nil"),
        userInfo: \(self.userInfo)
}
"""
        return errorDesc
    }
}


public protocol StreamingServices: AnyObject {
    var delegate: StreamingServicesDelegate? { get set }
    
    var streamURL: URL? { get set }
    
    var streamFormat: AVAudioFormat? { get }
    
    var isReady: Bool { get }
    
    var isFinish: Bool { get }
    
    var useCache: Bool { get set }
    
    var error: StreamError? { get }
    
    var status: StreamStatus { get }
    
    var duration: TimeInterval? { get }
    
    var volume: Float { get set }
    
    var currentTime: TimeInterval { get }
    
    var bufferTime: TimeInterval { get }
    
    var scheduleFrameCount: AVAudioFrameCount { get }
    
    @discardableResult
    func play() -> Bool
    
    func pause()
    
    func stop()
    
    @discardableResult
    func seek(to time: TimeInterval) -> Bool
}


extension StreamingServices {
    public var scheduleFrameCount: AVAudioFrameCount {
        return 11025
    }
}
