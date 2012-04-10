//
//  AudioPlayer.m
//  SpeechToText
//
//  Created by Andrew Shaw on 4/9/12.
//  Copyright (c) 2012 Astrid. All rights reserved.
//

#import "AudioPlayer.h"

@implementation AudioPlayer

static void HandleOutputBuffer (void *aqData, AudioQueueRef inAQ,
                                AudioQueueBufferRef inBuffer) {
    AQPlayerState *pAqData = (AQPlayerState *) aqData;
    if (pAqData->mIsRunning == 0) return;
    UInt32 numBytesReadFromFile;
    UInt32 numPackets = pAqData->mNumPacketsToRead;
    AudioFileReadPackets (pAqData->mAudioFile, false, &numBytesReadFromFile,
                          pAqData->mPacketDescs, pAqData->mCurrentPacket, &numPackets,
                          inBuffer->mAudioData);
    if (numPackets > 0) {
        inBuffer->mAudioDataByteSize = numBytesReadFromFile;
        AudioQueueEnqueueBuffer (pAqData->mQueue, inBuffer, (pAqData->mPacketDescs ? numPackets : 0),
                                 pAqData->mPacketDescs);
        pAqData->mCurrentPacket += numPackets; 
    } else {
        AudioQueueStop (
                        pAqData->mQueue,
                        false
                        );
        pAqData->mIsRunning = false; 
    }
}

static void isRunningProc (void *aqData, AudioQueueRef inAQ, AudioQueuePropertyID inID)
{
    
    NSLog(@"is running proc");
	AQPlayerState *pAqData = (AQPlayerState *)aqData;
	UInt32 size = sizeof(pAqData->mIsRunning);
	OSStatus result = AudioQueueGetProperty (inAQ, kAudioQueueProperty_IsRunning, &pAqData->mIsRunning, &size);
	
	if ((result == noErr) && (!pAqData->mIsRunning))
		[[NSNotificationCenter defaultCenter] postNotificationName: @"playbackQueueStopped" object: nil];
}

static void DeriveBufferSize (AudioStreamBasicDescription *ASBDesc, UInt32 maxPacketSize,
                              Float64 seconds, UInt32 *outBufferSize,                     
                              UInt32 *outNumPacketsToRead) {
    static const int maxBufferSize = 0x50000;                        // 6
    static const int minBufferSize = 0x4000;                         // 7
    
    if (ASBDesc->mFramesPerPacket != 0) {
        Float64 numPacketsForTime =
        ASBDesc->mSampleRate / ASBDesc->mFramesPerPacket * seconds;
        *outBufferSize = numPacketsForTime * maxPacketSize;
    } else {        
        *outBufferSize =
        maxBufferSize > maxPacketSize ?
        maxBufferSize : maxPacketSize;
    }
    
    if (*outBufferSize > maxBufferSize && *outBufferSize > maxPacketSize)
        *outBufferSize = maxBufferSize;
    else if (*outBufferSize < minBufferSize)
            *outBufferSize = minBufferSize;
    
    *outNumPacketsToRead = *outBufferSize / maxPacketSize; 
}

-(void) beginPlayback: (NSString*) fileName {
    CFStringRef recordFilePath = (CFStringRef)[NSTemporaryDirectory() stringByAppendingPathComponent: fileName];
    
    NSLog(@"Beginning playback");
    AudioFileID mAudioFile = nil;
    CFURLRef sndFile = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, recordFilePath, kCFURLPOSIXPathStyle, false);
    if (!sndFile) { printf("can't parse file path\n"); return; }
    
    OSStatus result = AudioFileOpenURL (sndFile, kAudioFileReadPermission, 0, &mAudioFile);
    
#warning Release
    //    CFRelease (mAudioFile);                               // 7
    NSLog(@"Closed recording");
    NSLog(@"OSStatus: %ld", result);
    
    UInt32 dataFormatSize = sizeof (aqData.mDataFormat); 
    
    AudioFileGetProperty (aqData.mAudioFile, kAudioFilePropertyDataFormat,
                          &dataFormatSize, &aqData.mDataFormat);
    [self setUpNewQueue];
    
#warning release
    //    if (sndFile) {
    //        CFRelease(sndFile);
    //    }
}

-(void) setUpNewQueue {
    
    NSLog(@"Setting up new queue");
    AudioQueueNewOutput (&aqData.mDataFormat, HandleOutputBuffer, &aqData,
                         CFRunLoopGetCurrent (), kCFRunLoopCommonModes, 0, &aqData.mQueue);
    
    UInt32 maxPacketSize;
    UInt32 propertySize = sizeof (maxPacketSize);
    AudioFileGetProperty (                               // 1
                          aqData.mAudioFile,                               // 2
                          kAudioFilePropertyPacketSizeUpperBound,          // 3
                          &propertySize,                                   // 4
                          &maxPacketSize                                   // 5
                          );
    
    DeriveBufferSize (                                   // 6
                      &aqData.mDataFormat,                              // 7
                      maxPacketSize,                                   // 8
                      0.5,                                             // 9
                      &aqData.bufferByteSize,                          // 10
                      &aqData.mNumPacketsToRead                        // 11
                      );
    
    // Allocating Memory for a Packet Descriptions Array
    bool isFormatVBR = (                                       // 1
                        aqData.mDataFormat.mBytesPerPacket == 0 ||
                        aqData.mDataFormat.mFramesPerPacket == 0
                        );
    
    if (isFormatVBR) {                                         // 2
        aqData.mPacketDescs =
        (AudioStreamPacketDescription*) malloc (
                                                aqData.mNumPacketsToRead * sizeof (AudioStreamPacketDescription)
                                                );
    } else {                                                   // 3
        aqData.mPacketDescs = NULL;
    }
    
    
    // cookie stuff
    UInt32 cookieSize = sizeof (UInt32);                   // 1
    bool couldNotGetProperty =                             // 2
    AudioFileGetPropertyInfo (                         // 3
                              aqData.mAudioFile,                             // 4
                              kAudioFilePropertyMagicCookieData,             // 5
                              &cookieSize,                                   // 6
                              NULL                                           // 7
                              );
    
    if (!couldNotGetProperty && cookieSize) {              // 8
        char* magicCookie =
        (char *) malloc (cookieSize);
        
        AudioFileGetProperty (                             // 9
                              aqData.mAudioFile,                             // 10
                              kAudioFilePropertyMagicCookieData,             // 11
                              &cookieSize,                                   // 12
                              magicCookie                                    // 13
                              );
        
        AudioQueueSetProperty (                            // 14
                               aqData.mQueue,                                 // 15
                               kAudioQueueProperty_MagicCookie,               // 16
                               magicCookie,                                   // 17
                               cookieSize                                     // 18
                               );
        
        free (magicCookie);                                // 19
    }
    
    //Allocate and Prime Audio Queue Buffers
    aqData.mCurrentPacket = 0;                                // 1
    
    for (int i = 0; i < kNumberBuffers; ++i) {                // 2
        AudioQueueAllocateBuffer (                            // 3
                                  aqData.mQueue,                                    // 4
                                  aqData.bufferByteSize,                            // 5
                                  &aqData.mBuffers[i]                               // 6
                                  );
        
        HandleOutputBuffer (                                  // 7
                            &aqData,                                          // 8
                            aqData.mQueue,                                    // 9
                            aqData.mBuffers[i]                                // 10
                            );
    }
    
    //Set an Audio Queue’s Playback Gain
    Float32 gain = 1.0;                                       // 1
    // Optionally, allow user to override gain setting here
    AudioQueueSetParameter (                                  // 2
                            aqData.mQueue,                                        // 3
                            kAudioQueueParam_Volume,                              // 4
                            gain                                                  // 5
                            );
	AudioQueueAddPropertyListener(aqData.mQueue, kAudioQueueProperty_IsRunning, isRunningProc, &aqData);
}
-(void) startQueue {
    NSLog(@"Starting queue");
    aqData.mIsRunning = true;
    
    AudioQueueStart (aqData.mQueue, NULL);
    
    do {
        CFRunLoopRunInMode (kCFRunLoopDefaultMode, 0.25, false);
    } while (aqData.mIsRunning);
    
    CFRunLoopRunInMode (kCFRunLoopDefaultMode, 1, false);
}
-(void) stopQueue {
    NSLog(@"Stopping queue");
    OSStatus result = AudioQueueStop(aqData.mQueue, true);
    if (result) {
        NSLog(@"Error stopping queue");
    }
}
-(void) pauseQueue {
    AudioQueuePause(aqData.mQueue);
}
-(void) disposeQueue {
    AudioQueueDispose (aqData.mQueue, true);
    
    AudioFileClose (aqData.mAudioFile);
    
    free (aqData.mPacketDescs);
}
@end
