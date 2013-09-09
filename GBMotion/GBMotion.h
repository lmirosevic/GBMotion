//
//  GBMotion.h
//  GBMotion
//
//  Created by Luka Mirosevic on 09/09/2013.
//  Copyright (c) 2013 Goonbee. All rights reserved.
//

#import <Foundation/Foundation.h>

extern NSString * const kGBMotionDeviceOrientationKey;

typedef enum {
    GBMotionGestureChangedDeviceOrientation,
} GBMotionGesture;

typedef enum {
    GBMotionDeviceOrientationUnknown,
    GBMotionDeviceOrientationPortrait,
    GBMotionDeviceOrientationLandscapeRight,
    GBMotionDeviceOrientationLandscapeLeft,
    GBMotionDeviceOrientationPortraitUpsideDown,
} GBMotionDeviceOrientation;

typedef void(^GBMotionGestureHandler)(GBMotionGesture gesture, NSDictionary *info);

@interface GBMotion : NSObject

@property (assign, nonatomic) GBMotionDeviceOrientation         deviceOrientation;

+(GBMotion *)sharedMotion;

-(void)addHandler:(GBMotionGestureHandler)handler;
-(void)removeHandler:(GBMotionGestureHandler)handler;

@end