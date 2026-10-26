#pragma once

#include "Settings.h"

#include <windows.h>

// Runs the screen saver full screen on every monitor until the user moves the
// mouse, clicks, or presses a key (the /s argument).
int RunScreensaver(const Settings& settings);

// Renders inside the miniature preview in Screen Saver Settings until Windows
// destroys the parent window (the /p argument).
int RunPreview(HWND parent, const Settings& settings);
