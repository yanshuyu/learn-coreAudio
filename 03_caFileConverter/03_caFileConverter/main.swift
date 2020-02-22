//
//  main.swift
//  03_caFileConverter
//
//  Created by sy on 2020/2/20.
//  Copyright © 2020 sy. All rights reserved.
//

import Foundation
import AudioToolbox

func handleConverterError(_ error: CAFileConverter.CAFileConverterError) {
    switch error {
    case .FilePermissionError:
        print("file permission error")
        break
        
    case .UnsupportedFileTypeError:
        print("unsupported file type")
        break
        
    case .UnsupportedDataFormatError:
        print("unsupported data format")
        break
        
    case .OtherError:
        print("converter unspecified error")
        break
    }
    
}

let srcFileURL = URL(fileURLWithPath: "/Users/sy/Desktop/Keisum _ Crankboy - Sweeting.flac")
let dstFileURL = URL(fileURLWithPath: "/Users/sy/Desktop/converterTestOutput.caf")
let converterQueue = OperationQueue()

do {
    let srcFmtID = kAudioFormatMPEGLayer3
    let dstFmtID = kAudioFormatLinearPCM
    let decoderValideFmtIDs = CAFileConverter.avalibleDecoderFormatIDs()
    let encoderValideFmtIDs = CAFileConverter.avalibleEncoderFormatIDs()
    print("decoder valide format ids: \(decoderValideFmtIDs)")
    print("encoder valide format ids: \(encoderValideFmtIDs)")
    print("srcFmt: \(srcFmtID) -> dstFmt: \(dstFmtID) is supported ?    \(CAFileConverter.isValideConvert(from: srcFmtID, to: dstFmtID))")
    let myConverter = try CAFileConverter(srcURL: srcFileURL, dstURL: dstFileURL, dstFormat: dstFmtID)
    if myConverter.prepareToConvert() {
        if myConverter.start(using: converterQueue) {
            print("converting...")
            while !myConverter.isDone {

            }
            print("Done.")
        }
    }
    
} catch let error as CAFileConverter.CAFileConverterError {
    handleConverterError(error)
} catch {
    print("unknow error: \(error)")
}

