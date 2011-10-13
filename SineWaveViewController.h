//
//  SineWaveViewController.h
//  SpeechToText
//
//  Created by Sam Bosley on 10/11/11.
//  Copyright (c) 2011 Astrid. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "WaveDisplay.h"

@protocol SineWaveViewDelegate <NSObject>

- (void)sineWaveDoneAction;
- (void)sineWaveCancelAction;

@end

// Users of this class can create

@interface SineWaveViewController : UIViewController {
    IBOutlet UITextView *header;
    IBOutlet UIImageView *backgroundImage;
    IBOutlet WaveDisplay *waveDisplay;
    IBOutlet UIView *processingView;
    IBOutlet UIButton *doneButton;
    
    BOOL cancelMode;
}

@property (assign) id<SineWaveViewDelegate> delegate;
@property (readonly) WaveDisplay *waveDisplay;
@property (readonly) UIImageView *backgroundView;
@property (readonly) UIView *processingView;
@property (readonly) UIButton *doneButton;
@property (readonly) UITextView *header;

@property (nonatomic, retain) NSArray *dataPoints;
- (IBAction)done;
- (void)updateWaveDisplay;
- (void)resetViewState;
- (void)repurposeForCancelling;

@end
