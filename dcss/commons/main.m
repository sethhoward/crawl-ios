//
//  main.m
//  dcss
//
//  Created by Аполлов Юрий Андреевич on 05/01/2021.
//  Copyright © 2021 Аполлов Юрий Андреевич. All rights reserved.
//

#import <UIKit/UIKit.h>

#import "AppDelegate.h"
#import "path_utils.h"

int main(int argc, char * argv[]) {
    @autoreleasepool {
        NSDictionary* appDefaults = @{
            @"overlayUIEnabled": @YES,
            @"invertScroll": @NO,
            @"invertPan": @NO,
            @"keyboardSwipeTime": @0.05,
            @"resizeGameWindowWhenTogglingKeyboard": @YES,
            @"panningWith1Finger": @NO,
            @"screenAutoresize": @YES,
        };
        [NSUserDefaults.standardUserDefaults registerDefaults:appDefaults];

        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
