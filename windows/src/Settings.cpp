#include "Settings.h"

#include "Savers.h"

#include <windows.h>

#include <algorithm>

namespace {

constexpr wchar_t kRegistryKey[] = L"Software\\Slightly After Dark";
constexpr wchar_t kSaverValue[] = L"ScreenSaver";
constexpr wchar_t kObjectScaleValue[] = L"ObjectScalePercent";
constexpr wchar_t kPlaybackSpeedValue[] = L"PlaybackSpeedPercent";
constexpr wchar_t kShowMemoryUsageValue[] = L"ShowMemoryUsage";

bool IsKnownSaver(std::wstring_view filename)
{
    return std::any_of(kSavers.begin(), kSavers.end(),
        [filename](const SaverInfo& saver) { return saver.filename == filename; });
}

int ReadInteger(const wchar_t* name, int defaultValue, int minimum, int maximum)
{
    DWORD value = 0;
    DWORD size = sizeof(value);
    if (RegGetValueW(HKEY_CURRENT_USER, kRegistryKey, name, RRF_RT_REG_DWORD,
                     nullptr, &value, &size) != ERROR_SUCCESS) {
        return defaultValue;
    }
    return std::clamp(static_cast<int>(value), minimum, maximum);
}

std::wstring ReadString(const wchar_t* name)
{
    wchar_t buffer[128] = {};
    DWORD size = sizeof(buffer);
    if (RegGetValueW(HKEY_CURRENT_USER, kRegistryKey, name, RRF_RT_REG_SZ,
                     nullptr, buffer, &size) != ERROR_SUCCESS) {
        return {};
    }
    return buffer;
}

bool WriteInteger(const wchar_t* name, int value)
{
    DWORD data = static_cast<DWORD>(value);
    return RegSetKeyValueW(HKEY_CURRENT_USER, kRegistryKey, name, REG_DWORD,
                           &data, sizeof(data)) == ERROR_SUCCESS;
}

}  // namespace

Settings Settings::Load()
{
    Settings settings;
    settings.saver = ReadString(kSaverValue);
    if (!IsKnownSaver(settings.saver)) {
        settings.saver = std::wstring(kSavers.front().filename);
    }
    settings.objectScalePercent = ReadInteger(kObjectScaleValue, kDefaultObjectScalePercent,
                                              kMinimumObjectScalePercent, kMaximumObjectScalePercent);
    settings.playbackSpeedPercent = ReadInteger(kPlaybackSpeedValue, kDefaultPlaybackSpeedPercent,
                                                kMinimumPlaybackSpeedPercent, kMaximumPlaybackSpeedPercent);
    settings.showMemoryUsage = ReadInteger(kShowMemoryUsageValue, 0, 0, 1) != 0;
    return settings;
}

bool Settings::Save() const
{
    const DWORD saverSize = static_cast<DWORD>((saver.size() + 1) * sizeof(wchar_t));
    bool saved = RegSetKeyValueW(HKEY_CURRENT_USER, kRegistryKey, kSaverValue, REG_SZ,
                                 saver.c_str(), saverSize) == ERROR_SUCCESS;
    saved = WriteInteger(kObjectScaleValue, objectScalePercent) && saved;
    saved = WriteInteger(kPlaybackSpeedValue, playbackSpeedPercent) && saved;
    saved = WriteInteger(kShowMemoryUsageValue, showMemoryUsage ? 1 : 0) && saved;
    return saved;
}
