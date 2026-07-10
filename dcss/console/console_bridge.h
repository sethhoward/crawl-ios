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
// Force the portrait stacked layout (HUD below the map) on a wide grid.
void ios_set_force_stacked(int on);
// 1 while an actual game is in progress, 0 on the title/menu screens.
int  ios_console_in_game(void);
// 1 only while the engine is waiting for a command at the map prompt.
int  ios_console_accepting_moves(void);
// 1 while a menu/prompt/help/targeting overlay is open (any UI layout on the
// stack, or the engine is blocked on a UI overlay). Stable across turns —
// unlike accepting_moves, it does NOT flicker every step.
int  ios_console_menu_open(void);
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
void ios_push_key_pgup(void);
void ios_push_key_pgdn(void);

// Request an in-place save (no quit) — called when the app is backgrounded.
// Thread-safe: sets a flag and wakes the engine, which saves on its own thread
// at the next input boundary.
void ios_request_save(void);

// --- command catalog (for the assignable button bar) ---------------------
// Curated categories of game commands (mirrors the in-game help, from
// "Extended Movement" onward). Commands are referenced by an opaque id (the
// engine's command_type as an int). Strings are owned by the bridge; copy them
// immediately on the Swift side.
int  ios_cmd_cat_count(void);
const char *ios_cmd_cat_name(int cat);
int  ios_cmd_count(int cat);
int  ios_cmd_id(int cat, int idx);     // opaque command id, or 0 if out of range
const char *ios_cmd_label(int cmd_id); // curated short label for a button face
const char *ios_cmd_name(int cmd_id);  // engine command name (stable; also the token)
int  ios_cmd_key(int cmd_id);          // default keystroke to send, or 0 if unbound
int  ios_cmd_from_token(const char *token); // name -> id, or 0 if unknown

#ifdef __cplusplus
}
#endif
