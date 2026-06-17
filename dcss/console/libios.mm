//
//  libios.mm
//  dcss (ASCII/console target — Target B)
//
//  iOS implementation of DCSS's console backend (libconsole.h — the same
//  contract libunix.cc implements with ncurses). This is the SPIKE-stage
//  skeleton: it satisfies the link contract and keeps the engine alive.
//  Real text-grid rendering (Core Text/Metal) + touch/keyboard input are
//  the follow-on work; for now output is dropped and input blocks.
//

#include "AppHdr.h"

#include "externs.h"     // coord_def, colour_t, COLOURS, etc.
#include "libconsole.h"  // the backend contract we implement
#include "cio.h"
#include "libutil.h"
#include "state.h"

#include <cstdarg>
#include <unistd.h>

// ---- backend state -------------------------------------------------------
static bool s_headless = false;
static bool s_cursor_enabled = true;
static int  s_cursor_x = 1;
static int  s_cursor_y = 1;

// ---- lifecycle -----------------------------------------------------------
void console_startup()  {}
void console_shutdown() {}

// ---- screen geometry (stub fixed grid until the view drives this) --------
int get_number_of_lines() { return 24; }
int get_number_of_cols()  { return 80; }
int num_to_lines(int num) { return num; }

// ---- clearing / cursor ---------------------------------------------------
void clrscr_sys()           {}
void clear_to_end_of_line() {}
void gotoxy_sys(int x, int y) { s_cursor_x = x; s_cursor_y = y; }
int  wherex() { return s_cursor_x; }
int  wherey() { return s_cursor_y; }
void set_cursor_enabled(bool enabled) { s_cursor_enabled = enabled; }
bool is_cursor_enabled() { return s_cursor_enabled; }
void fakecursorxy(int x, int y) { s_cursor_x = x; s_cursor_y = y; }

// ---- colour --------------------------------------------------------------
void textcolour(int) {}
void textbackground(int) {}
COLOURS default_hover_colour() { return DARKGREY; }

// ---- output --------------------------------------------------------------
void cprintf(const char *format, ...)
{
    // Drop for now; a real backend renders into the text grid.
    (void)format;
}
void putwch(char32_t) {}
void puttext(int, int, const crawl_view_buffer &) {}
void update_screen() {}

// ---- input ---------------------------------------------------------------
bool kbhit() { return false; }
void delay(unsigned int ms) { if (ms) usleep(ms * 1000); }

int getch_ck()
{
    // No input wired yet — block so the engine idles instead of spinning.
    for (;;) { usleep(100 * 1000); }
    return 0;
}

void set_mouse_enabled(bool) {}

// ---- headless ------------------------------------------------------------
bool in_headless_mode()   { return s_headless; }
void enter_headless_mode() { s_headless = true; }

// ---- display info --------------------------------------------------------
lib_display_info::lib_display_info()
    : type("iOS"), term("ios-console"), fg_colors(16), bg_colors(8)
{
}
