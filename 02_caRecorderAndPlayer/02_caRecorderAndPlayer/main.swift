//
//  main.swift
//  02_caRecorderAndPlayer
//
//  Created by sy on 2019/12/21.
//  Copyright © 2019 sy. All rights reserved.
//

import Foundation
import CoreGraphics


func handleRecorderError(_ error: CAAudioRecorder.CAAudioRecordeError) {
    switch error {
    case .dataFormatError(let reason):
        print("recorder error, data ftm error: \(reason)")
        break
        
    case .fileFormatError(let reason):
        print("recorder error,file ftm error: \(reason)")
        break
        
    case .hardwareError(let reason):
        print("recorder error,hardware error: \(reason)")
        break
        
    case .bufferError(let reaon):
        print("recorder error, buffer error: \(reaon)")
        break
        
    case .queueError(let reason):
        print("recorder error, queue error: \(reason)")
        break
        
    case .codecError(let reason):
        print("recorder error, codec error: \(reason)")
        break
        
    case .unknowedError:
        print("recorder error, unknow error")
        break
        
    default:
        print("recorder error, other error")
        break
    }
}

func handlePlayerError(_ error: CAAudioPlayer.CAAudioPlayerError) {
    switch error {
    case .fileNotFound:
        print("player error: file not found")
        break
    
    case .invaildDevice:
        print("player error: invalid device")
        break
        
    case .permissionError:
        print("player error: permission error")
        break
        
    case .unsupportedFileType:
        print("player error: unsupported file type")
        break
        
    case .unsupportedDataFormat:
        print("player error: unsupported data format")
        break
        
    case .unknowedError:
        print("player error: unknowed error")
        break
        
    default:
        print("player error: other error")
        break
    }
}


class RecorderDelegate: CAAudioRecorderDelegate {
    func audioRecorder(_ recorder: CAAudioRecorder, finishSuccess: Bool, error: CAAudioRecorder.CAAudioRecordeError?) {
        print("audio recorder finish success: \(finishSuccess)")
        if let error = error {
            handleRecorderError(error)
        }
    }
    
    func audioRecorder(_ recorder: CAAudioRecorder, stopSuccess: Bool, error: CAAudioRecorder.CAAudioRecordeError?) {
        print("audio recorder stop success: \(stopSuccess)")
        if let error = error {
            handleRecorderError(error)
        }
    }
    
    func audioRecorder(_ recorder: CAAudioRecorder, pauseSuccess: Bool, error: CAAudioRecorder.CAAudioRecordeError?) {
        print("audio recorder pause success: \(pauseSuccess)")
        if let error = error {
            handleRecorderError(error)
        }
    }
    
    func audioRecorder(_ recorder: CAAudioRecorder, startSucces: Bool, error: CAAudioRecorder.CAAudioRecordeError?) {
        print("audio recorder start success: \(startSucces)")
        if let error = error {
            handleRecorderError(error)
        }
    }
    
    func audioRecorder(_ recorder: CAAudioRecorder, prepareSuccess: Bool, error: CAAudioRecorder.CAAudioRecordeError?) {
        print("audio recorder prepare success: \(prepareSuccess)")
        if let error = error {
            handleRecorderError(error)
        }
    }
    

}


do {
    let lpcmRUL = URL(fileURLWithPath: "/Users/sy/Desktop/stdftm_lpcm.caf")
    let aacURL = URL(fileURLWithPath: "/Users/sy/Desktop/stdftm_aac.aac")
    let songURL = URL(fileURLWithPath: "/Users/sy/Desktop/Albert Vishi & Skylar Grey - Love The Way You Lie (Remix).mp3")
//    let myRecorderDelegate = RecorderDelegate()
//    let myRecoder = try CAAudioRecorder(uncompressedFormatSettings: nil, outputFileURL: lpcmRUL)
//    myRecoder.delegate = myRecorderDelegate
//    if myRecoder.prepareToRecord() {
//        myRecoder.start()
//        print("recording(press any key to stop)...")
//        getchar()
//        myRecoder.stop()
//    }
    
    let myPlayer = try CAAudioPlayer(url: songURL)
    myPlayer.play()
    myPlayer.volume = 0.9
    myPlayer.rate = 0.5
    print("volume: \(myPlayer.volume)")
    print("rate: \(myPlayer.rate)")
    print("Playing(press any key to stop)..")
    
    getchar()
    myPlayer.stop()
    
    
    
} catch let error as CAAudioRecorder.CAAudioRecordeError {
    handleRecorderError(error)
    exit(-100)
} catch let error as CAAudioPlayer.CAAudioPlayerError {
    handlePlayerError(error)
    exit(-1000)
} catch {
    print("catch unknowed error: \(error)")
    exit(-1)
}


