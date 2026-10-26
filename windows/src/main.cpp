#include "ConfigDialog.h"
#include "Screensaver.h"
#include "Settings.h"
#include "Verify.h"

#include <windows.h>
#include <objbase.h>
#include <shellapi.h>

#include <cwchar>
#include <cwctype>
#include <string>

namespace {

enum class Mode { Configure, Screensaver, Preview, Verify };

struct Invocation {
    Mode mode = Mode::Configure;
    HWND window = nullptr;
};

HWND ParseWindowHandle(const wchar_t* text)
{
    return reinterpret_cast<HWND>(static_cast<UINT_PTR>(std::wcstoull(text, nullptr, 10)));
}

// Windows passes "/s", "/p <hwnd>", "/c", or "/c:<hwnd>", in either case and
// with "-" or "/". Launching the file directly passes no arguments.
Invocation ParseCommandLine()
{
    Invocation invocation;
    int count = 0;
    LPWSTR* arguments = CommandLineToArgvW(GetCommandLineW(), &count);
    if (arguments == nullptr || count < 2) {
        LocalFree(arguments);
        return invocation;
    }

    std::wstring option = arguments[1];
    if (!option.empty() && (option[0] == L'/' || option[0] == L'-')) {
        option.erase(0, 1);
    }
    for (wchar_t& character : option) {
        character = static_cast<wchar_t>(std::towlower(character));
    }

    std::wstring command = option.substr(0, option.find(L':'));
    const wchar_t* handleText = nullptr;
    if (option.find(L':') != std::wstring::npos) {
        handleText = arguments[1] + (arguments[1][0] == L'/' || arguments[1][0] == L'-' ? 1 : 0)
            + command.size() + 1;
    } else if (count >= 3) {
        handleText = arguments[2];
    }

    if (command == L"s") {
        invocation.mode = Mode::Screensaver;
    } else if (command == L"p") {
        invocation.mode = Mode::Preview;
    } else if (command == L"verify") {
        invocation.mode = Mode::Verify;
    }
    if (handleText != nullptr) {
        invocation.window = ParseWindowHandle(handleText);
    }
    LocalFree(arguments);
    return invocation;
}

}  // namespace

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int)
{
    Invocation invocation = ParseCommandLine();
    if (FAILED(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED))) {
        return 1;
    }

    int exitCode = 0;
    switch (invocation.mode) {
    case Mode::Configure:
        exitCode = RunConfigDialog(invocation.window);
        break;
    case Mode::Screensaver:
        exitCode = RunScreensaver(Settings::Load());
        break;
    case Mode::Preview:
        exitCode = invocation.window != nullptr ? RunPreview(invocation.window, Settings::Load()) : 1;
        break;
    case Mode::Verify:
        exitCode = RunVerification();
        break;
    }

    CoUninitialize();
    return exitCode;
}
