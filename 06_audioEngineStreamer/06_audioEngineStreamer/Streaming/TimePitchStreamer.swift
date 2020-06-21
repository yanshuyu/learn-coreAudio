//
//  TimePitchStreamer.swift
//  06_audioEngineStreamer
//
//  Created by sy on 2020/6/20.
//  Copyright © 2020 sy. All rights reserved.
//

import Foundation
import AVFoundation

public class TimePitchStreamer: Streamer {
    
    internal lazy var timePitchEffect = AVAudioUnitTimePitch()
    
    public var pitch: Float {
        set {
            self.timePitchEffect.pitch = newValue
        }
        get {
            return self.timePitchEffect.pitch
        }
    }
    
    public var rate: Float {
        set {
            self.timePitchEffect.rate = newValue
        }
        get {
            return self.timePitchEffect.rate
        }
    }
    
    public override func attachNodes() {
        super.attachNodes()
        self.engine.attach(self.timePitchEffect)
    }
    
    public override func connectNodes() {
        self.engine.connect(self.player, to: self.timePitchEffect, format: self.streamFormat!)
        self.engine.connect(self.timePitchEffect, to: self.engine.mainMixerNode, format: self.streamFormat!)
        
    }
    
}
