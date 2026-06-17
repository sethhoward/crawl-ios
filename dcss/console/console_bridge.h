//
//  console_bridge.h
//  dcss (ASCII/console target — Target B)
//
//  Thin bridge between the cio backend (libios.mm, called on the engine
//  thread) and the UIKit text-grid view (ConsoleView, main thread).
//  The cell grid + input queue live in libios.mm; the view reads cells to
//  draw and pushes keystrokes/mouse in.
//

#pragma once
#include <cstdint>

struct ConsoleCell {
    char32_t ch = U' ';
    uint8_t  fg = 7;   // DCSS COLOURS index (0-15)
    uint8_t  bg = 0;
};

#ifdef __cplusplus
extern "C" {
#endif

// --- view -> model -------------------------------------------------------
// The view registers itself + its grid size (derived from bounds/font).
void ios_console_set_size(int cols, int rows);
int  ios_console_cols(void);
int  ios_console_rows(void);
// Snapshot one cell (thread-safe) for drawing.
void ios_console_get(int x, int y, uint32_t *ch, uint8_t *fg, uint8_t *bg);
// The view registers a redraw callback invoked (on main thread) by update_screen.
void ios_console_set_redraw(void (*cb)(void));
// Input from the view.
void ios_console_push_key(int keycode);

#ifdef __cplusplus
}
#endif
