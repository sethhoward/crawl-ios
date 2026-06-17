//
//  ConsoleAppDelegate.mm
//  dcss (ASCII/console target — Target B)
//

#import "ConsoleAppDelegate.h"
#import "ConsoleView.h"
#import "path_utils.h"
#include "console_bridge.h"

// Provided by CDDA_iOS_main.mm — builds argv and calls crawl's DCSS_main.
extern "C" int CDDA_iOS_main(NSString *documentPath);

@implementation ConsoleAppDelegate {
    ConsoleView *_console;
}

- (UIButton *)keyButton:(NSString *)title action:(void(^)(void))handler {
    UIButtonConfiguration *cfg = [UIButtonConfiguration grayButtonConfiguration];
    cfg.title = title;
    cfg.baseForegroundColor = UIColor.whiteColor;
    UIButton *b = [UIButton buttonWithConfiguration:cfg
        primaryAction:[UIAction actionWithHandler:^(UIAction *a){ handler(); }]];
    return b;
}

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    CGRect bounds = UIScreen.mainScreen.bounds;
    self.window = [[UIWindow alloc] initWithFrame:bounds];
    UIViewController *root = [[UIViewController alloc] init];
    UIView *container = root.view;
    container.backgroundColor = UIColor.blackColor;

    const CGFloat barH = 48;
    CGRect consoleRect = CGRectMake(0, 0, bounds.size.width, bounds.size.height - barH);
    _console = [[ConsoleView alloc] initWithFrame:consoleRect];
    _console.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [container addSubview:_console];

    // On-screen control bar (the keyboard can't send ESC/arrows/Tab).
    UIStackView *bar = [[UIStackView alloc] initWithFrame:
        CGRectMake(0, bounds.size.height - barH, bounds.size.width, barH)];
    bar.axis = UILayoutConstraintAxisHorizontal;
    bar.distribution = UIStackViewDistributionFillEqually;
    bar.spacing = 2;
    bar.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    __weak ConsoleView *wc = _console;
    NSArray *btns = @[
        [self keyButton:@"Esc" action:^{ ios_push_key_esc(); }],
        [self keyButton:@"Tab" action:^{ ios_push_key_tab(); }],
        [self keyButton:@"←"  action:^{ ios_push_key_left(); }],
        [self keyButton:@"↓"  action:^{ ios_push_key_down(); }],
        [self keyButton:@"↑"  action:^{ ios_push_key_up(); }],
        [self keyButton:@"→"  action:^{ ios_push_key_right(); }],
        [self keyButton:@"⏎"  action:^{ ios_push_key_enter(); }],
        [self keyButton:@"⌨" action:^{
            if (wc.isFirstResponder) [wc resignFirstResponder];
            else [wc becomeFirstResponder];
        }],
    ];
    for (UIButton *b in btns) [bar addArrangedSubview:b];
    [container addSubview:bar];

    // Start the engine only after the console view has its real bounds and
    // the grid is sized (avoids drawing into a stale/wrong-sized grid).
    NSString *docs = getDocumentURL().path;
    static BOOL launched = NO;
    _console.onReady = ^{
        if (launched) return;
        launched = YES;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            CDDA_iOS_main(docs);
        });
    };

    self.window.rootViewController = root;
    [self.window makeKeyAndVisible];
    return YES;
}

@end
