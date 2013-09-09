//
//  GBMotion.m
//  GBMotion
//
//  Created by Luka Mirosevic on 09/09/2013.
//  Copyright (c) 2013 Goonbee. All rights reserved.
//

#import "GBMotion.h"

#import <CoreMotion/CoreMotion.h>
#import <UIKit/UIKit.h>

NSString * const kGBMotionDeviceOrientationKey =         @"deviceOrientation";

static NSUInteger const kHistoryLength =                        20;//1 sec

static NSTimeInterval const kUpdatePeriod =                     1./20.;//20 times/sec

//orientation detection stuff
static CGFloat const kOrientationCenterLandscapeLeft =          0*M_PI_2;
static CGFloat const kOrientationCenterPortraitUpsideDown =     1*M_PI_2;
static CGFloat const kOrientationCenterLandscapeRight =         2*M_PI_2;
static CGFloat const kOrientationCenterPortrait =               3*M_PI_2;
static CGFloat const kOrientationCenterTriggerDistance =        (1/4)*M_PI_2;
static CGFloat const kOrientationZDimensionDiscardTrigger =     0.85;

@interface GBMotion ()

@property (strong, nonatomic) CMMotionManager                   *motionManager;
@property (strong, nonatomic) NSTimer                           *timer;

@property (strong, nonatomic) NSMutableArray                    *handlers;
@property (assign, nonatomic) NSUInteger                        handlerCount;

@property (assign, nonatomic) GBMotionDeviceOrientation         lastOrientation;
@property (assign, nonatomic) GBMotionDeviceOrientation         *orientationHistory;
@property (assign, nonatomic) NSUInteger                        orientationHistoryTail;

@end

@implementation GBMotion

#pragma mark - CA

-(void)setHandlerCount:(NSUInteger)handlerCount {
    if (_handlerCount == 0 && handlerCount > 0) {
        [self _changeStateToStarted:YES];
    }
    else if (_handlerCount > 0 && handlerCount == 0) {
        [self _changeStateToStarted:NO];
    }
    
    _handlerCount = handlerCount;
}

#pragma mark - mem

+(GBMotion *)sharedMotion {
    static GBMotion *_sharedMotion;
    @synchronized(self) {
        if (!_sharedMotion) {
            _sharedMotion = [self new];
        }
    }
    
    return _sharedMotion;
}

-(id)init {
    if (self = [super init]) {
        self.motionManager = [CMMotionManager new];
        self.handlers = [NSMutableArray new];
        
        self.lastOrientation = GBMotionDeviceOrientationUnknown;
        self.orientationHistory = malloc(sizeof(GBMotionDeviceOrientation) * kHistoryLength);
        memset(self.orientationHistory, GBMotionDeviceOrientationUnknown, kHistoryLength);//init it to contain a bunch of unknowns
        self.orientationHistoryTail = 0;
    }
    
    return self;
}

-(void)dealloc {
    [self.timer invalidate];
    free(self.orientationHistory);
}

#pragma mark - API

-(void)addHandler:(GBMotionGestureHandler)handler {
    [self.handlers addObject:[handler copy]];
    self.handlerCount = self.handlers.count;
}

-(void)removeHandler:(GBMotionGestureHandler)handler {
    [self.handlers removeObject:handler];
    self.handlerCount = self.handlers.count;
}

#pragma mark - util

-(void)_changeStateToStarted:(BOOL)started {
    if (started) {
        [self.motionManager startDeviceMotionUpdates];
        self.timer = [NSTimer timerWithTimeInterval:kUpdatePeriod target:self selector:@selector(_tick) userInfo:nil repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
    }
    else {
        [self.motionManager stopDeviceMotionUpdates];
        [self.timer invalidate];
        self.timer = nil;
    }
}

CGFloat WrapAngle(CGFloat angle) {
    CGFloat coterminalAngle = fmodf(angle, 2*M_PI);
    return coterminalAngle > 0 ? coterminalAngle : 2*M_PI + coterminalAngle;
}

BOOL InQuadrant(CGFloat currentAngle, CGFloat quadrantCenterAngle, CGFloat deadZoneAngle) {
    CGFloat maxDelta = (0.5/2)*M_PI - deadZoneAngle;
    
    //atan2(sin(x-y), cos(x-y))
    CGFloat delta = atan2f(sinf(quadrantCenterAngle-currentAngle), cosf(quadrantCenterAngle-currentAngle));
    
    return (fabsf(delta) <= maxDelta);
}

-(void)_detectDeviceOrientationChangeWithCMDeviceMotion:(CMDeviceMotion *)deviceMotion {
    GBMotionDeviceOrientation oldOrientation = self.deviceOrientation;
    CMAcceleration gravity = deviceMotion.gravity;
    
    //calculate angle of gravity vector relative to phone, ignoring z dimension
    CGFloat angle = atan2f(gravity.y, gravity.x);

    //change angle so we have a continuous angle from 0 to 2pi rather than 2 semicircles
    angle = angle > 0 ? angle : 2*M_PI + angle;
    
    //find out current orientation
    GBMotionDeviceOrientation instantaneousOrientation = GBMotionDeviceOrientationUnknown;
    
    //check if should discard based on z -> if the phone is almost flat, then minor movements in the phone attitude can result in rapid jumping across quadrants
    if (fabsf(gravity.z) < kOrientationZDimensionDiscardTrigger) {
        //check in quadrants
        if (InQuadrant(angle, kOrientationCenterLandscapeLeft, kOrientationCenterTriggerDistance)) {
            instantaneousOrientation = GBMotionDeviceOrientationLandscapeLeft;
        }
        else if (InQuadrant(angle, kOrientationCenterPortraitUpsideDown, kOrientationCenterTriggerDistance)) {
            instantaneousOrientation = GBMotionDeviceOrientationPortraitUpsideDown;
        }
        else if (InQuadrant(angle, kOrientationCenterLandscapeRight, kOrientationCenterTriggerDistance)) {
            instantaneousOrientation = GBMotionDeviceOrientationLandscapeRight;
        }
        else if (InQuadrant(angle, kOrientationCenterPortrait, kOrientationCenterTriggerDistance)) {
            instantaneousOrientation = GBMotionDeviceOrientationPortrait;
        }
    }
    //if z dictates that we should discard, then just stick to the old value
    else {
        instantaneousOrientation = self.deviceOrientation;
    }
    
    //decide based on history whether this one is acceptable -> has to be within the current orientation's parameters consistently for the entire history
    BOOL isHistoryConsistent = YES;
    NSUInteger tail = self.orientationHistoryTail;
    GBMotionDeviceOrientation *orientationHistory = self.orientationHistory;
    GBMotionDeviceOrientation firstOrientation = orientationHistory[tail];
    for (NSUInteger i=1; i<kHistoryLength; i++) {
        NSUInteger index = (i + tail) % kHistoryLength;
        
        if (orientationHistory[index] != firstOrientation) {
            isHistoryConsistent = NO;
            break;
        }
    }
    
    if (isHistoryConsistent) {
        //we just found a new orientation
        self.deviceOrientation = instantaneousOrientation;
    }
    
    //store the latest location
    if (instantaneousOrientation != GBMotionDeviceOrientationUnknown) {
        self.orientationHistory[self.orientationHistoryTail] = instantaneousOrientation;
        self.orientationHistoryTail = (self.orientationHistoryTail + 1) % kHistoryLength;
    }
    
    //check if it changed and if so notify the client
    if (self.deviceOrientation != oldOrientation) {
        for (GBMotionGestureHandler handler in self.handlers) {
            handler(GBMotionGestureChangedDeviceOrientation, @{kGBMotionDeviceOrientationKey: @(self.deviceOrientation)});
        }
    }
}

-(void)_tick {
    //get some updates
    CMDeviceMotion *deviceMotion = self.motionManager.deviceMotion;
    
    //check for orientation gestures
    [self _detectDeviceOrientationChangeWithCMDeviceMotion:deviceMotion];
}

@end
