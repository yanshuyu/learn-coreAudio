//
//  ViewController.swift
//  06_audioEngineStreamer
//
//  Created by sy on 2020/6/16.
//  Copyright © 2020 sy. All rights reserved.
//

import UIKit
import AVFoundation

class ViewController: UIViewController {
    let downloader: DownloadingServices = StreamDownloadServices()
    let parser: ParsingServices = StreamParsingServices()
    var converter: ConvertingServices?
    var timer: Timer?
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        downloader.delegate = self
        downloader.url = URL(string: "https://www.radiantmediaplayer.com/media/bbb-360p.mp4")!
        downloader.useCache = false
        downloader.start()
        
        self.timer = Timer.scheduledTimer(timeInterval: 0.25,
                                          target: self,
                                          selector: #selector(converting),
                                          userInfo: nil,
                                          repeats: true)
    }
    
    @objc func converting() {
        if self.parser.isReadyToProducePacket {
            if self.converter == nil {
                if let commonFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: self.parser.dataFormat!.sampleRate, channels: 2, interleaved: false) {
                    do {
                        self.converter = try StreamConvertingServices(commonFormat, self.parser)
                    } catch {
                    }
                }
            }
        }
        
        guard let converter = self.converter else {
            return
        }
        
        do {
            _ = try converter.convert(11025)
        } catch {
        }
    }
    
    deinit {
        self.timer?.invalidate()
    }

}

extension ViewController: DownloadingServicesDelegate {
    func downloadingServices(_ services: DownloadingServices, didChangeStatus: DownloadingServicesStatus) {
        
    }
    
    func downloadingServices(_ services: DownloadingServices, didFinishWithError: Error?) {
        
    }
    
    func downloadingServices(_ services: DownloadingServices, didReviceData: Data, progress: Float) {
        do {
            try parser.parseData(didReviceData)
        } catch StreamParsingServices.StreamParsingServicesError.canNotOpenStream(let status) {
            print("parser can't open stream, ostatus: \(status)")
        } catch StreamParsingServices.StreamParsingServicesError.unsupportedFileType {
            print("parser error unsupportedFileType")
        } catch StreamParsingServices.StreamParsingServicesError.unsupportedDataFormat {
            print("parser error unsupportedDataFormat")
        } catch StreamParsingServices.StreamParsingServicesError.invalidFile {
            print("parser error invalidFile")
        } catch StreamParsingServices.StreamParsingServicesError.dataUnavailable {
            print("parser error dataUnavailable")
        } catch StreamParsingServices.StreamParsingServicesError.otherError(let status) {
            print("parser got other error, osstatus:\(status)")
        } catch {
            print("parsing got unknowed error: \(error)")
        }
    }
    
    
}

