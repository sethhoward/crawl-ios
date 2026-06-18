//
//  libios.mm
//  dcss (ASCII/console target — Target B)
//
//  iOS implementation of DCSS's console backend (libconsole.h). Maintains a
//  character grid (written by the engine thread via the cio calls) and an
//  input queue (fed by the UIKit view). ConsoleView reads the grid to draw.
//

#include "AppHdr.h"

#include "externs.h"
#include "libconsole.h"
#include "cio.h"
#include "libutil.h"
#include "state.h"
#include "view.h"       // handle_terminal_resize
#include "viewgeom.h"   // screen_cell_t, crawl_view_buffer (full def)

#include "console_bridge.h"

#include <cstdarg>
#include <cstdio>
#include <unistd.h>
#include <vector>
#include <deque>
#include <mutex>
#include <condition_variable>

// ---- model ---------------------------------------------------------------
namespace {
    struct ConsoleCell {
        char32_t ch = U' ';
        uint8_t  fg = 7;   // DCSS COLOURS index (0-15)
        uint8_t  bg = 0;
    };

    std::mutex g_grid_mutex;
    std::vector<ConsoleCell> g_grid;
    int g_cols = 80, g_rows = 24;
    int g_cx = 1, g_cy = 1;          // DCSS cursor is 1-based
    uint8_t g_fg = 7, g_bg = 0;
    bool g_cursor_enabled = true;
    bool g_headless = false;
    void (*g_redraw)(void) = nullptr;

    std::mutex g_in_mutex;
    std::condition_variable g_in_cv;
    std::deque<int> g_in_queue;

    inline ConsoleCell *cell_at(int x1, int y1) {       // 1-based in
        int x = x1 - 1, y = y1 - 1;
        if (x < 0 || y < 0 || x >= g_cols || y >= g_rows) return nullptr;
        if ((int)g_grid.size() < g_cols * g_rows) return nullptr;
        return &g_grid[y * g_cols + x];
    }
}

// ---- bridge (used by the SwiftUI layer) ---------------------------------
// Read by crawl's viewgeom.cc (extern "C"): when set, portrait stacked layout.
extern "C" { bool g_ios_force_stacked = false; }
void ios_set_force_stacked(int on) { g_ios_force_stacked = (on != 0); }
// True once an actual game is in progress (false on the title/menu screens).
int ios_console_in_game(void) { return crawl_state.need_save ? 1 : 0; }
// True only while the engine is waiting for a movement/command at the map
// prompt — NOT during in-game menus (inventory, targeting, prompts). The touch
// D-pad only intercepts taps while this is true so menus stay interactive.
int ios_console_accepting_moves(void) { return crawl_state.waiting_for_command ? 1 : 0; }

void ios_console_set_size(int cols, int rows) {
    std::lock_guard<std::mutex> lk(g_grid_mutex);
    g_cols = cols > 0 ? cols : 80;
    g_rows = rows > 0 ? rows : 24;
    g_grid.assign(g_cols * g_rows, ConsoleCell{});
}
void ios_console_resize(int cols, int rows) {
    ios_console_set_size(cols, rows);
    // Wake the engine: the main loop polls terminal_resized and re-runs
    // init_geometry; CK_REDRAW unblocks getch_ck so it polls promptly.
    crawl_state.terminal_resized = true;
    ios_console_push_key(CK_REDRAW);
}
int  ios_console_cols(void) { return g_cols; }
int  ios_console_rows(void) { return g_rows; }
void ios_console_get(int x, int y, uint32_t *ch, uint8_t *fg, uint8_t *bg) {
    std::lock_guard<std::mutex> lk(g_grid_mutex);
    if (x < 0 || y < 0 || x >= g_cols || y >= g_rows ||
        (int)g_grid.size() < g_cols * g_rows) {
        *ch = ' '; *fg = 7; *bg = 0; return;
    }
    const ConsoleCell &c = g_grid[y * g_cols + x];
    *ch = c.ch; *fg = c.fg; *bg = c.bg;
}
void ios_console_set_redraw(void (*cb)(void)) { g_redraw = cb; }
void ios_console_push_key(int keycode) {
    { std::lock_guard<std::mutex> lk(g_in_mutex); g_in_queue.push_back(keycode); }
    g_in_cv.notify_one();
}
void ios_push_key_up(void)    { ios_console_push_key(CK_UP); }
void ios_push_key_down(void)  { ios_console_push_key(CK_DOWN); }
void ios_push_key_left(void)  { ios_console_push_key(CK_LEFT); }
void ios_push_key_right(void) { ios_console_push_key(CK_RIGHT); }
void ios_push_key_esc(void)   { ios_console_push_key(ESCAPE); }
void ios_push_key_enter(void) { ios_console_push_key('\r'); }
void ios_push_key_tab(void)   { ios_console_push_key('\t'); }

// ---- lifecycle -----------------------------------------------------------
void console_startup()  {}
void console_shutdown() {}

int get_number_of_lines() { return g_rows; }
int get_number_of_cols()  { return g_cols; }
int num_to_lines(int num) { return num; }

// ---- clearing / cursor ---------------------------------------------------
void clrscr_sys() {
    std::lock_guard<std::mutex> lk(g_grid_mutex);
    g_grid.assign(g_cols * g_rows, ConsoleCell{});
}
void clear_to_end_of_line() {
    std::lock_guard<std::mutex> lk(g_grid_mutex);
    for (int x = g_cx; x <= g_cols; ++x)
        if (ConsoleCell *c = cell_at(x, g_cy)) *c = ConsoleCell{U' ', g_fg, g_bg};
}
void gotoxy_sys(int x, int y) { g_cx = x; g_cy = y; }
int  wherex() { return g_cx; }
int  wherey() { return g_cy; }
void set_cursor_enabled(bool e) { g_cursor_enabled = e; }
bool is_cursor_enabled() { return g_cursor_enabled; }
void fakecursorxy(int x, int y) { g_cx = x; g_cy = y; }

// ---- colour --------------------------------------------------------------
void textcolour(int c) { g_fg = (uint8_t)(c & 0x0f); }
void textbackground(int c) { g_bg = (uint8_t)(c & 0x0f); }
COLOURS default_hover_colour() { return DARKGREY; }

// ---- output --------------------------------------------------------------
void putwch(char32_t c) {
    std::lock_guard<std::mutex> lk(g_grid_mutex);
    if (ConsoleCell *cell = cell_at(g_cx, g_cy))
        *cell = ConsoleCell{ c ? c : U' ', g_fg, g_bg };
    if (g_cx <= g_cols) g_cx++;
}
void cprintf(const char *format, ...) {
    char buf[2048];
    va_list ap; va_start(ap, format);
    vsnprintf(buf, sizeof(buf), format, ap);
    va_end(ap);
    std::lock_guard<std::mutex> lk(g_grid_mutex);
    for (const unsigned char *p = (const unsigned char *)buf; *p; ++p) {
        if (*p == '\n') { g_cx = 1; g_cy++; continue; }
        if (ConsoleCell *cell = cell_at(g_cx, g_cy))
            *cell = ConsoleCell{ (char32_t)*p, g_fg, g_bg };
        g_cx++;
    }
}
void puttext(int x, int y, const crawl_view_buffer &vbuf) {
    const screen_cell_t *src = vbuf;
    coord_def sz = vbuf.size();
    std::lock_guard<std::mutex> lk(g_grid_mutex);
    for (int row = 0; row < sz.y; ++row)
        for (int col = 0; col < sz.x; ++col) {
            const screen_cell_t &s = src[row * sz.x + col];
            if (ConsoleCell *cell = cell_at(x + col, y + row))
                *cell = ConsoleCell{ s.glyph ? s.glyph : U' ',
                                     (uint8_t)(s.colour & 0x0f),
                                     (uint8_t)((s.colour >> 4) & 0x0f) };
        }
}
void update_screen() { if (g_redraw) g_redraw(); }

// ---- input ---------------------------------------------------------------
bool kbhit() {
    std::lock_guard<std::mutex> lk(g_in_mutex);
    return !g_in_queue.empty();
}
void delay(unsigned int ms) { if (ms) usleep(ms * 1000); }
int getch_ck() {
    int k;
    {
        std::unique_lock<std::mutex> lk(g_in_mutex);
        g_in_cv.wait(lk, []{ return !g_in_queue.empty(); });
        k = g_in_queue.front(); g_in_queue.pop_front();
    }
    // A rotation / keyboard resize bumps the grid size and pushes CK_REDRAW.
    // Re-lay-out here on the engine thread so the game AND menus reflow
    // immediately, instead of waiting for the next real keypress (the in-game
    // key reader only redraws on CK_REDRAW; it doesn't re-run init_geometry).
    if (k == CK_REDRAW && crawl_state.terminal_resized)
        handle_terminal_resize();
    return k;
}
void set_mouse_enabled(bool) {}

// ---- headless ------------------------------------------------------------
bool in_headless_mode()    { return g_headless; }
void enter_headless_mode() { g_headless = true; }

// ---- display info --------------------------------------------------------
lib_display_info::lib_display_info()
    : type("iOS"), term("ios-console"), fg_colors(16), bg_colors(8) {}
