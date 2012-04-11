

//
//  VoiceAddModule.m
//  AstridiPhone
//
//  Created by Sam Bosley on 10/7/11.
//  Copyright (c) 2011 Todoroo. All rights reserved.
//

#import "SpeechToTextRecorder.h"
#import "SineWaveViewController.h"

#define FRAME_SIZE 110

@interface SpeechToTextRecorder ()

- (void)reset;
@end

@implementation SpeechToTextRecorder


static void HandleInputBuffer (void *aqData, AudioQueueRef inAQ, AudioQueueBufferRef inBuffer, 
                               const AudioTimeStamp *inStartTime, UInt32 inNumPackets, 
                               const AudioStreamPacketDescription *inPacketDesc) {
    
    AQRecorderState *pAqData = (AQRecorderState *) aqData;               
    
    if (inNumPackets == 0 && pAqData->mDataFormat.mBytesPerPacket != 0)
        inNumPackets = inBuffer->mAudioDataByteSize / pAqData->mDataFormat.mBytesPerPacket;
    
    // process speex
    int packets_per_frame = pAqData->speex_samples_per_frame;
    
    char cbits[FRAME_SIZE + 1];
    for (int i = 0; i < inNumPackets; i+= packets_per_frame) {
        speex_bits_reset(&(pAqData->speex_bits));
        
        speex_encode_int(pAqData->speex_enc_state, ((spx_int16_t*)inBuffer->mAudioData) + i, &(pAqData->speex_bits));
        int nbBytes = speex_bits_write(&(pAqData->speex_bits), cbits + 1, FRAME_SIZE);
        cbits[0] = nbBytes;
        
        [pAqData->encodedSpeexData appendBytes:cbits length:nbBytes + 1];
    }
    // handle recording
    OSStatus result = AudioFileWritePackets (pAqData->mAudioFile, false, inBuffer->mAudioDataByteSize,
                                             inPacketDesc, pAqData->mCurrentPacket, &inNumPackets,
                                             inBuffer->mAudioData);
    if (pAqData->transcribeAudio || result == noErr) {
        pAqData->mCurrentPacket += inNumPackets;
    }
    
    if (!pAqData->mIsRunning) 
        return;
    
    AudioQueueEnqueueBuffer(pAqData->mQueue, inBuffer, 0, NULL);
}

static void DeriveBufferSize (AudioQueueRef audioQueue, AudioStreamBasicDescription *ASBDescription, Float64 seconds, UInt32 *outBufferSize) {
    static const int maxBufferSize = 0x50000;
    
    int maxPacketSize = ASBDescription->mBytesPerPacket;
    if (maxPacketSize == 0) {
        UInt32 maxVBRPacketSize = sizeof(maxPacketSize);
        AudioQueueGetProperty (audioQueue, kAudioQueueProperty_MaximumOutputPacketSize, &maxPacketSize, &maxVBRPacketSize);
    }
    
    Float64 numBytesForTime = ASBDescription->mSampleRate * maxPacketSize * seconds;
    *outBufferSize = (UInt32)(numBytesForTime < maxBufferSize ? numBytesForTime : maxBufferSize);
}




OSStatus SetMagicCookieForFile (
                                AudioQueueRef inQueue,                                      // 1
                                AudioFileID   inFile                                        // 2
                                ) {
    OSStatus result = noErr;                                    // 3
    UInt32 cookieSize;                                          // 4
    
    if (
        AudioQueueGetPropertySize (                         // 5
                                   inQueue,
                                   kAudioQueueProperty_MagicCookie,
                                   &cookieSize
                                   ) == noErr
        ) {
        char* magicCookie =
        (char *) malloc (cookieSize);                       // 6
        if (
            AudioQueueGetProperty (                         // 7
                                   inQueue,
                                   kAudioQueueProperty_MagicCookie,
                                   magicCookie,
                                   &cookieSize
                                   ) == noErr
            )
            result =    AudioFileSetProperty (                  // 8
                                              inFile,
                                              kAudioFilePropertyMagicCookieData,
                                              cookieSize,
                                              magicCookie
                                              );
        free (magicCookie);                                     // 9
    }
    return result;                                              // 10
}

- (id)init{
    if ((self = [super init])) {
        aqData.mDataFormat.mFormatID         = kAudioFormatLinearPCM; 
        aqData.mDataFormat.mSampleRate       = 16000.0;               
        aqData.mDataFormat.mChannelsPerFrame = 1;                     
        aqData.mDataFormat.mBitsPerChannel   = 16;                    
        aqData.mDataFormat.mBytesPerPacket   =                        
        aqData.mDataFormat.mBytesPerFrame =
        aqData.mDataFormat.mChannelsPerFrame * sizeof (SInt16);
        aqData.mDataFormat.mFramesPerPacket  = 1;                     
        
        aqData.mDataFormat.mFormatFlags =                            
        kLinearPCMFormatFlagIsSignedInteger
        | kLinearPCMFormatFlagIsPacked;
        
        memset(&(aqData.speex_bits), 0, sizeof(SpeexBits));
        speex_bits_init(&(aqData.speex_bits)); 
        aqData.speex_enc_state = speex_encoder_init(&speex_wb_mode);
        
        int quality = 8;
        speex_encoder_ctl(aqData.speex_enc_state, SPEEX_SET_QUALITY, &quality);
        int vbr = 1;
        speex_encoder_ctl(aqData.speex_enc_state, SPEEX_SET_VBR, &vbr);
        speex_encoder_ctl(aqData.speex_enc_state, SPEEX_GET_FRAME_SIZE, &(aqData.speex_samples_per_frame));
        aqData.mQueue = NULL;
        
        
        [self reset];
        aqData.selfRef = self;
    }
    return self;
}

- (void)dealloc {
    speex_bits_destroy(&(aqData.speex_bits));
    speex_encoder_destroy(aqData.speex_enc_state);
    [aqData.encodedSpeexData release];
    AudioQueueDispose(aqData.mQueue, true);
    AudioFileClose (aqData.mAudioFile); 
    
    [super dealloc];
}

- (BOOL)recording {
    return aqData.mIsRunning;
}

- (void)reset {
    if (aqData.mQueue != NULL) {
        AudioQueueDispose(aqData.mQueue, true);
        AudioFileClose (aqData.mAudioFile); 
    }
    UInt32 enableLevelMetering = 1;
    AudioQueueNewInput(&(aqData.mDataFormat), HandleInputBuffer, &aqData, NULL, kCFRunLoopCommonModes, 0, &(aqData.mQueue));
    AudioQueueSetProperty(aqData.mQueue, kAudioQueueProperty_EnableLevelMetering, &enableLevelMetering, sizeof(UInt32));
    DeriveBufferSize(aqData.mQueue, &(aqData.mDataFormat), 0.5, &(aqData.bufferByteSize));
    
    for (int i = 0; i < kNumberBuffers; i++) {
        AudioQueueAllocateBuffer(aqData.mQueue, aqData.bufferByteSize, &(aqData.mBuffers[i]));
        
        AudioQueueEnqueueBuffer(aqData.mQueue, aqData.mBuffers[i], 0, NULL);
    }
    
    [aqData.encodedSpeexData release];
    aqData.encodedSpeexData = [[NSMutableData alloc] init];
    
    samplesBelowSilence = 0;
    detectedSpeech = NO;
    
}

- (void)beginRecordingTranscribe: (BOOL) transcribe saveToFile: (NSURL*) fileURL {
    @synchronized(self) {
        if (!self.recording) {
            aqData.transcribeAudio = transcribe;	
            
            XThrowIfError(AudioFileCreateWithURL ((CFURLRef) fileURL, kAudioFileCAFType, &aqData.mDataFormat, kAudioFileFlags_EraseFile, &aqData.mAudioFile), @"Error creating audio file");
            aqData.mCurrentPacket = 0;
            aqData.mIsRunning = true;
            [self reset];
            
            SetMagicCookieForFile(aqData.mQueue, aqData.mAudioFile);
            AudioQueueStart(aqData.mQueue, NULL);
        }
    }
}

- (NSData*)encodedSpeexData {
    return aqData.encodedSpeexData;
}

- (AudioQueueRef) mQueue {
    return aqData.mQueue;
}

- (void)stopRecording {
    @synchronized(self) {
        if (self.recording) {
            
            AudioQueueStop(aqData.mQueue, true);
            aqData.mIsRunning = false;
            SetMagicCookieForFile(aqData.mQueue, aqData.mAudioFile);
            AudioQueueDispose(aqData.mQueue, true);
            AudioFileClose (aqData.mAudioFile); 
        }
    }
    
    
}

@end
