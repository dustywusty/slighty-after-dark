#pragma once

#include <array>
#include <string_view>

struct SaverInfo {
    std::wstring_view title;
    std::wstring_view filename;
};

// Keep in sync with availableSavers in macos/slightly-after-dark/SADScreenSaverView.m.
inline constexpr std::array<SaverInfo, 12> kSavers = {{
    {L"Flying Toasters", L"flying-toasters"},
    {L"Fish", L"fish"},
    {L"Globe", L"globe"},
    {L"Hard Rain", L"hard-rain"},
    {L"Bouncing Ball", L"bouncing-ball"},
    {L"Warp", L"warp"},
    {L"Messages", L"messages"},
    {L"Messages 2", L"messages2"},
    {L"Fade Out", L"fade-out"},
    {L"Logo", L"logo"},
    {L"Rainstorm", L"rainstorm"},
    {L"Spotlight", L"spotlight"},
}};
