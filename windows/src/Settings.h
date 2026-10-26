#pragma once

#include <string>

inline constexpr int kDefaultObjectScalePercent = 100;
inline constexpr int kMinimumObjectScalePercent = 50;
inline constexpr int kMaximumObjectScalePercent = 200;
inline constexpr int kDefaultPlaybackSpeedPercent = 100;
inline constexpr int kMinimumPlaybackSpeedPercent = 50;
inline constexpr int kMaximumPlaybackSpeedPercent = 200;

// Options stored under HKCU\Software\Slightly After Dark, using the same value
// names as the macOS ScreenSaverDefaults keys.
struct Settings {
    std::wstring saver;
    int objectScalePercent = kDefaultObjectScalePercent;
    int playbackSpeedPercent = kDefaultPlaybackSpeedPercent;
    bool showMemoryUsage = false;

    static Settings Load();
    bool Save() const;
};
