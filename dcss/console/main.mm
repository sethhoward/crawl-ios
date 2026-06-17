//
//  main.mm
//  dcss (ASCII/console target — Target B)
//
//  Non-SDL entry point. crawl's own main() is renamed to DCSS_main under
//  DCSS_IOS, so the app owns the real main() via UIApplicationMain.
//

#import <UIKit/UIKit.h>
#import "ConsoleAppDelegate.h"

int main(int argc, char *argv[])
{
    @autoreleasepool {
        NSDictionary *appDefaults = @{
            @"overlayUIEnabled": @YES,
        };
        [NSUserDefaults.standardUserDefaults registerDefaults:appDefaults];
        return UIApplicationMain(argc, argv, nil,
                                 NSStringFromClass([ConsoleAppDelegate class]));
    }
}
