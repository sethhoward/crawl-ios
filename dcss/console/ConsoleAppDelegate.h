//
//  ConsoleAppDelegate.h
//  dcss (ASCII/console target — Target B)
//
//  Minimal non-SDL app shell. Hosts the text-grid view and starts the
//  crawl engine (DCSS_main via CDDA_iOS_main) on a background thread.
//

#import <UIKit/UIKit.h>

@interface ConsoleAppDelegate : UIResponder <UIApplicationDelegate>
@property (strong, nonatomic) UIWindow *window;
@end
