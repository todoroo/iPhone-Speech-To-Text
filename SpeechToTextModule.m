//
//  VoiceAddModule.m
//  AstridiPhone
//
//  Created by Sam Bosley on 10/7/11.
//  Copyright (c) 2011 Todoroo. All rights reserved.
//

#import "SpeechToTextModule.h"
#import "SineWaveViewController.h"
#import "AudioPlayer.h"

@interface SpeechToTextModule ()

- (void)reset;
- (void)postByteData:(NSData *)data;
- (void)cleanUpProcessingThread;
@end

@implementation SpeechToTextModule

@synthesize delegate, fileName, isPlaying;

- (id)init {
    if ((self = [self initWithCustomDisplay:nil])) {
        //
    }
    return self;
}

- (id)initWithCustomDisplay:(NSString *)nibName {
    if ((self = [super init])) {        
        if (nibName) {
            speechRecorder = [[SpeechToTextRecorder alloc] init];
            sineWave = [[SineWaveViewController alloc] initWithNibName:nibName bundle:nil];
            sineWave.delegate = self;
        }
        [self reset];
    }
    return self;
}

- (void)dealloc {
    [processingThread cancel];
    if (processing) {
        [self cleanUpProcessingThread];
    }
    [speechRecorder release];
    [audioPlayer release];
    
    self.delegate = nil;
    status.delegate = nil;
    [status release];
    sineWave.delegate = nil;
    [sineWave release];
    [volumeDataPoints release];
    
    [super dealloc];
}

- (BOOL)recording {
    return [speechRecorder recording];
}

- (void)reset {
    [speechRecorder reset];
    [meterTimer invalidate];
    [meterTimer release];
    samplesBelowSilence = 0;
    detectedSpeech = NO;
    
    [volumeDataPoints release];
    volumeDataPoints = [[NSMutableArray alloc] initWithCapacity:kNumVolumeSamples];
    for (int i = 0; i < kNumVolumeSamples; i++) {
        [volumeDataPoints addObject:[NSNumber numberWithFloat:kMinVolumeSampleValue]];
    }
    sineWave.dataPoints = volumeDataPoints;
}

+ (NSURL *)applicationDocumentsDirectory
{
    return [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
}

+ (NSURL *) urlForFile: (NSString *) fName {
    return [[[self class] applicationDocumentsDirectory] URLByAppendingPathComponent:fName];
}
+ (NSString *) fullFilePath: (NSString *) fName {
    return [[[[self class] applicationDocumentsDirectory] absoluteString] stringByAppendingPathExtension:fName];
}
- (void)beginRecordingTranscribe: (BOOL) transcribe saveToFile: (NSString*) fName {
    @synchronized(self) {
        if (!self.recording && !processing) {
            self.fileName = fName;
            [self reset];
            [speechRecorder beginRecordingTranscribe:transcribe saveToFile:[[self class] urlForFile: fileName]];
            if (sineWave && [delegate respondsToSelector:@selector(showSineWaveView:)]) {
                [delegate showSineWaveView:sineWave];
            } else {
                status = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Speak now!", nil) message:@"" delegate:self cancelButtonTitle:NSLocalizedString(@"Done", nil) otherButtonTitles:nil];
                [status show];
            }
            meterTimer = [[NSTimer scheduledTimerWithTimeInterval:kVolumeSamplingInterval target:self selector:@selector(checkMeter) userInfo:nil repeats:YES] retain];
        }
    }
}

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex {
    if (self.recording && buttonIndex == 0) {
        [self stopRecording:YES];
    }
}

- (void)sineWaveDoneAction {
    if (self.recording)
        [self stopRecording:YES];
    else if ([delegate respondsToSelector:@selector(dismissSineWaveView:cancelled:)]) {
        [delegate dismissSineWaveView:sineWave cancelled:NO];
    }
}

- (void)cleanUpProcessingThread {
    @synchronized(self) {
        [processingThread release];
        processingThread = nil;
        processing = NO;
    }
}

- (void)sineWaveCancelAction {
    if (self.recording) {
        [self stopRecording:NO];
    } else {
        if (processing) {
            [processingThread cancel];
            processing = NO;
        }
        if ([delegate respondsToSelector:@selector(dismissSineWaveView:cancelled:)]) {
            [delegate dismissSineWaveView:sineWave cancelled:YES];
        }
    }
}

- (void)stopRecording:(BOOL)startProcessing {
    @synchronized(self) {
        if (self.recording) {
            [status dismissWithClickedButtonIndex:-1 animated:YES];
            [status release];
            status = nil;
            
            if ([delegate respondsToSelector:@selector(dismissSineWaveView:cancelled:)])
                [delegate dismissSineWaveView:sineWave cancelled:!startProcessing];
            
            [meterTimer invalidate];
            [meterTimer release];
            meterTimer = nil;
            [speechRecorder stopRecording];
            if (startProcessing) {
                [self cleanUpProcessingThread];
                processing = YES;
                processingThread = [[NSThread alloc] initWithTarget:self selector:@selector(postByteData:) object:speechRecorder.encodedSpeexData];
                [processingThread start];
                if ([delegate respondsToSelector:@selector(showLoadingView)])
                    [delegate showLoadingView];
            }
        }
    }
    
    /*
     #warning REMOVE
     CFStringRef recordFilePath = (CFStringRef)[NSTemporaryDirectory() stringByAppendingPathComponent: @"newfile.caf"];
     
     AudioFileID mAudioFile = nil;
     CFURLRef sndFile = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, recordFilePath, kCFURLPOSIXPathStyle, false);
     if (!sndFile) { printf("can't parse file path\n"); return; }
     
     OSStatus result = AudioFileOpenURL (sndFile, kAudioFileReadPermission, 0, &mAudioFile);
     NSLog(@"Closed recording");
     NSLog(@"OSStatus: %ld", result);
     */
}

- (void)checkMeter {
    AudioQueueLevelMeterState meterState;
    AudioQueueLevelMeterState meterStateDB;
    UInt32 ioDataSize = sizeof(AudioQueueLevelMeterState);
    AudioQueueGetProperty(speechRecorder.mQueue, kAudioQueueProperty_CurrentLevelMeter, &meterState, &ioDataSize);
    AudioQueueGetProperty(speechRecorder.mQueue, kAudioQueueProperty_CurrentLevelMeterDB, &meterStateDB, &ioDataSize);
    
    [volumeDataPoints removeObjectAtIndex:0];
    float dataPoint;
    if (meterStateDB.mAveragePower > kSilenceThresholdDB) {
        detectedSpeech = YES;
        dataPoint = MIN(kMaxVolumeSampleValue, meterState.mPeakPower);
    } else {
        dataPoint = MAX(kMinVolumeSampleValue, meterState.mPeakPower);
    }
    [volumeDataPoints addObject:[NSNumber numberWithFloat:dataPoint]];
    
    [sineWave updateWaveDisplay];
    
    if (detectedSpeech) {
        if (meterStateDB.mAveragePower < kSilenceThresholdDB) {
            samplesBelowSilence++;
            if (samplesBelowSilence > kSilenceThresholdNumSamples)
                [self stopRecording:YES];
        } else {
            samplesBelowSilence = 0;
        }
    }
}

- (void)postByteData:(NSData *)byteData {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSURL *url = [NSURL URLWithString:@"https://www.google.com/speech-api/v1/recognize?xjerr=1&client=chromium&lang=en-US"];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] init];
    [request setHTTPMethod:@"POST"];
    [request setHTTPBody:byteData];
    [request addValue:@"audio/x-speex-with-header-byte; rate=16000" forHTTPHeaderField:@"Content-Type"];
    [request setURL:url];
    [request setTimeoutInterval:15];
    NSURLResponse *response;
    NSError *error = nil;
    if ([processingThread isCancelled]) {
        [self cleanUpProcessingThread];
        [request release];
        [pool drain];
        return;
    }
    NSData *data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
    [request release];
    if ([processingThread isCancelled]) {
        [self cleanUpProcessingThread];
        [pool drain];
        return;
    }
    
    [self performSelectorOnMainThread:@selector(gotResponse:) withObject:data waitUntilDone:NO];
    [pool drain];
}

- (void)gotResponse:(NSData *)jsonData {
    [self cleanUpProcessingThread];
    [delegate didReceiveVoiceResponse:jsonData];
}

#pragma Audio Player

+ (BOOL)audioFileExists: (NSString*) fName {
    NSURL *urlRef = [SpeechToTextModule urlForFile:fName];
    NSLog(@"File exists for path: %@, %d", [urlRef absoluteString], [urlRef checkResourceIsReachableAndReturnError:nil]);
    return [urlRef checkResourceIsReachableAndReturnError:nil];
}

- (void)playAudioFile: (NSString *) fName {
    if (!audioPlayer) {
        audioPlayer = [[AudioPlayer alloc] init];
    }
    self.fileName = fName;
    [audioPlayer beginPlayback:[[self class] urlForFile: fName]];
    
    isPlaying = YES;
    
    [audioPlayer startQueue];
}

- (void)pauseAudio {
    [audioPlayer pauseQueue];
    isPlaying = NO;
}

- (void)stopAudio {
    [audioPlayer stopQueue];
    isPlaying = NO;
}

@end
