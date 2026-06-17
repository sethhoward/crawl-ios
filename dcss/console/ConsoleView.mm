//
//  ConsoleView.mm
//  dcss (ASCII/console target — Target B)
//

#import "ConsoleView.h"
#include "console_bridge.h"

// DCSS COLOURS (0-15) -> RGB
static const uint8_t kPalette[16][3] = {
    {  0,  0,  0}, {  0,  0,170}, {  0,170,  0}, {  0,170,170},
    {170,  0,  0}, {170,  0,170}, {170, 85,  0}, {170,170,170},
    { 85, 85, 85}, { 85, 85,255}, { 85,255, 85}, { 85,255,255},
    {255, 85, 85}, {255, 85,255}, {255,255, 85}, {255,255,255},
};

static __weak ConsoleView *gConsoleView = nil;

static void console_redraw(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [gConsoleView setNeedsDisplay];
    });
}

@implementation ConsoleView {
    UIFont *_font;
    CGFloat _cellW, _cellH;
    int _cols, _rows;
    BOOL _ready;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.blackColor;
        self.opaque = YES;
        self.contentMode = UIViewContentModeRedraw;
        gConsoleView = self;
        ios_console_set_redraw(console_redraw);
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    int oldCols = _cols, oldRows = _rows;
    [self computeGrid];
    // Start the engine only once the grid is sized to the real bounds.
    if (!_ready && _cols > 0 && _rows > 0) {
        _ready = YES;
        if (self.onReady) self.onReady();
    } else if (_cols != oldCols || _rows != oldRows) {
        [self setNeedsDisplay];
    }
}

- (void)computeGrid {
    // DCSS console wants at least ~80x24. Landscape iPhone is wide but short,
    // so rows (height) is usually the binding constraint. Pick the font size
    // that satisfies BOTH >=80 cols and >=24 rows (i.e. the smaller font).
    const CGFloat targetCols = 80, targetRows = 24;
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    if (w < 1 || h < 1) return;

    // Reference measurement to get per-point metrics.
    CGFloat ref = 10.0;
    UIFont *rf = [UIFont fontWithName:@"Menlo" size:ref] ?: [UIFont monospacedSystemFontOfSize:ref weight:UIFontWeightRegular];
    CGFloat charWPerPt = [@"M" sizeWithAttributes:@{NSFontAttributeName: rf}].width / ref;
    CGFloat lineHPerPt = rf.lineHeight / ref;

    CGFloat sizeForCols = (w / targetCols) / charWPerPt;
    CGFloat sizeForRows = (h / targetRows) / lineHPerPt;
    CGFloat size = MAX(6.0, MIN(sizeForCols, sizeForRows));

    _font = [UIFont fontWithName:@"Menlo" size:size] ?: [UIFont monospacedSystemFontOfSize:size weight:UIFontWeightRegular];
    _cellW = [@"M" sizeWithAttributes:@{NSFontAttributeName: _font}].width;
    _cellH = _font.lineHeight;
    _cols = MAX(1, (int)(w / _cellW));
    _rows = MAX(1, (int)(h / _cellH));
    ios_console_set_size(_cols, _rows);
}

- (void)drawRect:(CGRect)rect {
    if (!_font) return;
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetRGBFillColor(ctx, 0, 0, 0, 1);
    CGContextFillRect(ctx, rect);

    NSMutableDictionary *attrs = [@{NSFontAttributeName: _font} mutableCopy];
    for (int y = 0; y < _rows; ++y) {
        for (int x = 0; x < _cols; ++x) {
            uint32_t ch; uint8_t fg, bg;
            ios_console_get(x, y, &ch, &fg, &bg);
            CGRect cell = CGRectMake(x * _cellW, y * _cellH, _cellW, _cellH);
            if (bg) {
                const uint8_t *b = kPalette[bg & 15];
                CGContextSetRGBFillColor(ctx, b[0]/255.0, b[1]/255.0, b[2]/255.0, 1);
                CGContextFillRect(ctx, cell);
            }
            if (ch && ch != ' ') {
                const uint8_t *f = kPalette[fg & 15];
                attrs[NSForegroundColorAttributeName] =
                    [UIColor colorWithRed:f[0]/255.0 green:f[1]/255.0 blue:f[2]/255.0 alpha:1];
                unichar u = (ch <= 0xFFFF) ? (unichar)ch : (unichar)'?';
                [[NSString stringWithCharacters:&u length:1]
                    drawAtPoint:cell.origin withAttributes:attrs];
            }
        }
    }
}

// ---- UIKeyInput ----------------------------------------------------------
- (BOOL)canBecomeFirstResponder { return YES; }
- (BOOL)hasText { return YES; }

- (void)insertText:(NSString *)text {
    if (text.length == 0) return;
    if ([text isEqualToString:@"\n"]) { ios_console_push_key('\r'); return; }
    for (NSUInteger i = 0; i < text.length; ++i)
        ios_console_push_key([text characterAtIndex:i]);
}
- (void)deleteBackward { ios_console_push_key(0x7f); }

@end
