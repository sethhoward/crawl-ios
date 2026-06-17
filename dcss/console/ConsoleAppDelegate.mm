//
//  ConsoleAppDelegate.mm
//  dcss (ASCII/console target — Target B)
//

#import "ConsoleAppDelegate.h"
#import "ConsoleView.h"
#import "path_utils.h"

// Provided by CDDA_iOS_main.mm — builds argv and calls crawl's DCSS_main.
extern "C" int CDDA_iOS_main(NSString *documentPath);

@implementation ConsoleAppDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    CGRect bounds = UIScreen.mainScreen.bounds;
    self.window = [[UIWindow alloc] initWithFrame:bounds];

    UIViewController *root = [[UIViewController alloc] init];
    ConsoleView *console = [[ConsoleView alloc] initWithFrame:bounds];
    console.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    root.view = console;
    self.window.rootViewController = root;
    [self.window makeKeyAndVisible];
    [console becomeFirstResponder];

    // Run the engine off the main thread; the cio backend marshals
    // drawing back to the main thread via the view's redraw callback.
    NSString *docs = getDocumentURL().path;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        CDDA_iOS_main(docs);
    });
    return YES;
}

@end
