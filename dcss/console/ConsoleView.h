//
//  ConsoleView.h
//  dcss (ASCII/console target — Target B)
//
//  A monospaced character-grid view: draws the cell grid maintained by
//  libios.mm and feeds keystrokes back via the bridge.
//

#import <UIKit/UIKit.h>

@interface ConsoleView : UIView <UIKeyInput>
// Called once, after the view has its real bounds and the grid is sized.
@property (nonatomic, copy) void (^onReady)(void);
@end
