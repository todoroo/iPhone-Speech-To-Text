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
    XThrowIfError(AudioFileReadPackets (pAqData->mAudioFile, false, &numBytesReadFromFile,
                          pAqData->mPacketDescs, pAqData->mCurrentPacket, &numPackets,
                          inBuffer->mAudioData), @"Error reading audio file packets");
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
    
	AQPlayerState *pAqData = (AQPlayerState *)aqData;
	UInt32 size = sizeof(pAqData->mIsRunning);
	OSStatus result = AudioQueueGetProperty (inAQ, kAudioQueueProperty_IsRunning, &pAqData->mIsRunning, &size);
	
	if ((result == noErr) && (!pAqData->mIsRunning))
		[[NSNotificationCenter defaultCenter] postNotificationName: @"playbackQueueStopped" object: nil];
}

static void DeriveBufferSize (AudioStreamBasicDescription *ASBDesc, UInt32 maxPacketSize,
                              Float64 seconds, UInt32 *outBufferSize,                     
                              UInt32 *outNumPacketsToRead) {
    static const int maxBufferSize = 0x50000;
    static const int minBufferSize = 0x4000;
    
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

-(void) beginPlayback: (NSURL*) fullFilePath {
    
    AudioFileID mAudioFile = nil;
    /*
    CFURLRef sndFile = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, (CFStringRef)fullFilePath, kCFURLPOSIXPathStyle, false);
    if (!sndFile) { printf("can't parse file path\n"); return; }*/
    
    XThrowIfError(AudioFileOpenURL ((CFURLRef)fullFilePath, kAudioFileReadPermission, 0, &mAudioFile), @"Error opening file url");
    
    
    UInt32 dataFormatSize = sizeof (aqData.mDataFormat); 
    
    XThrowIfError( AudioFileGetProperty (aqData.mAudioFile, kAudioFilePropertyDataFormat,
                                         &dataFormatSize, &aqData.mDataFormat), @"Error getting file property");
    [self setUpNewQueue];
    
#warning release
    //    if (sndFile) {
    //        CFRelease(sndFile);
    //    }
}

-(void) setUpNewQueue {
    
    NSLog(@"Setting up new queue");
    XThrowIfError(AudioQueueNewOutput (&aqData.mDataFormat, HandleOutputBuffer, &aqData,
                                       CFRunLoopGetCurrent (), kCFRunLoopCommonModes, 0, &aqData.mQueue), @"Error queue new output");
    
    UInt32 maxPacketSize;
    UInt32 propertySize = sizeof (maxPacketSize);
    XThrowIfError(AudioFileGetProperty (aqData.mAudioFile, kAudioFilePropertyPacketSizeUpperBound, 
                                        &propertySize, &maxPacketSize), @"Error Still can't get property");
    
    DeriveBufferSize (&aqData.mDataFormat, maxPacketSize, 0.5,
                      &aqData.bufferByteSize, &aqData.mNumPacketsToRead);
    
    // Allocating Memory for a Packet Descriptions Array
    bool isFormatVBR = (                                       // 1
                        aqData.mDataFormat.mBytesPerPacket == 0 ||
                        aqData.mDataFormat.mFramesPerPacket == 0
                        );
    
    if (isFormatVBR) {
        aqData.mPacketDescs = (AudioStreamPacketDescription*) malloc (aqData.mNumPacketsToRead * sizeof (AudioStreamPacketDescription));
    } else {
        aqData.mPacketDescs = NULL;
    }
    
    
    // cookie stuff
    UInt32 cookieSize = sizeof (UInt32);
    bool couldNotGetProperty = AudioFileGetPropertyInfo ( aqData.mAudioFile, kAudioFilePropertyMagicCookieData,
                              &cookieSize, NULL);
    
    if (!couldNotGetProperty && cookieSize) {
        NSLog(@"Could not get property");
        char* magicCookie = (char *) malloc (cookieSize);
        
        AudioFileGetProperty (aqData.mAudioFile, kAudioFilePropertyMagicCookieData,
                              &cookieSize, magicCookie);
        
        AudioQueueSetProperty (aqData.mQueue, kAudioQueueProperty_MagicCookie,
                               magicCookie, cookieSize);
        
        free (magicCookie);
    }
    
    //Allocate and Prime Audio Queue Buffers
    aqData.mCurrentPacket = 0;
    
    for (int i = 0; i < kNumberBuffers; ++i) {
        AudioQueueAllocateBuffer (aqData.mQueue, aqData.bufferByteSize,
                                  &aqData.mBuffers[i]);
        
        HandleOutputBuffer (&aqData, aqData.mQueue,
                            aqData.mBuffers[i]);
    }
    
    //Set an Audio Queue’s Playback Gain
    Float32 gain = 1.0;                                       // 1
    // Optionally, allow user to override gain setting here
    AudioQueueSetParameter (aqData.mQueue, kAudioQueueParam_Volume, gain);
	AudioQueueAddPropertyListener(aqData.mQueue, kAudioQueueProperty_IsRunning, isRunningProc, &aqData);
}
-(void) startQueue {
    NSLog(@"Starting queue");
    aqData.mIsRunning = true;
    
    XThrowIfError(AudioQueueStart(aqData.mQueue, NULL), @"Error starting queue") ;
    
    do {
        CFRunLoopRunInMode (kCFRunLoopDefaultMode, 0.25, false);
    } while (aqData.mIsRunning);
    
    CFRunLoopRunInMode (kCFRunLoopDefaultMode, 1, false);
}
-(void) stopQueue {
    NSLog(@"Stopping queue");
    XThrowIfError(AudioQueueStop(aqData.mQueue, true), @"Error stopping queue") ;
}
-(void) pauseQueue {
    XThrowIfError(AudioQueuePause(aqData.mQueue), @"Error pausing queue") ;
}
-(void) disposeQueue {
    AudioQueueDispose (aqData.mQueue, true);
    
    AudioFileClose (aqData.mAudioFile);
    
    free (aqData.mPacketDescs);
}
@end
