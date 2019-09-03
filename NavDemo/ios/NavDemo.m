//
//  NavDemo.m
//  NavDemo
//
//  Created by Tianxiang Liu on 2/9/19.
//  Copyright © 2019 Facebook. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "React/RCTBridgeModule.h"
@interface RCT_EXTERN_MODULE(NavDemo, NSObject)
RCT_EXTERN_METHOD(renderNaviDemo:(nonnull NSNumber *)originLat oriLon:(nonnull NSNumber *)originLon oriName:(NSString *)originName destLat:(nonnull NSNumber *)destinationLat destLon:(nonnull NSNumber *)destinationLon destName:(NSString *)destinationName)
@end
