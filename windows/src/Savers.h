#pragma once

#include <array>
#include <string_view>

struct SaverInfo {
    std::wstring_view title;
    std::wstring_view filename;
};

// kSavers is generated from shared/savers.txt; see cmake/Savers.cmake.
#include "savers.inc"
