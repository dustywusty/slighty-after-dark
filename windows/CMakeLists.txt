cmake_minimum_required(VERSION 3.24)

project(SlightlyAfterDark VERSION 1.0.0 LANGUAGES CXX RC)

if(NOT MSVC)
    message(FATAL_ERROR "The Windows screen saver must be built with MSVC.")
endif()

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
# A static CRT keeps the .scr a single self-contained file.
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

get_filename_component(SAD_REPOSITORY_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/.." ABSOLUTE)
set(SAD_SHARED_ROOT "${SAD_REPOSITORY_ROOT}/shared")
set(SAD_ASSET_ROOT "${SAD_SHARED_ROOT}/after-dark-css")

include(cmake/WebView2.cmake)
include(cmake/EmbedAssets.cmake)

configure_file(src/version.h.in "${CMAKE_CURRENT_BINARY_DIR}/generated/version.h" @ONLY)

add_executable(SlightlyAfterDark WIN32
    src/main.cpp
    src/Assets.cpp
    src/ConfigDialog.cpp
    src/Screensaver.cpp
    src/Settings.cpp
    src/Verify.cpp
    src/WebSurface.cpp
    src/SlightlyAfterDark.rc
    src/SlightlyAfterDark.manifest
    "${SAD_GENERATED_ASSET_RC}"
)

set_target_properties(SlightlyAfterDark PROPERTIES
    OUTPUT_NAME "Slightly After Dark"
    SUFFIX ".scr"
)

target_include_directories(SlightlyAfterDark PRIVATE
    src
    "${CMAKE_CURRENT_BINARY_DIR}/generated"
)

target_compile_definitions(SlightlyAfterDark PRIVATE
    UNICODE
    _UNICODE
    WIN32_LEAN_AND_MEAN
    NOMINMAX
)

target_compile_options(SlightlyAfterDark PRIVATE
    $<$<COMPILE_LANGUAGE:CXX>:/W4 /permissive- /utf-8>
)

target_link_libraries(SlightlyAfterDark PRIVATE
    WebView2::Loader
    comctl32
    shlwapi
    version
)
