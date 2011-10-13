//
//  SineWaveViewController.m
//  SpeechToText
//
//  Created by Sam Bosley on 10/11/11.
//  Copyright (c) 2011 Astrid. All rights reserved.
//

#import "SineWaveViewController.h"
#import "SpeechToTextModule.h"

@implementation SineWaveViewController

@synthesize delegate;
@synthesize dataPoints;
@synthesize backgroundView;
@synthesize waveDisplay;
@synthesize doneButton;
@synthesize processingView;
@synthesize header;

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        //
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    waveDisplay.dataPoints = self.dataPoints;
}

- (void)setDataPoints:(NSArray *)_dataPoints {
    [dataPoints release];
    dataPoints = [_dataPoints retain];
    waveDisplay.dataPoints = dataPoints;
}

- (void)dealloc {
    [dataPoints release];
    [header release];
    [backgroundImage release];
    [waveDisplay release];
    [doneButton release];
    [processingView release];
    
    [super dealloc];
}

- (void)resetViewState {
    self.header.hidden = NO;
    self.processingView.hidden = YES;
    self.waveDisplay.hidden = NO;
    self.doneButton.hidden = NO;
}

- (IBAction)done {
    [delegate didDismissSineWave];
}

- (void)updateWaveDisplay {
    [waveDisplay setNeedsDisplay];
}

@end
