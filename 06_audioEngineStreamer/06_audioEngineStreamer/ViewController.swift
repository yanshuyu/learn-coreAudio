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
    
    let streamer: StreamingServices = Streamer()
    var isPlaying: Bool = false
    var isSeeking: Bool = false
    var timer: Timer?
    
    
   
    override func viewDidLoad() {
        super.viewDidLoad()
        streamer.delegate = self
        streamer.useCache = false
        streamer.streamURL = URL(string: "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4")
        
        self.playSliderView.addTarget(self, action: #selector(onPlaySliderSeeking(_:)), for: .touchDragInside)
        self.playSliderView.addTarget(self, action: #selector(onPlaySliderSeeking(_:)), for: .touchDragOutside)
        self.playSliderView.addTarget(self, action: #selector(onPlaySliderSeekEnd(_:)), for: .touchUpInside)
        self.playSliderView.addTarget(self, action: #selector(onPlaySliderSeekEnd(_:)), for: .touchUpInside)
        
        self.volumeSliderView.addTarget(self, action: #selector(onVolumeSlideChange(_:)), for: .valueChanged)
        
        toggleLoaddingIndicator(false)
        
        
        self.volumeLable.text = "\(self.streamer.volume)"
        self.volumeSliderView.value = self.streamer.volume
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
