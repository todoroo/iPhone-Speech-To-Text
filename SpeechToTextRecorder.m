

//
//  VoiceAddModule.m
//  AstridiPhone
//
//  Created by Sam Bosley on 10/7/11.
//  Copyright (c) 2011 Todoroo. All rights reserved.
//

#import "SpeechToTextRecorder.h"
#import "SineWaveViewController.h"
//#import "CAStreamBasicDescription.h"

#define FRAME_SIZE 110

@implementation SpeechToTextRecorder


static void HandleInputBuffer (void *aqData, AudioQueueRef inAQ, AudioQueueBufferRef inBuffer, 
                               const AudioTimeStamp *inStartTime, UInt32 inNumPackets, 
                               const AudioStreamPacketDescription *inPacketDesc) {
    
    AQRecorderState *pAqData = (AQRecorderState *) aqData;               
    
    if (inNumPackets == 0 && pAqData->mDataFormat.mBytesPerPacket != 0)
        inNumPackets = inBuffer->mAudioDataByteSize / pAqData->mDataFormat.mBytesPerPacket;
    
    UInt32 recordNumPackets = inNumPackets;
    if (inNumPackets == 0 && pAqData->recordDataFormat.mBytesPerPacket != 0)
        recordNumPackets = inBuffer->mAudioDataByteSize / pAqData->recordDataFormat.mBytesPerPacket;
    // handle recording
    
    AudioBufferList buffList;
    buffList.mBuffers[0].mData = inBuffer->mAudioData;
    buffList.mBuffers[0].mDataByteSize = inBuffer->mAudioDataByteSize;
    buffList.mBuffers[0].mNumberChannels = pAqData->recordDataFormat.mChannelsPerFrame;
    UInt32 writeFrames = inBuffer->mAudioDataByteSize / pAqData->recordDataFormat.mBytesPerFrame;
    
    OSStatus result = ExtAudioFileWrite(pAqData->recordAudioFile, writeFrames, &buffList);
    
    if (result == 0) {
        NSLog(@"Success writing!!");
        pAqData->recordCurrentPacket += recordNumPackets;
    }
    XThrowIfError(result, @"Failed to write audio file packets");
    NSLog(@"Result %ld", result);
    
    
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




static OSStatus SetMagicCookieForFile (AudioQueueRef inQueue, AudioFileID inFile) {
    OSStatus result = noErr;
    UInt32 cookieSize;
    if (AudioQueueGetPropertySize (inQueue, kAudioQueueProperty_MagicCookie,
                                   &cookieSize) == noErr) {
        char* magicCookie =
        (char *) malloc (cookieSize);
        if (AudioQueueGetProperty (inQueue, kAudioQueueProperty_MagicCookie,
                                   magicCookie, &cookieSize) == noErr)
            result =    AudioFileSetProperty (inFile, kAudioFilePropertyMagicCookieData,
                                              cookieSize, magicCookie);
        free (magicCookie);
    }
    return result;
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
        
        
        //record
        aqData.recordDataFormat.mSampleRate       = 48000;
        aqData.recordDataFormat.mFormatID         = kAudioFormatMPEG4AAC; 
        aqData.recordDataFormat.mChannelsPerFrame = 1;
        
        aqData.recordDataFormat.mBitsPerChannel   = 0;                    
        aqData.recordDataFormat.mBytesPerPacket   = 0;                       
        aqData.recordDataFormat.mBytesPerFrame =
        aqData.recordDataFormat.mChannelsPerFrame * sizeof (SInt16);
        aqData.recordDataFormat.mFramesPerPacket  = 1024;                     
        aqData.recordDataFormat.mFormatFlags = 0;
        aqData.recordDataFormat.mReserved = 0;
        //        aqData.recordDataFormat.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
        // use AudioFormat API to fill out the rest of the description
        UInt32 size = sizeof(aqData.recordDataFormat);
        XThrowIfError(AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, NULL, &size, &aqData.recordDataFormat), @"couldn't create destination data format");
        
        
        
        
        memset(&(aqData.speex_bits), 0, sizeof(SpeexBits));
        speex_bits_init(&(aqData.speex_bits)); 
        aqData.speex_enc_state = speex_encoder_init(&speex_wb_mode);
        
        int quality = 8;
        speex_encoder_ctl(aqData.speex_enc_state, SPEEX_SET_QUALITY, &quality);
        int vbr = 1;
        speex_encoder_ctl(aqData.speex_enc_state, SPEEX_SET_VBR, &vbr);
        speex_encoder_ctl(aqData.speex_enc_state, SPEEX_GET_FRAME_SIZE, &(aqData.speex_samples_per_frame));
        aqData.mQueue = NULL;
        
        
        aqData.selfRef = self;
    }
    return self;
}

- (void)dealloc {
    speex_bits_destroy(&(aqData.speex_bits));
    speex_encoder_destroy(aqData.speex_enc_state);
    [aqData.encodedSpeexData release];
    AudioQueueDispose(aqData.mQueue, true);
//    ExtAudioFileDispose (aqData.mAudioFile); 
    
    [super dealloc];
}

- (BOOL)recording {
    return aqData.mIsRunning;
}
-(CFURLRef) setupRecording {
    XThrowIfError(AudioSessionInitialize(NULL, NULL, NULL, self), @"couldn't initialize audio session");
    
    // our default category -- we change this for conversion and playback appropriately
    UInt32 audioCategory = kAudioSessionCategory_SoloAmbientSound;
    XThrowIfError(AudioSessionSetProperty(kAudioSessionProperty_AudioCategory, sizeof(audioCategory), &audioCategory), @"couldn't set audio category");
    
    // the session must be active for offline conversion including after an  an audio interruption
    XThrowIfError(AudioSessionSetActive(true), @"couldn't set audio session active\n");
    
    // create the URLs we'll use for source and destination
    //            NSString *source = [[NSBundle mainBundle] pathForResource:@"sourceA
    
    
    NSArray  *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString *destinationFilePath = [[NSString alloc] initWithFormat: @"%@/output.caf", documentsDirectory];
    CFURLRef destinationURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, (CFStringRef)destinationFilePath, kCFURLPOSIXPathStyle, false);
    
    NSLog(@"Destination url: %@", [(NSURL*) destinationURL absoluteString]);
    return destinationURL;
}

- (void)reset: (CFURLRef) fileURL {
    if (!fileURL) {
        return;
    }
    if (aqData.mQueue != NULL) {
        AudioQueueDispose(aqData.mQueue, true);
        ExtAudioFileDispose (aqData.recordAudioFile); 
    }
    UInt32 enableLevelMetering = 1;
    
    /*
     * Audio file stuff
     */
    XThrowIfError(ExtAudioFileCreateWithURL(fileURL, kAudioFileM4AType, &aqData.mDataFormat, NULL, kAudioFileFlags_EraseFile, &aqData.recordAudioFile), @"Error creating audio file");
    
    
    AudioStreamBasicDescription clientFormat;
    // Create the canonical PCM client format.
    memset(&clientFormat, 0, sizeof(clientFormat));
    clientFormat.mSampleRate = aqData.mDataFormat.mSampleRate;
    clientFormat.mFormatID = kAudioFormatLinearPCM;
    clientFormat.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked; //kAudioFormatFlagIsPacked | kAudioFormatFlagIsSignedInteger;
    clientFormat.mChannelsPerFrame = aqData.mDataFormat.mChannelsPerFrame;
    clientFormat.mBytesPerPacket   =                        
    clientFormat.mBytesPerFrame =
    clientFormat.mChannelsPerFrame * sizeof (SInt16);
    clientFormat.mBitsPerChannel = 16;
    clientFormat.mFramesPerPacket = 1;
    
    // Set the client format in source and destination file.
    UInt32 size = sizeof( clientFormat );

    XThrowIfError(ExtAudioFileSetProperty( aqData.recordAudioFile, kExtAudioFileProperty_ClientDataFormat, size, &clientFormat), @"Error while setting client format in destination file");
    /*
     * End Audio file stuff
     */
    
    
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
            
            CFURLRef destination = [self setupRecording];
            
            [self reset: destination];
            aqData.mCurrentPacket = 0;
            aqData.recordCurrentPacket = 0;
            aqData.mIsRunning = true;
            
            AudioQueueStart(aqData.mQueue, NULL);
        }
    }
}

- (NSData*)encodedSpeexData {
    return aqData.encodedSpeexData;
}

- (AudioQueueRef)mQueue {
    return aqData.mQueue;
}

- (BOOL) transcribe {
    return aqData.transcribeAudio;
}

- (void)stopRecording {
    @synchronized(self) {
        if (self.recording) {
            
            AudioQueueStop(aqData.mQueue, true);
            aqData.mIsRunning = false;
            /*for (int i = 0; i < kNumberBuffers; i++)
             {
             AudioQueueFreeBuffer(aqData.mQueue, aqData.mBuffers[i]);
             }*/
            
            XThrowIfError(AudioQueueDispose(aqData.mQueue, true), @"Error disposing queue");
            XThrowIfError(ExtAudioFileDispose (aqData.recordAudioFile), @"Error file closing"); 
        }
    }
    
    
}

@end
