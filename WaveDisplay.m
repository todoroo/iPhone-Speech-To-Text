//
//  WaveDisplay.m
//  SpeechToText
//
//  Created by Sam Bosley on 10/11/11.
//  Copyright (c) 2011 Astrid. All rights reserved.
//

#import "WaveDisplay.h"
#import "SpeechToTextModule.h"

@implementation WaveDisplay

@synthesize dataPoints;

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization code
    }
    return self;
}

- (void)dealloc {
    self.dataPoints = nil;
}

// Only override drawRect: if you perform custom drawing.
// An empty implementation adversely affects performance during animation.
- (void)drawRect:(CGRect)rect {
    [super drawRect:rect];
    static bool reverse = false;
    
    CGFloat scaleFactor = ((rect.size.height / 2) - 4.0) / kMaxVolumeSampleValue;
    CGContextRef context = UIGraphicsGetCurrentContext();
    
    CGContextBeginPath(context);
    CGContextSetRGBStrokeColor(context, 1.0, 1.0, 1.0, 1.0);
    CGContextSetLineWidth(context, 3.0);
    int count = [self.dataPoints count];
    CGFloat dx = rect.size.width / count;
    CGFloat x = 0.0;
    CGFloat y = rect.size.height / 2;
    CGContextMoveToPoint(context, x, y);
    BOOL down = NO;
    
    for (NSNumber *point in self.dataPoints) {
        // Draw curve
        CGFloat raw = [point floatValue] * scaleFactor;
        CGFloat draw = (down ? -raw : raw);
        draw = (reverse ? -draw : draw);
        CGContextAddQuadCurveToPoint(context, x + dx/2, y - draw * 2, x += dx, y);
        
        down = !down;
    }
    reverse = !reverse;
    CGContextDrawPath(context, kCGPathStroke);//*/
}

@end
