//
//  ConsoleAppDelegate.mm
//  dcss (ASCII/console target — Target B)
//

#import "ConsoleAppDelegate.h"
#import "path_utils.h"

// Provided by CDDA_iOS_main.mm — builds argv and calls crawl's DCSS_main.
extern "C" int CDDA_iOS_main(NSString *documentPath);

@implementation ConsoleAppDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UIViewController *root = [[UIViewController alloc] init];
    root.view.backgroundColor = UIColor.blackColor;
    self.window.rootViewController = root;
    [self.window makeKeyAndVisible];

    // Run the crawl engine off the main thread; the cio backend (libios)
    // marshals drawing/input back to the UI.
    NSString *docs = getDocumentURL().path;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        CDDA_iOS_main(docs);
    });
    return YES;
}

@end
