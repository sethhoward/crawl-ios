//
//  console_bridge.h
//  dcss (ASCII/console target — Target B)
//
//  Thin C bridge between the cio backend (libios.mm, called on the engine
//  thread) and the SwiftUI layer (Canvas renderer + key input, main thread).
//  The cell grid + input queue live in libios.mm; Swift reads cells to draw
//  and pushes keystrokes in. Kept pure C (no C++ types) so it can be included
//  from the Swift bridging header.
//

#pragma once
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// --- view -> model -------------------------------------------------------
// Set the grid size (initial sizing; does NOT signal the engine to relayout).
void ios_console_set_size(int cols, int rows);
// Set the grid size AND tell the running engine to relayout/redraw
// (rotation, keyboard show/hide). Safe to call from the main thread.
void ios_console_resize(int cols, int rows);
int  ios_console_cols(void);
int  ios_console_rows(void);
// Snapshot one cell (thread-safe) for drawing.
void ios_console_get(int x, int y, uint32_t *ch, uint8_t *fg, uint8_t *bg);
// Register a redraw callback invoked (on the main thread) by update_screen.
void ios_console_set_redraw(void (*cb)(void));
// Input from the view.
void ios_console_push_key(int keycode);
// Special keys (values live in libios.mm, which has cio.h).
void ios_push_key_up(void);
void ios_push_key_down(void);
void ios_push_key_left(void);
void ios_push_key_right(void);
void ios_push_key_esc(void);
void ios_push_key_enter(void);
void ios_push_key_tab(void);

#ifdef __cplusplus
}
#endif
