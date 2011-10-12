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

- (void)didDismissSineWave;

@end

// Users of this class can create

@interface SineWaveViewController : UIViewController {
    IBOutlet UIImageView *backgroundImage;
    IBOutlet WaveDisplay *waveDisplay;
    IBOutlet UIButton *doneButton;
}

@property (assign) id<SineWaveViewDelegate> delegate;
@property (readonly) WaveDisplay *waveDisplay;
@property (readonly) UIImageView *backgroundView;
@property (readonly) UIButton *doneButton;

@property (nonatomic, retain) NSArray *dataPoints;
- (IBAction)done;
- (void)updateWaveDisplay;

@end
