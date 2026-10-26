#include "Screensaver.h"

#include "Assets.h"
#include "WebSurface.h"

#include <psapi.h>
#include <wrl/client.h>

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <memory>
#include <vector>

using Microsoft::WRL::ComPtr;

namespace {

constexpr wchar_t kRuntimeMissingMessage[] =
    L"Slightly After Dark needs the Microsoft Edge WebView2 Runtime.\n"
    L"Install it from https://developer.microsoft.com/microsoft-edge/webview2/";
// Matches the slack Windows' own screen savers give a resting mouse.
constexpr LONG kMouseMoveThreshold = 8;
// Previews lay pages out as if on a screen at least this wide.
constexpr double kPreviewLayoutWidth = 1024.0;
constexpr UINT kMemoryUsageUpdateIntervalMilliseconds = 1000;

struct Session {
    Settings settings;
    ComPtr<ICoreWebView2Environment> environment;
    std::vector<std::unique_ptr<WebSurface>> surfaces;
    POINT initialCursorPosition = {};
    bool quitting = false;
};

Session* gSession = nullptr;

void Quit()
{
    if (gSession != nullptr && !gSession->quitting) {
        gSession->quitting = true;
        PostQuitMessage(0);
    }
}

LRESULT CALLBACK LowLevelMouseProc(int code, WPARAM wParam, LPARAM lParam)
{
    if (code == HC_ACTION && gSession != nullptr) {
        auto event = reinterpret_cast<const MSLLHOOKSTRUCT*>(lParam);
        switch (wParam) {
        case WM_MOUSEMOVE: {
            const POINT& origin = gSession->initialCursorPosition;
            if (std::abs(event->pt.x - origin.x) > kMouseMoveThreshold
                || std::abs(event->pt.y - origin.y) > kMouseMoveThreshold) {
                Quit();
            }
            break;
        }
        case WM_LBUTTONDOWN:
        case WM_RBUTTONDOWN:
        case WM_MBUTTONDOWN:
        case WM_XBUTTONDOWN:
        case WM_MOUSEWHEEL:
        case WM_MOUSEHWHEEL:
            Quit();
            break;
        }
    }
    return CallNextHookEx(nullptr, code, wParam, lParam);
}

LRESULT CALLBACK LowLevelKeyboardProc(int code, WPARAM wParam, LPARAM lParam)
{
    if (code == HC_ACTION && (wParam == WM_KEYDOWN || wParam == WM_SYSKEYDOWN)) {
        Quit();
    }
    return CallNextHookEx(nullptr, code, wParam, lParam);
}

BOOL CALLBACK CollectMonitor(HMONITOR monitor, HDC, LPRECT, LPARAM data)
{
    MONITORINFO info = {sizeof(info)};
    if (GetMonitorInfoW(monitor, &info)) {
        reinterpret_cast<std::vector<RECT>*>(data)->push_back(info.rcMonitor);
    }
    return TRUE;
}

// Sums the working sets of this process and its WebView2 browser, GPU, and
// renderer processes, which together hold what the macOS host keeps in-process.
std::wstring MemoryUsageText(ICoreWebView2Environment* environment)
{
    std::vector<DWORD> processIDs = {GetCurrentProcessId()};
    ComPtr<ICoreWebView2Environment8> environment8;
    ComPtr<ICoreWebView2ProcessInfoCollection> processes;
    UINT count = 0;
    if (environment != nullptr && SUCCEEDED(environment->QueryInterface(IID_PPV_ARGS(&environment8)))
        && SUCCEEDED(environment8->GetProcessInfos(&processes))
        && SUCCEEDED(processes->get_Count(&count))) {
        for (UINT index = 0; index < count; ++index) {
            ComPtr<ICoreWebView2ProcessInfo> process;
            INT32 processID = 0;
            if (SUCCEEDED(processes->GetValueAtIndex(index, &process))
                && SUCCEEDED(process->get_ProcessId(&processID))) {
                processIDs.push_back(static_cast<DWORD>(processID));
            }
        }
    }

    SIZE_T workingSetBytes = 0;
    for (DWORD processID : processIDs) {
        HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, processID);
        if (process == nullptr) {
            continue;
        }
        PROCESS_MEMORY_COUNTERS counters = {sizeof(counters)};
        if (GetProcessMemoryInfo(process, &counters, sizeof(counters))) {
            workingSetBytes += counters.WorkingSetSize;
        }
        CloseHandle(process);
    }

    wchar_t text[64];
    swprintf_s(text, L"Process memory: %.1f MB", workingSetBytes / (1024.0 * 1024.0));
    return text;
}

std::wstring MemoryUsageScript(const std::wstring& text)
{
    return L"(function (text) {"
           L"var label = document.getElementById('sad-memory-usage');"
           L"if (!label) {"
           L"label = document.createElement('div');"
           L"label.id = 'sad-memory-usage';"
           L"label.style.cssText = 'position:fixed;left:0;top:0;z-index:2147483647;"
           L"padding:4px 8px;background:rgba(0,0,0,0.65);color:#fff;"
           L"font:13px Consolas,monospace;pointer-events:none;white-space:pre';"
           L"document.documentElement.appendChild(label);"
           L"}"
           L"label.textContent = text;"
           L"})('" + text + L"')";
}

void CALLBACK UpdateMemoryUsage(HWND, UINT, UINT_PTR, DWORD)
{
    if (gSession == nullptr || gSession->environment == nullptr) {
        return;
    }
    std::wstring script = MemoryUsageScript(MemoryUsageText(gSession->environment.Get()));
    for (auto& surface : gSession->surfaces) {
        surface->ExecuteScript(script);
    }
}

// Creates the WebView2 environment and loads the selected saver into every
// surface of the session.
void StartRendering(Session& session)
{
    HRESULT result = CreateSaverEnvironment(
        [&session](HRESULT error, ICoreWebView2Environment* environment) {
            if (FAILED(error) || environment == nullptr) {
                for (auto& surface : session.surfaces) {
                    surface->ShowError(kRuntimeMissingMessage);
                }
                return;
            }
            session.environment = environment;
            std::wstring pageURL = SaverPageURL(session.settings.saver);
            std::wstring presentationScript = PagePresentationScript(
                session.settings.objectScalePercent, session.settings.playbackSpeedPercent);
            for (auto& surface : session.surfaces) {
                WebSurface* target = surface.get();
                target->SetNavigationHandler([target, presentationScript](bool succeeded) {
                    if (succeeded) {
                        target->ExecuteScript(presentationScript);
                    }
                });
                target->CreateWebView(environment, [target, pageURL](HRESULT createError) {
                    if (SUCCEEDED(createError)) {
                        target->Navigate(pageURL);
                    }
                });
            }
            if (session.settings.showMemoryUsage) {
                SetTimer(nullptr, 0, kMemoryUsageUpdateIntervalMilliseconds, UpdateMemoryUsage);
            }
        });
    if (FAILED(result)) {
        for (auto& surface : session.surfaces) {
            surface->ShowError(kRuntimeMissingMessage);
        }
    }
}

int RunMessageLoop()
{
    MSG message;
    while (GetMessageW(&message, nullptr, 0, 0) > 0) {
        TranslateMessage(&message);
        DispatchMessageW(&message);
    }
    return static_cast<int>(message.wParam);
}

}  // namespace

int RunScreensaver(const Settings& settings)
{
    // Windows can ask for the screen saver again while it is already running.
    HANDLE instanceMutex = CreateMutexW(nullptr, TRUE, L"Local\\SlightlyAfterDark.Screensaver");
    if (instanceMutex == nullptr || GetLastError() == ERROR_ALREADY_EXISTS) {
        if (instanceMutex != nullptr) {
            CloseHandle(instanceMutex);
        }
        return 0;
    }

    Session session;
    session.settings = settings;
    GetCursorPos(&session.initialCursorPosition);
    gSession = &session;

    std::vector<RECT> monitors;
    EnumDisplayMonitors(nullptr, nullptr, CollectMonitor, reinterpret_cast<LPARAM>(&monitors));
    for (const RECT& monitor : monitors) {
        WebSurface::Options options;
        options.style = WS_POPUP | WS_VISIBLE;
        options.extendedStyle = WS_EX_TOPMOST | WS_EX_TOOLWINDOW;
        options.bounds = monitor;
        options.hidesCursor = true;
        auto surface = std::make_unique<WebSurface>(options);
        surface->SetDestroyedHandler(Quit);
        session.surfaces.push_back(std::move(surface));
    }
    if (!session.surfaces.empty()) {
        SetForegroundWindow(session.surfaces.front()->Window());
    }

    HHOOK mouseHook = SetWindowsHookExW(WH_MOUSE_LL, LowLevelMouseProc, GetModuleHandleW(nullptr), 0);
    HHOOK keyboardHook = SetWindowsHookExW(WH_KEYBOARD_LL, LowLevelKeyboardProc, GetModuleHandleW(nullptr), 0);

    StartRendering(session);
    int exitCode = RunMessageLoop();

    if (mouseHook != nullptr) {
        UnhookWindowsHookEx(mouseHook);
    }
    if (keyboardHook != nullptr) {
        UnhookWindowsHookEx(keyboardHook);
    }
    session.surfaces.clear();
    gSession = nullptr;
    CloseHandle(instanceMutex);
    return exitCode;
}

int RunPreview(HWND parent, const Settings& settings)
{
    RECT bounds;
    if (!IsWindow(parent) || !GetClientRect(parent, &bounds)) {
        return 1;
    }

    Session session;
    session.settings = settings;
    gSession = &session;

    WebSurface::Options options;
    options.style = WS_CHILD | WS_VISIBLE;
    options.parent = parent;
    options.bounds = bounds;
    options.zoomFactor = std::clamp((bounds.right - bounds.left) / kPreviewLayoutWidth, 0.25, 1.0);
    auto surface = std::make_unique<WebSurface>(options);
    surface->SetDestroyedHandler(Quit);
    session.surfaces.push_back(std::move(surface));

    StartRendering(session);
    int exitCode = RunMessageLoop();

    session.surfaces.clear();
    gSession = nullptr;
    return exitCode;
}
