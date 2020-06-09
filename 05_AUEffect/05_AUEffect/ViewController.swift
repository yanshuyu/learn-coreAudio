//
//  ViewController.swift
//  05_AUEffect
//
//  Created by sy on 2020/6/9.
//  Copyright © 2020 sy. All rights reserved.
//

import UIKit
import AVFoundation
import AudioToolbox

class ViewController: UIViewController {
    var dspGraph: AUGraph?
    var rioAU: AudioUnit?
    var genAU: AudioUnit?
    var mixerAU: AudioUnit?
    var reverbAU: AudioUnit?
    
    var prepareButton: UIButton!
    var startButton: UIButton!
    var stopButton: UIButton!
    var resetButton: UIButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        setUpUI()
        self.startButton.isEnabled = false
        self.stopButton.isEnabled = false
        self.resetButton.isEnabled = false
    }
    
    func setUpUI() {
        let startButton = UIButton()
        startButton.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(startButton)
        startButton.setTitle("start", for: .normal)
        startButton.setTitleColor(.blue, for: .normal)
        startButton.setTitleColor(.gray, for: .highlighted)
        startButton.setTitleColor(.gray, for: .disabled)
        startButton.addTarget(self, action: #selector(onStartButtonTap), for: .touchUpInside)
        
        startButton.centerXAnchor.constraint(equalTo: self.view.centerXAnchor).isActive = true
        startButton.centerYAnchor.constraint(equalTo: self.view.centerYAnchor).isActive = true
        
        let prepareButton = UIButton()
        prepareButton.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(prepareButton)
        prepareButton.setTitle("prepare", for: .normal)
        prepareButton.setTitleColor(.blue, for: .normal)
        prepareButton.setTitleColor(.gray, for: .highlighted)
        prepareButton.setTitleColor(.gray, for: .disabled)
        prepareButton.addTarget(self, action: #selector(onPrepareButtonTap), for: .touchUpInside)
        
        prepareButton.centerXAnchor.constraint(equalTo: self.view.centerXAnchor).isActive = true
        prepareButton.bottomAnchor.constraint(equalTo: startButton.topAnchor, constant: -10).isActive = true
        
        
        let stopButton = UIButton()
        stopButton.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(stopButton)
        stopButton.setTitle("stop", for: .normal)
        stopButton.setTitleColor(.blue, for: .normal)
        stopButton.setTitleColor(.gray, for: .highlighted)
        stopButton.setTitleColor(.gray, for: .disabled)
        stopButton.addTarget(self, action: #selector(onStopButtonTap), for: .touchUpInside)
        
        stopButton.centerXAnchor.constraint(equalTo: self.view.centerXAnchor).isActive = true
        stopButton.topAnchor.constraint(equalTo: startButton.bottomAnchor, constant: 10).isActive = true
        
        let resetButton = UIButton()
        resetButton.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(resetButton)
        resetButton.setTitle("reset", for: .normal)
        resetButton.setTitleColor(.blue, for: .normal)
        resetButton.setTitleColor(.gray, for: .highlighted)
        resetButton.setTitleColor(.gray, for: .disabled)
        resetButton.addTarget(self, action: #selector(onResetButtonTap), for: .touchUpInside)
        
        resetButton.centerXAnchor.constraint(equalTo: self.view.centerXAnchor).isActive = true
        resetButton.topAnchor.constraint(equalTo: stopButton.bottomAnchor, constant: 10).isActive = true
        
        self.startButton = startButton
        self.prepareButton = prepareButton
        self.stopButton = stopButton
        self.resetButton = resetButton
    }
    
    func setUpAudioUnits() {
        guard self.dspGraph == nil else {
            return
        }
        
        let bus0: UInt32 = 0
        let bus1: UInt32 = 1
        
        checkOSStatus(NewAUGraph(&self.dspGraph), message: "failed to create dsp graph")
        
        //
        // create remote io unit
        //
        var rioAUDesc = AudioComponentDescription()
        rioAUDesc.componentType = kAudioUnitType_Output
        rioAUDesc.componentSubType = kAudioUnitSubType_RemoteIO
        rioAUDesc.componentManufacturer = kAudioUnitManufacturer_Apple

        var rioAUNode: AUNode = 0
        checkOSStatus(AUGraphAddNode(self.dspGraph!, &rioAUDesc, &rioAUNode), message: "dsp graph failed to add remote io node")
        
        //
        // create generator unit
        //
        var generatorAUDesc = AudioComponentDescription()
        var genAUNode: AUNode = 0
        generatorAUDesc.componentType = kAudioUnitType_Generator
        generatorAUDesc.componentSubType = kAudioUnitSubType_AudioFilePlayer
        generatorAUDesc.componentManufacturer = kAudioUnitManufacturer_Apple
        checkOSStatus(AUGraphAddNode(self.dspGraph!, &generatorAUDesc, &genAUNode), message: "dsp graph failed to add generator node")
        
        //
        // create reverb effect unit
        //
        var reverbAUNode: AUNode = 0
        var reverbAUDesc = AudioComponentDescription()
        reverbAUDesc.componentType = kAudioUnitType_Effect
        reverbAUDesc.componentSubType = kAudioUnitSubType_Reverb2
        reverbAUDesc.componentManufacturer = kAudioUnitManufacturer_Apple
        checkOSStatus(AUGraphAddNode(self.dspGraph!,
                                     &reverbAUDesc,
                                     &reverbAUNode),
                      message: "dsp graph failed to add reverb node")
        
        var converterAUNode: AUNode = 0
        var converterAUDesc = AudioComponentDescription()
        converterAUDesc.componentType = kAudioUnitType_FormatConverter
        converterAUDesc.componentSubType = kAudioUnitSubType_AUConverter
        converterAUDesc.componentManufacturer = kAudioUnitManufacturer_Apple
        checkOSStatus(AUGraphAddNode(self.dspGraph!,
                                     &converterAUDesc,
                                     &converterAUNode),
                      message: "dsp graph failed to add converter node")
        
        
        //
        // create mixer unit
        //
        var mixerAUDesc = AudioComponentDescription()
        var mixerAUNode: AUNode = 0
        mixerAUDesc.componentType = kAudioUnitType_Mixer
        mixerAUDesc.componentSubType = kAudioUnitSubType_MultiChannelMixer
        mixerAUDesc.componentManufacturer = kAudioUnitManufacturer_Apple
        checkOSStatus(AUGraphAddNode(self.dspGraph!, &mixerAUDesc, &mixerAUNode), message: "dsp graph failed to add mixer node")
        
        checkOSStatus(AUGraphOpen(self.dspGraph!), message: "dsp graph fail to open")
        
        //
        // connect remote unit's input bus to output bus
        //
        checkOSStatus(AUGraphConnectNodeInput(self.dspGraph!,
                                              genAUNode,
                                              bus0,
                                              mixerAUNode,
                                              bus0),
                      message: "dsp graph failed to connect gen -> mixer")
        
        checkOSStatus(AUGraphConnectNodeInput(self.dspGraph!,
                                              rioAUNode,
                                              bus1,
                                              converterAUNode,
                                              bus0),
                      message: "dsp graph failed to connect rio -> reverb")
        
        checkOSStatus(AUGraphConnectNodeInput(self.dspGraph!,
                                              converterAUNode,
                                              bus0,
                                              reverbAUNode,
                                              bus0),
                      message: "dsp graph failed to connect converter -> reverb")
        
        checkOSStatus(AUGraphConnectNodeInput(self.dspGraph!,
                                              reverbAUNode,
                                              bus0,
                                              mixerAUNode,
                                              bus1),
                      message: "dsp graph failed to connect reverb -> mixer")

        checkOSStatus(AUGraphConnectNodeInput(self.dspGraph!,
                                              mixerAUNode,
                                              bus0,
                                              rioAUNode,
                                              bus0),
                      message: "dsp graph failed to connect mixer -> rio")
        
        //
        // config audio units
        //
        var propertySize: UInt32 = 0
        checkOSStatus(AUGraphNodeInfo(self.dspGraph!, rioAUNode, nil, &self.rioAU), message: "dsp graph failed to get remote io unit")
        checkOSStatus(AUGraphNodeInfo(self.dspGraph!, genAUNode, nil, &self.genAU), message: "dsp graph failed to get generator unit")
        checkOSStatus(AUGraphNodeInfo(self.dspGraph!, mixerAUNode, nil, &self.mixerAU), message: "dsp graph failed to get mixer unit")
        checkOSStatus(AUGraphNodeInfo(self.dspGraph!, reverbAUNode, nil, &self.reverbAU), message: "dsp graph failed to get reverb unit")
        //
        // enable remote hardware io
        //
        var onFlag: UInt32 = 1
        checkOSStatus(AudioUnitSetProperty(self.rioAU!,
                                           kAudioOutputUnitProperty_EnableIO,
                                           kAudioUnitScope_Input,
                                           bus1,
                                           &onFlag,
                                           UInt32(MemoryLayout.size(ofValue: onFlag))),
                      message: "failed to enable io on remote unit input bus")
        checkOSStatus(AudioUnitSetProperty(self.rioAU!,
                                           kAudioOutputUnitProperty_EnableIO,
                                           kAudioUnitScope_Output,
                                           bus0,
                                           &onFlag,
                                           UInt32(MemoryLayout.size(ofValue: onFlag))),
                      message: "failed to enable io on remote unit output bus")

        
        //
        // set capture stream format
        //
        var streamFtm = AudioStreamBasicDescription()
        propertySize = UInt32(MemoryLayout.size(ofValue: streamFtm))
        checkOSStatus(AudioUnitGetProperty(self.rioAU!,
                                           kAudioUnitProperty_StreamFormat,
                                           kAudioUnitScope_Input,
                                           bus1,
                                           &streamFtm,
                                           &propertySize),
                      message: "failed to get hardware input format")

        streamFtm.mSampleRate = AVAudioSession.sharedInstance().sampleRate
        checkOSStatus(AudioUnitSetProperty(self.rioAU!,
                                           kAudioUnitProperty_StreamFormat,
                                           kAudioUnitScope_Output,
                                           bus1,
                                           &streamFtm,
                                           UInt32(MemoryLayout.size(ofValue: streamFtm))),
                      message: "failed to set  bus-1 output stream format")
        
        
        //
        // initialize audio unit
        //
        checkOSStatus(AUGraphInitialize(self.dspGraph!), message: "dsp graph failed to initialize")
        

        //
        // set up gen unit
        //
        var bgTrackFileID: AudioFileID?
        var bgTrackPackCnt: UInt64 = 0
        var bgTrackFmtDesc = AudioStreamBasicDescription()
        let url = Bundle.main.url(forResource: "周杰伦-龙卷风 (KTV版伴奏)", withExtension: "mp3")!
        
        checkOSStatus(AudioFileOpenURL(url as CFURL,
                                       .readPermission,
                                       0,
                                       &bgTrackFileID), message: "genAU failed to open track file")
        
        propertySize = UInt32(MemoryLayout.size(ofValue: bgTrackPackCnt))
        checkOSStatus(AudioFileGetProperty(bgTrackFileID!,
                                           kAudioFilePropertyAudioDataPacketCount,
                                           &propertySize,
                                           &bgTrackPackCnt), message: "genAU failed to get kAudioFilePropertyAudioDataPacketCount")
        
        propertySize = UInt32(MemoryLayout.size(ofValue: bgTrackFmtDesc))
        checkOSStatus(AudioFileGetProperty(bgTrackFileID!,
                                           kAudioFilePropertyDataFormat,
                                           &propertySize,
                                           &bgTrackFmtDesc), message: "genAU failed to get kAudioFilePropertyDataFormat")
        
        var ts = AudioTimeStamp()
        ts.mSampleTime = 0
        ts.mFlags = .sampleTimeValid
        var scheReg = ScheduledAudioFileRegion(mTimeStamp: ts,
                                               mCompletionProc: nil,
                                               mCompletionProcUserData: nil,
                                               mAudioFile: bgTrackFileID!,
                                               mLoopCount: UInt32.max,
                                               mStartFrame: 0,
                                               mFramesToPlay: bgTrackFmtDesc.mFramesPerPacket * UInt32(bgTrackPackCnt))
       
        checkOSStatus(AudioUnitSetProperty(self.genAU!,
                                           kAudioUnitProperty_ScheduledFileIDs,
                                           kAudioUnitScope_Global,
                                           0,
                                           &bgTrackFileID,
                                           UInt32(MemoryLayout.size(ofValue: bgTrackFileID))),
                      message: "genAU failed to set kAudioUnitProperty_ScheduledFileIDs")
        
        checkOSStatus(AudioUnitSetProperty(self.genAU!,
                                           kAudioUnitProperty_ScheduledFileRegion,
                                           kAudioUnitScope_Global,
                                           0,
                                           &scheReg,
                                           UInt32(MemoryLayout.size(ofValue: scheReg))),
                      message: "genAU failed to set kAudioUnitProperty_ScheduledFileRegion")
        
        ts.mSampleTime = -1
        ts.mFlags = .sampleTimeValid
        checkOSStatus(AudioUnitSetProperty(self.genAU!,
                                           kAudioUnitProperty_ScheduleStartTimeStamp,
                                           kAudioUnitScope_Global,
                                           0,
                                           &ts,
                                           UInt32(MemoryLayout.size(ofValue: ts))),
                      message: "genAU failed to set kAudioUnitProperty_ScheduleStartTimeStamp")
        
        //
        // set up reverb effect
        //
        var reverbRoomType = AUReverbRoomType.reverbRoomType_LargeHall
        checkOSStatus(AudioUnitSetProperty(self.reverbAU!,
                                           kAudioUnitProperty_ReverbRoomType,
                                           kAudioUnitScope_Global,
                                           0,
                                           &reverbRoomType,
                                           UInt32(MemoryLayout.size(ofValue: reverbRoomType))),
                      message: "reverbAU failed to set kAudioUnitProperty_ReverbRoomType")
        
        //
        // set up mixer
        //
        let bgTrackVolume: Float32 = 0.8
        checkOSStatus(AudioUnitSetParameter(self.mixerAU!,
                                            kMultiChannelMixerParam_Volume,
                                            kAudioUnitScope_Input,
                                            bus0,
                                            bgTrackVolume,
                                            UInt32(MemoryLayout.size(ofValue: bgTrackVolume))),
                      message: "mixerAU failed to set kMultiChannelMixerParam_Volume")
    }
    
    
    @objc func onPrepareButtonTap() {
        print("onPrepareButtonTap")
        setUpAudioUnits()
        
        self.startButton.isEnabled = true
        self.stopButton.isEnabled = true
        self.resetButton.isEnabled = true
        self.prepareButton.isEnabled = false
    }
    
    @objc func onStartButtonTap() {
        print("onStartButtonTap")
        startCapture()
    }
    
    @objc func onStopButtonTap() {
        print("onStopButtonTap")
        stopCapture()
    }
    
    @objc func onResetButtonTap() {
        print("onResetButtonTap")
        guard let _ = self.dspGraph else { return }
        stopCapture()
        //checkOSStatus(AudioUnitUninitialize(self.rioAU!), message: "failed to uninitailize remote unit")
        checkOSStatus(AUGraphUninitialize(self.dspGraph!), message: "dsp graph failed to uninitialize")
        checkOSStatus(AUGraphClose(self.dspGraph!), message: "dsp graph failed to close")
        self.dspGraph = nil
        self.rioAU = nil
        self.genAU = nil
        self.mixerAU = nil
        self.prepareButton.isEnabled = true
        self.startButton.isEnabled = false
        self.stopButton.isEnabled = false
        self.resetButton.isEnabled = false
    }
    
    func startCapture() {
        //checkOSStatus(AudioOutputUnitStart(self.rioAU!), message: "failed to start capture")
        checkOSStatus(AUGraphStart(self.dspGraph!), message: "dsp graph failed to start")
    }
    
    func stopCapture() {
        //checkOSStatus(AudioOutputUnitStop(self.rioAU!), message: "failed to stop capture")
        checkOSStatus(AUGraphStop(self.dspGraph!), message: "dsp graph failed to stop")
    }
    
    func checkOSStatus(_ status: OSStatus, message: String = "") {
        guard status != noErr else {
            return
        }
        print("Error: \(status)(\(status.fourCharaterCode)), message: \(message)")
        fatalError()
    }
    
}



extension Int32 {
    var fourCharaterCode: String {
        let codeUints = [
            UInt16(self >> 24 & 0xff),
            UInt16(self >> 16 & 0xff),
            UInt16(self >> 8 & 0xff),
            UInt16(self & 0xff),
        ]
        return String(utf16CodeUnits: codeUints, count: 4)
    }
}

