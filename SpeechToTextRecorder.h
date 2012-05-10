

//
//  VoiceAddModule.h
//  AstridiPhone
//
//  Created by Sam Bosley on 10/7/11.
//  Copyright (c) 2011 Todoroo. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AudioToolbox/AudioToolbox.h>
#import <speex/speex.h>

#define kNumberBuffers 3
#define kNumVolumeSamples 10
#define kSilenceThresholdDB -30.0

#define kVolumeSamplingInterval 0.05
#define kSilenceTimeThreshold 0.9
#define kSilenceThresholdNumSamples kSilenceTimeThreshold / kVolumeSamplingInterval

// For scaling display
#define kMinVolumeSampleValue 0.01
#define kMaxVolumeSampleValue 1.0

#define XThrowIfError(error, operation)	\
if (error) {							\
NSLog(@"%@, Error: %ld", operation, error);                \
}

typedef struct AQRecorderState {
    AudioStreamBasicDescription  mDataFormat;                   
    AudioQueueRef                mQueue;                        
    AudioQueueBufferRef          mBuffers[kNumberBuffers];                    
    UInt32                       bufferByteSize;                
    SInt64                       mCurrentPacket;                
    bool                         mIsRunning;
    
    bool                         transcribeAudio;
    
    // Recording
    ExtAudioFileRef              recordAudioFile;
    AudioStreamBasicDescription  recordDataFormat;      
    
    // Speex
    SpeexBits                    speex_bits; 
    void *                       speex_enc_state;
    int                          speex_samples_per_frame;
    __unsafe_unretained NSMutableData *              encodedSpeexData;
    
    __unsafe_unretained id selfRef;
} AQRecorderState;


@interface SpeechToTextRecorder : NSObject <UIAlertViewDelegate> {
    
    AQRecorderState aqData;
    
    BOOL detectedSpeech;
    int samplesBelowSilence;
    
}

@property (readonly) BOOL recording;

/* Caller can pass a non-nil nib name to specify the nib with which to create
 a SineWaveViewController (nib should conform to the spec in the SineWaveViewController
 interface). A nil argument will cause the module to display an alert view instead
 of the custom view controller. */
- (void) stopRecording;
- (void)reset: (CFURLRef) fileURL;
- (NSData *) encodedSpeexData;
- (AudioQueueRef) mQueue;
- (BOOL) transcribe;
// Begins a voice recording
- (void)beginRecordingTranscribe: (BOOL) transcribe saveToFile: (NSURL*) fileURL;



@end
