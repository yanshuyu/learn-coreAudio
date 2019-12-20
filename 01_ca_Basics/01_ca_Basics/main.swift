//
//  main.swift
//  01_ca_Basics
//
//  Created by sy on 2019/12/19.
//  Copyright © 2019 sy. All rights reserved.
//

//
// Core Audio is a collection of frameworks for working with digital audio
// these frameworks can split into two groups:
// * audio engines: process streams of audio
// * helper APIs: facilitate getting audio data into or out of audio engines
//
// audio engines apis: Audio Units, Audio Queues, OpenAL
// helper apis: Audio File Services, Audio File Stream Services, Audio Converter Services,
// Extended Audio File Services, Core MIDI(mac os only), Audio Session Services(ios only)
//
import Foundation
import AudioToolbox
import AVFoundation


extension UInt32 {
    public func charaters() -> String {
        let first = Character(Unicode.Scalar((self >> 24) & 0x000000ff)!)
        let second = Character(Unicode.Scalar((self >> 16) & 0x000000ff)!)
        let third = Character(Unicode.Scalar((self >> 8) & 0x000000ff)!)
        let fourth = Character(Unicode.Scalar(self & 0xff)!)
        return String(first) + String(second) + String(third) + String(fourth)
    }
}

extension AudioStreamBasicDescription: CustomStringConvertible {
    public var description: String {
        var desc = ""
        desc += "{ fmtId: \(self.mFormatID.charaters()) formatFlags: \(self.mFormatFlags) bitsPerChannel: \(self.mBitsPerChannel)}\n"
        return desc
    }
}



//
// MARK: - create audio file, save precompute audio samples to it.
//
public enum AudioWaveType {
    case square(frequence: TimeInterval)
    case sawtooth(frequnce: TimeInterval)
    case sine(frequnce: TimeInterval)
}

@discardableResult
public func generateAudioWave(type: AudioWaveType, duration: TimeInterval) -> URL? {
    var fileName = ""

    switch type {
    case .square(let frequnce):
        fileName = String(format: "square_%.2f.aif", frequnce)
        break
    case .sawtooth(let frequnce):
        fileName = String(format: "sawtooth_%.2f.aif", frequnce)
        break
    case .sine(let frequnce):
        fileName = String(format: "sine_%.2f.aif", frequnce)
        break
    }
    
    
    let fileUrl = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
    var asbd = AudioStreamBasicDescription()
    var fileId: AudioFileID?
    var result: OSStatus = noErr
    
    asbd.mFormatID = kAudioFormatLinearPCM
    asbd.mFormatFlags = kAudioFormatFlagIsBigEndian | kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked
    asbd.mSampleRate = 44100
    asbd.mChannelsPerFrame = 1
    asbd.mBitsPerChannel = 16
    asbd.mBytesPerFrame = 2
    asbd.mFramesPerPacket = 1
    asbd.mBytesPerPacket = 2

    result = AudioFileCreateWithURL(fileUrl as CFURL,
                           kAudioFileAIFFType,
                           &asbd,
                           .eraseFile,
                           &fileId)
    
    
    guard result == noErr else {
        print("AudioFileCreateWithURL fail with statue code: \(result)")
        return nil
    }
    
    guard fileId != nil else {
        print("AudioFileCreateWithURL yield nil file id")
        return nil
    }
    
    generateAudioSamples(for: fileId!, wave: type, duration: duration)
    
    AudioFileClose(fileId!)
    
    return fileUrl
}

fileprivate func generateAudioSamples(for file: AudioFileID, wave: AudioWaveType, duration: TimeInterval) {
    switch wave {
    case .square(let frequnce):
        let totalSampleCount = Int(44100 * duration)
        let waveLengthInSample = Int(44100 / frequnce)
        var sampleCountWritten = 0
        var bytesPerSample: UInt32 = 2
        var result: OSStatus = noErr
        while sampleCountWritten < totalSampleCount {
            for i in 1...waveLengthInSample {
                var sample: Int16 = 0
                sample = (i < waveLengthInSample / 2) ? Int16.max : Int16.min
                //
                // how to swap sample to big endian ????????????????????
                //
                result = AudioFileWriteBytes(file,
                                    false,
                                    Int64(sampleCountWritten * 2),
                                    &bytesPerSample,
                                    &sample)
                if result != noErr {
                    print("generateAudioSamples() faile to write sample: \(sample) ")
                    return
                }
                sampleCountWritten += 1
            }
        }
        
        break
        
    case .sawtooth(let frequnce):
        let totalSampleCount = Int(44100 * duration)
        let waveLengthInSample = Int(44100 / frequnce)
        var sampleCountWritten = 0
        var bytesPerSample: UInt32 = 2
        var result: OSStatus = noErr
        while sampleCountWritten < totalSampleCount {
            for i in 1...waveLengthInSample {
                var sample: Int16 = 0
                sample = Int16(Float(i) / Float(waveLengthInSample) * Float(Int16.max) * 2  - Float(Int16.max))
                result = AudioFileWriteBytes(file,
                                    false,
                                    Int64(sampleCountWritten * 2),
                                    &bytesPerSample,
                                    &sample)
                if result != noErr {
                    print("generateAudioSamples() faile to write sample: \(sample) ")
                    return
                }
                sampleCountWritten += 1
            }
        }
    case .sine(let frequnce):
        let totalSampleCount = Int(44100 * duration)
        let waveLengthInSample = Int(44100 / frequnce)
        var sampleCountWritten = 0
        var bytesPerSample: UInt32 = 2
        var result: OSStatus = noErr
        while sampleCountWritten < totalSampleCount {
            for i in 1...waveLengthInSample {
                var sample: Int16 = 0
                sample = Int16(sin(Float.pi * 2 * (Float(i) / Float(waveLengthInSample))) * Float(Int16.max))
                result = AudioFileWriteBytes(file,
                                    false,
                                    Int64(sampleCountWritten * 2),
                                    &bytesPerSample,
                                    &sample)
                if result != noErr {
                    print("generateAudioSamples() faile to write sample: \(sample) ")
                    return
                }
                sampleCountWritten += 1
            }
        }
    }
}

print("\n\n--------------generating audio samples----------------")
var songUrl: URL?
if let audioSquareUrl = generateAudioWave(type: .square(frequence: 2), duration: 5) {
    print("generate square wave audio at: \(audioSquareUrl.absoluteString)")
    songUrl = audioSquareUrl
}

if let audioSwatoothUrl = generateAudioWave(type: .sawtooth(frequnce: 10000), duration: 5) {
    print("generate swatooth wave audio at: \(audioSwatoothUrl.absoluteString)")
    songUrl = audioSwatoothUrl
}

if let audioSineUrl = generateAudioWave(type: .sine(frequnce: 10000), duration: 5) {
    print("generate sine wave audio at: \(audioSineUrl.absoluteString)")
    songUrl = audioSineUrl
}





//
// MARK: - inspecting audio file info
//

assert(songUrl != nil)

var fId: AudioFileID?
var result = noErr
result = AudioFileOpenURL(songUrl! as CFURL,
                 .readPermission,
                 0,
                 &fId)
if result != noErr {
    print("error open audio file of url: \(songUrl!)")
}

var infoDictSz: UInt32 = 0
var writeFlag: UInt32 = 0
result = AudioFileGetPropertyInfo(fId!,
                         kAudioFilePropertyInfoDictionary,
                         &infoDictSz,
                         &writeFlag)
if result != noErr {
    print("error get property info of url: \(songUrl!)")
}

var infoDict: CFDictionary?
result = AudioFileGetProperty(fId!,
                     kAudioFilePropertyInfoDictionary,
                     &infoDictSz,
                     &infoDict)



if result != noErr {
    print("error get metadata info of url: \(songUrl!)")
}

print("\n\n--------------inspecting audio file info--------------")

if infoDict != nil {
    print("metadata of audio \(songUrl!.absoluteString): \(infoDict!)")
}



public func getAvailableAudioStreamBasicDescpritions(for format: inout AudioFileTypeAndFormatID) -> [AudioStreamBasicDescription]? {
    var availableAsbdSz: UInt32 = 0
    var result: OSStatus = noErr
    result = AudioFileGetGlobalInfoSize(kAudioFileGlobalInfo_AvailableStreamDescriptionsForFormat,
                               UInt32(MemoryLayout<AudioFileTypeAndFormatID>.size),
                               &format,
                               &availableAsbdSz)
    if result != noErr {
        return nil
    }
    
    var asbdRawPtr = UnsafeMutableRawPointer.allocate(byteCount: Int(availableAsbdSz),
                                                      alignment: MemoryLayout<AudioStreamBasicDescription>.alignment)
    defer {
        asbdRawPtr.deallocate()
    }
    
    result = AudioFileGetGlobalInfo(kAudioFileGlobalInfo_AvailableStreamDescriptionsForFormat,
                           UInt32(MemoryLayout<AudioFileTypeAndFormatID>.size),
                           &format,
                           &availableAsbdSz,
                           asbdRawPtr)
    if result != noErr {
        return nil
    }
    
    let asbdPtr = asbdRawPtr.bindMemory(to: AudioStreamBasicDescription.self,
                                        capacity: Int(availableAsbdSz) / MemoryLayout<AudioStreamBasicDescription>.stride)
    let asbdBufferPtr = UnsafeBufferPointer<AudioStreamBasicDescription>(start: asbdPtr,
                                                                         count: Int(availableAsbdSz) / MemoryLayout<AudioStreamBasicDescription>.stride)
    
    return Array(asbdBufferPtr)
}


var audioFileTypeAndFormat = AudioFileTypeAndFormatID()
audioFileTypeAndFormat.mFileType = kAudioFileAIFFType
audioFileTypeAndFormat.mFormatID = kAudioFormatLinearPCM
print("all aif + lpcm supported asbd: \(getAvailableAudioStreamBasicDescpritions(for: &audioFileTypeAndFormat) ?? [])")

audioFileTypeAndFormat.mFileType = kAudioFileWAVEType
print("all wav + lpcm supported asbd: \(getAvailableAudioStreamBasicDescpritions(for: &audioFileTypeAndFormat) ?? [])")

audioFileTypeAndFormat.mFileType = kAudioFileMP3Type
audioFileTypeAndFormat.mFormatID = kAudioFormatMPEGLayer3
print("all mp3 + mpeg-layer-3 supported asbd: \(getAvailableAudioStreamBasicDescpritions(for: &audioFileTypeAndFormat) ?? [])")

audioFileTypeAndFormat.mFileType = kAudioFileM4AType
audioFileTypeAndFormat.mFormatID = kAudioFormatMPEG4AAC
print("all m4a + mpeg-aac supported asbd: \(getAvailableAudioStreamBasicDescpritions(for: &audioFileTypeAndFormat) ?? [])")


