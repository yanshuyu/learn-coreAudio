//: A UIKit based Playground for presenting user interface
  
import UIKit
import AudioToolbox
import PlaygroundSupport



class MyViewController : UIViewController {
    var auGrap: AUGraph?
    var audioFileID: AudioFileID?
    var audioStreamBasicDesc: AudioStreamBasicDescription?
    var audioPackCount: UInt64 = 0
    
    var lable: UILabel?
    var loadButton: UIButton!
    var playButton: UIButton!
    var stopButton: UIButton!
    var resetButton: UIButton!
    
    var isPlaying = false {
        didSet {
            self.playButton.isEnabled = !self.isPlaying
            self.stopButton.isEnabled = self.isPlaying
            self.resetButton .isEnabled = !self.isPlaying
        }
    }
    
    override func loadView() {
        let view = UIView()
        view.backgroundColor = .white
        self.view = view
        
        setUpUI()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.isPlaying = false
        self.playButton.isEnabled = false
        self.resetButton.isEnabled = false
    }
    
    @objc func onLoadButtonClick() {
        print("onPlayButtonClick()")
        let url = Bundle.main.url(forResource: "01 Star Gazing", withExtension: "m4a")!
        setUpAudioFile(url)
        setupAUGrap()
        self.lable?.text = "load success"
        self.playButton.isEnabled = true
        self.resetButton.isEnabled = true
        self.loadButton.isEnabled = false
    }
    
    @objc func onPlayButtonClick() {
        print("onPlayButtonClick()")
        startAUGrap()
        self.isPlaying = true
    }
    
    @objc func onStopButtonClick() {
        print("onStopButtonClick()")
        stopAUGrap()
        self.isPlaying = false
    }
    
    @objc func onResetButtonClick() {
        print("onResetButtonClick()")
        tearDownAUGrap()
        tearDownAudioFile()
        self.loadButton.isEnabled = true
        self.resetButton.isEnabled = false
    }
    
    func setUpUI() {
        
        self.lable = UILabel()
        self.view.addSubview(self.lable!)
        self.lable?.text = "Please click Load button for loading"
        
        self.lable?.translatesAutoresizingMaskIntoConstraints = false
        self.lable?.centerXAnchor.constraint(equalTo: self.view.centerXAnchor).isActive = true
        self.lable?.topAnchor.constraint(equalTo: self.view.topAnchor, constant: 20).isActive = true
        
        
        let loadButton = UIButton()
        self.view.addSubview(loadButton)
        loadButton.translatesAutoresizingMaskIntoConstraints = false
        loadButton.backgroundColor = .blue
        loadButton.layer.cornerRadius = 16
        loadButton.setTitle("Load", for: .normal)
        loadButton.setTitleColor(.white, for: .normal)
        loadButton.setTitleColor(.lightGray, for: .disabled)
        loadButton.addTarget(self, action: #selector(onLoadButtonClick), for: .touchUpInside)
        
        loadButton.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 40).isActive = true
        loadButton.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -40).isActive = true
        loadButton.heightAnchor.constraint(equalToConstant: 60).isActive = true
        loadButton.centerXAnchor.constraint(equalTo: self.lable!.centerXAnchor).isActive = true
        loadButton.topAnchor.constraint(equalTo: self.lable!.bottomAnchor, constant: 20).isActive = true
        
        let playButton = UIButton(type: .system)
        self.view.addSubview(playButton)
        playButton.translatesAutoresizingMaskIntoConstraints = false
        playButton.backgroundColor = .blue
        playButton.layer.cornerRadius = 16
        playButton.setTitle("Play", for: .normal)
        playButton.setTitleColor(.white, for: .normal)
        playButton.setTitleColor(.lightGray, for: .disabled)
        playButton.addTarget(self, action: #selector(onPlayButtonClick), for: .touchUpInside)
        
        playButton.leadingAnchor.constraint(equalTo: loadButton.leadingAnchor).isActive = true
        playButton.trailingAnchor.constraint(equalTo: loadButton.trailingAnchor).isActive = true
        playButton.heightAnchor.constraint(equalTo: loadButton.heightAnchor).isActive = true
        playButton.centerXAnchor.constraint(equalTo: loadButton.centerXAnchor).isActive = true
        playButton.topAnchor.constraint(equalTo: loadButton.bottomAnchor, constant: 20).isActive = true
        
        let stopButton = UIButton(type: .system)
        self.view.addSubview(stopButton)
        stopButton.translatesAutoresizingMaskIntoConstraints = false
        stopButton.backgroundColor = .blue
        stopButton.layer.cornerRadius = 16
        stopButton.setTitle("Stop", for: .normal)
        stopButton.setTitleColor(.white, for: .normal)
        stopButton.setTitleColor(.lightGray, for: .disabled)
        stopButton.addTarget(self, action: #selector(onStopButtonClick), for: .touchUpInside)
        
        stopButton.leadingAnchor.constraint(equalTo: loadButton.leadingAnchor).isActive = true
        stopButton.trailingAnchor.constraint(equalTo: loadButton.trailingAnchor).isActive = true
        stopButton.heightAnchor.constraint(equalTo: loadButton.heightAnchor).isActive = true
        stopButton.centerXAnchor.constraint(equalTo: loadButton.centerXAnchor).isActive = true
        stopButton.topAnchor.constraint(equalTo: playButton.bottomAnchor, constant: 20).isActive = true
        
        let resetButton = UIButton(type: .system)
        self.view.addSubview(resetButton)
        resetButton.translatesAutoresizingMaskIntoConstraints = false
        resetButton.backgroundColor = .blue
        resetButton.layer.cornerRadius = 16
        resetButton.setTitle("Reset", for: .normal)
        resetButton.setTitleColor(.white, for: .normal)
        resetButton.setTitleColor(.lightGray, for: .disabled)
        resetButton.addTarget(self, action: #selector(onResetButtonClick), for: .touchUpInside)
        
        resetButton.leadingAnchor.constraint(equalTo: loadButton.leadingAnchor).isActive = true
        resetButton.trailingAnchor.constraint(equalTo: loadButton.trailingAnchor).isActive = true
        resetButton.heightAnchor.constraint(equalTo: loadButton.heightAnchor).isActive = true
        resetButton.centerXAnchor.constraint(equalTo: loadButton.centerXAnchor).isActive = true
        resetButton.topAnchor.constraint(equalTo: stopButton.bottomAnchor, constant: 20).isActive = true
        

        self.loadButton = loadButton
        self.playButton = playButton
        self.stopButton = stopButton
        self.resetButton = resetButton
    }
    
    func setUpAudioFile(_ url: URL) {
        checkOSStatus(AudioFileOpenURL(url as CFURL, .readPermission, 0, &self.audioFileID),
                      message: "setUpAudioFile() -> failed to open file.")
        self.audioFileID
        
        self.audioStreamBasicDesc = AudioStreamBasicDescription()
        var ioDataSize: UInt32 = UInt32(MemoryLayout.size(ofValue: self.audioStreamBasicDesc!))
        checkOSStatus(AudioFileGetProperty(self.audioFileID!,
                                           kAudioFilePropertyDataFormat,
                                           &ioDataSize,
                                           &self.audioStreamBasicDesc),
                      message: "setUpAudioFile() -> failed to get audio file data format.")
        
        self.audioStreamBasicDesc
        
        ioDataSize = UInt32(MemoryLayout.size(ofValue: self.audioPackCount))
        checkOSStatus(AudioFileGetProperty(self.audioFileID!,
                                           kAudioFilePropertyAudioDataPacketCount,
                                           &ioDataSize,
                                           &self.audioPackCount),
                      message: "setUpAudioFile() -> failed to get pack count of audio file.")
        self.audioPackCount
    }

    func setupAUGrap() {
        // create AUGrap
        checkOSStatus(NewAUGraph(&self.auGrap), message: "setupAUGrap() -> failed to create AUGrap.")
        
        // create audio unit nodes
        var audioCompDesc = AudioComponentDescription()
        audioCompDesc.componentType = kAudioUnitType_Generator
        audioCompDesc.componentSubType = kAudioUnitSubType_AudioFilePlayer
        audioCompDesc.componentManufacturer = kAudioUnitManufacturer_Apple
        var auFilePlayerNode: AUNode = 0
        checkOSStatus(AUGraphAddNode(self.auGrap!, &audioCompDesc, &auFilePlayerNode),
                      message: "setupAUGrap() -> failed to add file player node.")
        
        audioCompDesc.componentType = kAudioUnitType_Output
        //audioCompDesc.componentSubType = kAudioUnitSubType_DefaultOutput  // Mac os only
        audioCompDesc.componentSubType = kAudioUnitSubType_RemoteIO // Ios only
        audioCompDesc.componentManufacturer = kAudioUnitManufacturer_Apple
        var auOutputNode: AUNode = 0
        checkOSStatus(AUGraphAddNode(self.auGrap!, &audioCompDesc, &auOutputNode),
                      message: "setupAUGrap() -> failed to add output node.")
        
        
        // open all audio unit nodes
        checkOSStatus(AUGraphOpen(self.auGrap!), message: "setupAUGrap() -> failed to open auGrap.")
        
        // set up connections between audio units
        checkOSStatus(AUGraphConnectNodeInput(self.auGrap!, auFilePlayerNode, 0, auOutputNode, 0),
                      message: "setupAUGrap() -> failed to connect audio units.")
  
        // allocate resource for all audio unit
        checkOSStatus(AUGraphInitialize(self.auGrap!), message: "setupAUGrap() -> failed to initialize auGrap.")
        
        // set up audio units
        var filePlayerAU: AudioUnit?
        checkOSStatus(AUGraphNodeInfo(self.auGrap!, auFilePlayerNode, nil, &filePlayerAU),
                      message: "setupAUGrap() -> failed to get auidio unit.")
        
       checkOSStatus( AudioUnitSetProperty(filePlayerAU!,
                                   kAudioUnitProperty_ScheduledFileIDs,
                                   kAudioUnitScope_Global,
                                   0,
                                   &self.audioFileID,
                                   UInt32(MemoryLayout<AudioFileID>.size) ),
                      message: "setupAUGrap() -> failed to set audio file player unit's schedule file id.")
        
        
        
        var timeStamp = AudioTimeStamp()
        timeStamp.mSampleTime = 0
        timeStamp.mFlags = AudioTimeStampFlags.sampleTimeValid
        let frameCount = UInt64(self.audioStreamBasicDesc!.mFramesPerPacket) * self.audioPackCount
        var scheduleRegion = ScheduledAudioFileRegion(mTimeStamp: timeStamp,
                                                      mCompletionProc: nil,
                                                      mCompletionProcUserData: nil,
                                                      mAudioFile: self.audioFileID!,
                                                      mLoopCount: 1,
                                                      mStartFrame: 0,
                                                      mFramesToPlay: UInt32(frameCount))
        checkOSStatus( AudioUnitSetProperty(filePlayerAU!,
                               kAudioUnitProperty_ScheduledFileRegion,
                               kAudioUnitScope_Global,
                               0,
                               &scheduleRegion,
                               UInt32(MemoryLayout.size(ofValue: scheduleRegion))),
                       message: "setupAUGrap() -> failed to set audio file player unit's schedule region.")
        
        
        var startTime = AudioTimeStamp()
        startTime.mFlags = AudioTimeStampFlags.sampleTimeValid
        startTime.mSampleTime = -1
        checkOSStatus(AudioUnitSetProperty(filePlayerAU!,
                                           kAudioUnitProperty_ScheduleStartTimeStamp,
                                           kAudioUnitScope_Global,
                                           0,
                                           &startTime,
                                           UInt32(MemoryLayout.size(ofValue: startTime))),
                      message: "setupAUGrap() -> failed to set audio file player uint's schedule start time.")
        
    }
    
    func startAUGrap() {
        guard let grap = self.auGrap, !self.isPlaying else {
            return
        }
        
        checkOSStatus(AUGraphStart(grap), message: "startAUGrap() -> failed to start auGrap.")
        self.lable?.text = "play success"
    }
    
    func stopAUGrap() {
        guard let grap = self.auGrap, self.isPlaying else {
            return
        }
        
        checkOSStatus(AUGraphStop(grap), message: "stopAUGrap() -> failed to stop auGrap.")
        self.lable?.text = "stop success"
    }
    
    func tearDownAUGrap() {
        if self.isPlaying {
            stopAUGrap()
        }
        
        checkOSStatus(AUGraphUninitialize(self.auGrap!), message: "tearDownAUGrap() -> failed to unInitailize auGrap.")
        checkOSStatus(AUGraphClose(self.auGrap!), message: "tearDownAUGrap() -> failed to close auGrap.")
        self.auGrap = nil
        self.lable?.text = "auGrap tear down success"
    }
    
    func tearDownAudioFile() {
        guard let fileID = self.audioFileID else {
            return
        }
        
        checkOSStatus( AudioFileClose(fileID), message: "tearDownAudioFile() -> failed to close audio file.")
        self.audioFileID = nil
        self.audioStreamBasicDesc = nil
        self.audioPackCount = 0
    }
    
    func checkOSStatus(_ status: OSStatus, message: String = "") {
        guard status != noErr else {
            return
        }
        self.lable?.text = "Error: \(status)(\(status.fourCharaterCode)), message: \(message)"
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

// Present the view controller in the Live View window
PlaygroundPage.current.liveView = MyViewController()
