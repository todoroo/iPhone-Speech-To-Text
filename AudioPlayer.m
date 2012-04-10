//
//  AudioPlayer.m
//  SpeechToText
//
//  Created by Andrew Shaw on 4/9/12.
//  Copyright (c) 2012 Astrid. All rights reserved.
//

#import "AudioPlayer.h"

@implementation AudioPlayer

static void HandleOutputBuffer (
                                void                *aqData,
                                AudioQueueRef       inAQ,
                                AudioQueueBufferRef inBuffer
                                ) {
    AQPlayerState *pAqData = (AQPlayerState *) aqData;        // 1
    if (pAqData->mIsRunning == 0) return;                     // 2
    UInt32 numBytesReadFromFile;                              // 3
    UInt32 numPackets = pAqData->mNumPacketsToRead;           // 4
    AudioFileReadPackets (
                          pAqData->mAudioFile,
                          false,
                          &numBytesReadFromFile,
                          pAqData->mPacketDescs, 
                          pAqData->mCurrentPacket,
                          &numPackets,
                          inBuffer->mAudioData 
                          );
    if (numPackets > 0) {                                     // 5
        inBuffer->mAudioDataByteSize = numBytesReadFromFile;  // 6
        AudioQueueEnqueueBuffer ( 
                                 pAqData->mQueue,
                                 inBuffer,
                                 (pAqData->mPacketDescs ? numPackets : 0),
                                 pAqData->mPacketDescs
                                 );
        pAqData->mCurrentPacket += numPackets;                // 7 
    } else {
        AudioQueueStop (
                        pAqData->mQueue,
                        false
                        );
        pAqData->mIsRunning = false; 
    }
}

static void DeriveBufferSize (AudioStreamBasicDescription *ASBDesc,                            // 1
                       UInt32                      maxPacketSize,                       // 2
                       Float64                     seconds,                             // 3
                       UInt32                      *outBufferSize,                      // 4
                       UInt32                      *outNumPacketsToRead                 // 5
                       ) {
    static const int maxBufferSize = 0x50000;                        // 6
    static const int minBufferSize = 0x4000;                         // 7
    
    if (ASBDesc->mFramesPerPacket != 0) {                             // 8
        Float64 numPacketsForTime =
        ASBDesc->mSampleRate / ASBDesc->mFramesPerPacket * seconds;
        *outBufferSize = numPacketsForTime * maxPacketSize;
    } else {                                                         // 9
        *outBufferSize =
        maxBufferSize > maxPacketSize ?
        maxBufferSize : maxPacketSize;
    }
    
    if (                                                             // 10
        *outBufferSize > maxBufferSize &&
        *outBufferSize > maxPacketSize
        )
        *outBufferSize = maxBufferSize;
    else {                                                           // 11
        if (*outBufferSize < minBufferSize)
            *outBufferSize = minBufferSize;
    }
    
    *outNumPacketsToRead = *outBufferSize / maxPacketSize;           // 12
}

-(void) beginPlayback: (NSString*) fileName {
    CFStringRef recordFilePath = (CFStringRef)[NSTemporaryDirectory() stringByAppendingPathComponent: fileName];
    
    AudioFileID mAudioFile = nil;
    CFURLRef sndFile = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, recordFilePath, kCFURLPOSIXPathStyle, false);
    if (!sndFile) { printf("can't parse file path\n"); return; }
    
    OSStatus result = AudioFileOpenURL (sndFile, kAudioFileReadPermission, 0, &mAudioFile);
    
#warning Release
//    CFRelease (mAudioFile);                               // 7
    NSLog(@"Closed recording");
    NSLog(@"OSStatus: %ld", result);
    
    UInt32 dataFormatSize = sizeof (aqData.mDataFormat);    // 1
    
    AudioFileGetProperty (                                  // 2
                          aqData.mAudioFile,                                  // 3
                          kAudioFilePropertyDataFormat,                       // 4
                          &dataFormatSize,                                    // 5
                          &aqData.mDataFormat                                 // 6
                          );
    [self setUpNewQueue];
    
#warning release
//    if (sndFile) {
//        CFRelease(sndFile);
//    }
}

-(void) setUpNewQueue {
    AudioQueueNewOutput (                                // 1
                         &aqData.mDataFormat,                             // 2
                         HandleOutputBuffer,                              // 3
                         &aqData,                                         // 4
                         CFRunLoopGetCurrent (),                          // 5
                         kCFRunLoopCommonModes,                           // 6
                         0,                                               // 7
                         &aqData.mQueue                                   // 8
                         );
    
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
}
-(void) startQueue {
    aqData.mIsRunning = true;                          // 1
    
    AudioQueueStart (                                  // 2
                     aqData.mQueue,                                 // 3
                     NULL                                           // 4
                     );
    
    do {                                               // 5
        CFRunLoopRunInMode (                           // 6
                            kCFRunLoopDefaultMode,                     // 7
                            0.25,                                      // 8
                            false                                      // 9
                            );
    } while (aqData.mIsRunning);
    
    CFRunLoopRunInMode (                               // 10
                        kCFRunLoopDefaultMode,
                        1,
                        false
                        );
}
-(void) stopQueue {
    AudioQueueDispose (                            // 1
                       aqData.mQueue,                             // 2
                       true                                       // 3
                       );
    
    AudioFileClose (aqData.mAudioFile);            // 4
    
    free (aqData.mPacketDescs);                    // 5
}
@end
