# Fetches the pinned WebView2 SDK from NuGet and exposes WebView2::Loader.
# The static loader is linked so the .scr does not need WebView2Loader.dll.

include(FetchContent)

set(SAD_WEBVIEW2_VERSION "1.0.2903.40")

FetchContent_Declare(webview2
    URL "https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2/${SAD_WEBVIEW2_VERSION}"
    URL_HASH SHA256=ef128016dd1e51c59178c827ed5b8aa3322c57afa8675d930f8109505542ad74
    DOWNLOAD_NAME "microsoft.web.webview2.${SAD_WEBVIEW2_VERSION}.zip"
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE
)
FetchContent_MakeAvailable(webview2)

string(TOLOWER "${CMAKE_CXX_COMPILER_ARCHITECTURE_ID}" _sad_architecture)
if(_sad_architecture STREQUAL "x64" OR _sad_architecture STREQUAL "arm64" OR _sad_architecture STREQUAL "x86")
    set(_sad_webview2_architecture "${_sad_architecture}")
else()
    message(FATAL_ERROR "Unsupported target architecture: ${CMAKE_CXX_COMPILER_ARCHITECTURE_ID}")
endif()

add_library(WebView2::Loader STATIC IMPORTED)
set_target_properties(WebView2::Loader PROPERTIES
    IMPORTED_LOCATION "${webview2_SOURCE_DIR}/build/native/${_sad_webview2_architecture}/WebView2LoaderStatic.lib"
    INTERFACE_INCLUDE_DIRECTORIES "${webview2_SOURCE_DIR}/build/native/include"
)
