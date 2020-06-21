//
//  ViewController.swift
//  06_audioEngineStreamer
//
//  Created by sy on 2020/6/16.
//  Copyright © 2020 sy. All rights reserved.
//

import UIKit
import AVFoundation
import os.log

// http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4
class ViewController: UIViewController {
    @IBOutlet weak var bufferTimeLable: UILabel!
    @IBOutlet weak var bufferDurationLable: UILabel!
    @IBOutlet weak var playTimeLable: UILabel!
    @IBOutlet weak var playDurationLable: UILabel!
    @IBOutlet weak var volumeLable: UILabel!
    
    @IBOutlet weak var bufferProgressView: UIProgressView!
    @IBOutlet weak var playSliderView: UISlider!
    @IBOutlet weak var volumeSliderView: UISlider!
    @IBOutlet weak var playPauseButton: UIButton!
    
    @IBOutlet weak var loadingIndicator: UIActivityIndicatorView!
    
    @IBOutlet weak var minRateLable: UILabel!
    @IBOutlet weak var maxRateLable: UILabel!
    @IBOutlet weak var rateSliderView: UISlider!
    
    @IBOutlet weak var minPitchLable: UILabel!
    @IBOutlet weak var maxPitchLable: UILabel!
    @IBOutlet weak var pitchSliderView: UISlider!
    @IBOutlet weak var rateLable: UILabel!
    @IBOutlet weak var pitchLable: UILabel!
    
    
    let streamer: StreamingServices = TimePitchStreamer()
    var isPlaying: Bool = false
    var isSeeking: Bool = false
    var timer: Timer?
    
   
    override func viewDidLoad() {
        super.viewDidLoad()
        streamer.delegate = self
        streamer.useCache = false
        streamer.streamURL = URL(string: "https://m10.music.126.net/20200621165032/25c1031f88354f859f8bb29a58124d47/ymusic/obj/w5zDlMODwrDDiGjCn8Ky/2879481247/b21a/b97b/fd69/10d9abc926f1602216b5c122c5022dab.mp3")
        
        self.playSliderView.addTarget(self, action: #selector(onPlaySliderSeeking(_:)), for: .touchDragInside)
        self.playSliderView.addTarget(self, action: #selector(onPlaySliderSeeking(_:)), for: .touchDragOutside)
        self.playSliderView.addTarget(self, action: #selector(onPlaySliderSeekEnd(_:)), for: .touchUpInside)
        self.playSliderView.addTarget(self, action: #selector(onPlaySliderSeekEnd(_:)), for: .touchUpInside)
        
        self.volumeSliderView.addTarget(self, action: #selector(onVolumeSlideChange(_:)), for: .valueChanged)
        
        toggleLoaddingIndicator(false)
        
        
        self.volumeLable.text = "\(self.streamer.volume)"
        self.volumeSliderView.value = self.streamer.volume
        
        if let streamer = self.streamer as? TimePitchStreamer {
            let minRate: Float = 0.25
            let maxRate: Float = 4
            let minPitch: Float = -2400
            let maxPitch: Float = 2400
            
            self.minRateLable.text = "\(minRate)"
            self.maxRateLable.text = "\(maxRate)"
            self.rateSliderView.minimumValue = minRate
            self.rateSliderView.maximumValue = maxRate
            self.rateSliderView.value = streamer.rate
            
            self.minPitchLable.text = "\(minPitch)"
            self.maxPitchLable.text = "\(maxPitch)"
            self.pitchSliderView.minimumValue = minPitch
            self.pitchSliderView.maximumValue = maxPitch
            self.pitchSliderView.value = streamer.pitch
            
            self.rateSliderView.addTarget(self,
                                          action: #selector(onRateSliderChange(_:)),
                                          for: .valueChanged)
            self.pitchSliderView.addTarget(self,
                                           action: #selector(onPitchSliderChange(_:)),
                                           for: .valueChanged)
            
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.timer = Timer.scheduledTimer(timeInterval: 0.25,
                                          target: self,
                                          selector: #selector(updateUI),
                                          userInfo: nil,
                                          repeats: true)
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        self.timer?.invalidate()
    }
    
    
    @objc func updateUI() {
        let durationText = self.streamer.duration == nil ? "00:00" : formatTime(self.streamer.duration!)
        self.bufferTimeLable.text = formatTime(self.streamer.bufferTime)
        self.bufferDurationLable.text = durationText
        
        var bufferProgress: Float = 0
        if let duration = self.streamer.duration {
            bufferProgress = Float(self.streamer.bufferTime / duration)
        }
        self.bufferProgressView.progress = bufferProgress
        
        var playProgress: Float = 0
        var playTime = self.streamer.currentTime
        if let duration = self.streamer.duration {
            playProgress = self.isSeeking ? self.playSliderView.value : Float(self.streamer.currentTime / duration)
            playTime = self.isSeeking ? duration * Double(playProgress) : playTime
        }
        self.playTimeLable.text = formatTime(playTime)
        self.playDurationLable.text = durationText
        if !self.isSeeking {
            self.playSliderView.value = playProgress
        }
        
        if let _ = self.streamer as? TimePitchStreamer {
            self.rateLable.text = "\(self.rateSliderView.value)"
            self.pitchLable.text = "\(self.pitchSliderView.value)"
        }
    }
    
    @IBAction func onPlayPauseButtonTouch(_ sender: UIButton) {
        if self.isPlaying {
            self.streamer.pause()
            self.playPauseButton.isSelected = false
        } else {
            self.streamer.play()
            self.playPauseButton.isSelected = true
        }
        self.isPlaying = !self.isPlaying
    }
    
    @objc func onVolumeSlideChange(_ sender: UISlider) {
        self.streamer.volume = sender.value
        self.volumeLable.text = "\(sender.value)"
    }
    
    @objc func onPlaySliderSeeking(_ sender: UISlider) {
        self.isSeeking = true
    }
    
    @objc func onPlaySliderSeekEnd(_ sender: UISlider) {
        if self.isSeeking {
            if let duration = self.streamer.duration {
                self.streamer.seek(to: Double(sender.value) * duration)
            }
            self.isSeeking = false
        }
    }
    
    
    @objc func onRateSliderChange(_ sender: UISlider) {
        if let streamer = self.streamer as? TimePitchStreamer {
            streamer.rate = sender.value
        }
    }
    
    @objc func onPitchSliderChange(_ sender: UISlider) {
        if let streamer = self.streamer as? TimePitchStreamer {
            streamer.pitch = sender.value
        }
        
    }
    
}


extension ViewController {
    func formatTime(_ time: TimeInterval) -> String? {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.allowsFractionalUnits = false
        formatter.maximumUnitCount = 2
        formatter.unitsStyle = .positional
        formatter.collapsesLargestUnit = false
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: time)
    }
    
    func toggleLoaddingIndicator(_ show: Bool) {
        if show {
            self.loadingIndicator.isHidden = false
            self.loadingIndicator.startAnimating()
        } else {
            self.loadingIndicator.isHidden = true
            self.loadingIndicator.stopAnimating()
        }
    }
}


extension ViewController: StreamingServicesDelegate {
    func streamBecomeReady(_ stream: StreamingServices) {
        os_log(.debug, "[streamer] stream is ready")
        self.playPauseButton.isEnabled = true
    }
    
    func streamDidFinish(_ stream: StreamingServices) {
        os_log(.debug, "[streamer] stream is finish")
    }
    
    func stream(_ stream: StreamingServices, didChange status: StreamStatus) {
        let st = "\(status)"
        os_log(.debug, "[streamer] status did change to: %@", st)
        switch status {
            case .playing:
                self.playPauseButton.isSelected = true
                toggleLoaddingIndicator(false)
            
            case .pause(let reason):
                if reason == .manually {
                    self.playPauseButton.isSelected = false
                    toggleLoaddingIndicator(false)
                    
                }else if reason == .waitToPlay {
                    toggleLoaddingIndicator(false)
                } else {
                    toggleLoaddingIndicator(true)
                }
                break
            case .stop:
                self.playPauseButton.isSelected = false
                self.isPlaying = false
                toggleLoaddingIndicator(false)
                break
            
            default:
                self.playPauseButton.isEnabled = false
                break
        }
    }
    
    func stream(_ stream: StreamingServices, didRevice error: Error?) {
        if let e = error {
            os_log(.debug, "[streamer] error: %@", e.localizedDescription)
            self.streamer.stop()
        }
    }
}
