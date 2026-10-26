#pragma once

#include <windows.h>

// Shows the Options dialog (the /c argument). OK saves the settings; Cancel
// leaves the saved settings untouched.
int RunConfigDialog(HWND owner);
