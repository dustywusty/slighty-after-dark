#pragma once

// Loads every saver offscreen and checks that its assets resolve, its CSS
// animations run, and the presentation script applies (the /verify argument).
// This is the Windows counterpart of macos/scripts/runtime-smoke-test.swift.
// Returns the process exit code.
int RunVerification();
