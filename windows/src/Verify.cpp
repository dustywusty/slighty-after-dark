#include "Verify.h"

#include "Assets.h"
#include "Savers.h"
#include "WebSurface.h"

#include <wrl/client.h>

#include <cwchar>
#include <memory>
#include <string>
#include <vector>

using Microsoft::WRL::ComPtr;

namespace {

constexpr int kTestScalePercent = 150;
constexpr int kTestSpeedPercent = 125;
constexpr DWORD kStateTimeoutMilliseconds = 5000;
constexpr UINT kPollIntervalMilliseconds = 50;
constexpr LONG kTestWidth = 1024;
constexpr LONG kTestHeight = 768;

constexpr wchar_t kStateScript[] =
    L"(function () {"
    L"var data = document.documentElement.dataset;"
    L"var animations = document.getAnimations ? document.getAnimations() : [];"
    L"return [document.readyState, data.sadObjectScale, data.sadPlaybackSpeed,"
    L"animations.length, animations.length ? animations[0].playbackRate : 0].join(' ');"
    L"})()";

struct Verification {
    ComPtr<ICoreWebView2Environment> environment;
    std::unique_ptr<WebSurface> surface;
    size_t saverIndex = 0;
    int missingAssetsBeforePage = 0;
    ULONGLONG stateDeadline = 0;
    std::wstring lastState;
    int failures = 0;
};

Verification* gVerification = nullptr;

void Log(const std::wstring& line)
{
    std::wstring text = line + L"\r\n";
    int size = WideCharToMultiByte(CP_UTF8, 0, text.c_str(), static_cast<int>(text.size()),
                                   nullptr, 0, nullptr, nullptr);
    std::string utf8(size, '\0');
    WideCharToMultiByte(CP_UTF8, 0, text.c_str(), static_cast<int>(text.size()),
                        utf8.data(), size, nullptr, nullptr);
    DWORD written = 0;
    WriteFile(GetStdHandle(STD_OUTPUT_HANDLE), utf8.data(), static_cast<DWORD>(utf8.size()),
              &written, nullptr);
}

const SaverInfo& CurrentSaver()
{
    return kSavers[gVerification->saverIndex];
}

void LoadNextSaver();

void FinishSaver(bool passed, const std::wstring& detail)
{
    Verification& verification = *gVerification;
    std::wstring name(CurrentSaver().filename);
    int missingAssets = verification.surface->MissingAssetCount() - verification.missingAssetsBeforePage;
    if (passed && missingAssets > 0) {
        passed = false;
    }
    if (passed) {
        Log(L"ok   " + name + L" (" + detail + L")");
    } else {
        ++verification.failures;
        std::wstring reason = missingAssets > 0
            ? std::to_wstring(missingAssets) + L" missing asset request(s); " + detail
            : detail;
        Log(L"FAIL " + name + L": " + reason);
    }
    ++verification.saverIndex;
    LoadNextSaver();
}

void CALLBACK PollState(HWND, UINT, UINT_PTR timerID, DWORD);

void SchedulePoll()
{
    SetTimer(nullptr, 0, kPollIntervalMilliseconds, PollState);
}

// Expects "complete <scale> <speed> <animationCount> <playbackRate>".
bool StateIsExpected(const std::wstring& state)
{
    wchar_t readyState[32] = {};
    int scale = 0;
    int speed = 0;
    int animationCount = 0;
    double playbackRate = 0;
    if (swscanf_s(state.c_str(), L"\"%31s %d %d %d %lf\"", readyState, 32,
                  &scale, &speed, &animationCount, &playbackRate) != 5) {
        return false;
    }
    double expectedRate = kTestSpeedPercent / 100.0;
    return std::wstring(readyState) == L"complete"
        && scale == kTestScalePercent && speed == kTestSpeedPercent
        && animationCount > 0
        && playbackRate > expectedRate - 0.01 && playbackRate < expectedRate + 0.01;
}

void CALLBACK PollState(HWND, UINT, UINT_PTR timerID, DWORD)
{
    KillTimer(nullptr, timerID);
    gVerification->surface->ExecuteScript(kStateScript, [](HRESULT error, const std::wstring& state) {
        Verification& verification = *gVerification;
        if (SUCCEEDED(error)) {
            verification.lastState = state;
            if (StateIsExpected(state)) {
                FinishSaver(true, L"state " + state);
                return;
            }
        }
        if (GetTickCount64() > verification.stateDeadline) {
            FinishSaver(false, L"timed out; last state " + verification.lastState);
            return;
        }
        SchedulePoll();
    });
}

void LoadNextSaver()
{
    Verification& verification = *gVerification;
    if (verification.saverIndex >= kSavers.size()) {
        Log(verification.failures == 0
            ? L"Verified " + std::to_wstring(kSavers.size()) + L" savers."
            : std::to_wstring(verification.failures) + L" saver(s) failed verification.");
        PostQuitMessage(verification.failures == 0 ? 0 : 1);
        return;
    }
    verification.missingAssetsBeforePage = verification.surface->MissingAssetCount();
    verification.lastState.clear();
    verification.surface->Navigate(SaverPageURL(CurrentSaver().filename));
}

void HandleNavigation(bool succeeded)
{
    Verification& verification = *gVerification;
    if (!succeeded) {
        FinishSaver(false, L"navigation failed");
        return;
    }
    std::wstring script = PagePresentationScript(kTestScalePercent, kTestSpeedPercent);
    if (script.empty()) {
        FinishSaver(false, L"page-presentation.js is not embedded");
        return;
    }
    verification.surface->ExecuteScript(script);
    verification.stateDeadline = GetTickCount64() + kStateTimeoutMilliseconds;
    SchedulePoll();
}

}  // namespace

int RunVerification()
{
    Verification verification;
    gVerification = &verification;

    WebSurface::Options options;
    options.style = WS_POPUP;
    options.extendedStyle = WS_EX_TOOLWINDOW;
    options.bounds = {0, 0, kTestWidth, kTestHeight};
    verification.surface = std::make_unique<WebSurface>(options);
    verification.surface->SetNavigationHandler(HandleNavigation);

    HRESULT result = CreateSaverEnvironment([&verification](HRESULT error, ICoreWebView2Environment* environment) {
        if (FAILED(error) || environment == nullptr) {
            wchar_t code[16];
            swprintf_s(code, L"0x%08lX", static_cast<unsigned long>(error));
            Log(std::wstring(L"FAIL could not create the WebView2 environment (") + code + L")");
            PostQuitMessage(1);
            return;
        }
        verification.environment = environment;
        verification.surface->CreateWebView(environment, [](HRESULT createError) {
            if (FAILED(createError)) {
                Log(L"FAIL could not create the WebView2 controller");
                PostQuitMessage(1);
                return;
            }
            LoadNextSaver();
        });
    });
    if (FAILED(result)) {
        Log(L"FAIL the WebView2 runtime is unavailable");
        return 1;
    }

    MSG message;
    while (GetMessageW(&message, nullptr, 0, 0) > 0) {
        TranslateMessage(&message);
        DispatchMessageW(&message);
    }
    verification.surface.reset();
    gVerification = nullptr;
    return static_cast<int>(message.wParam);
}
