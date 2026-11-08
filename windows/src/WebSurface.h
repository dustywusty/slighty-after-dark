#pragma once

#include <windows.h>
#include <wrl/client.h>

#include <WebView2.h>

#include <functional>
#include <string>

// Creates the shared WebView2 environment. Its profile lives in
// %LOCALAPPDATA%\Slightly After Dark because the .scr itself is often
// installed somewhere read-only, such as System32.
HRESULT CreateSaverEnvironment(
    std::function<void(HRESULT, ICoreWebView2Environment*)> completion);

// A window that hosts one WebView2 controller and serves the embedded
// after-dark-css assets to it. Every screen saver mode renders through this.
class WebSurface {
public:
    struct Options {
        DWORD style = WS_POPUP;
        DWORD extendedStyle = 0;
        RECT bounds = {};
        HWND parent = nullptr;
        bool hidesCursor = false;
        double zoomFactor = 1.0;
    };

    using CompletionHandler = std::function<void(HRESULT)>;
    using NavigationHandler = std::function<void(bool succeeded)>;
    using ScriptHandler = std::function<void(HRESULT, const std::wstring& resultJSON)>;

    explicit WebSurface(const Options& options);
    ~WebSurface();

    WebSurface(const WebSurface&) = delete;
    WebSurface& operator=(const WebSurface&) = delete;

    HWND Window() const { return window_; }
    int MissingAssetCount() const { return missingAssetCount_; }

    void CreateWebView(ICoreWebView2Environment* environment, CompletionHandler completion);
    void Navigate(const std::wstring& url);
    void ExecuteScript(const std::wstring& script, ScriptHandler completion = {});
    void ShowError(std::wstring message);
    void Close();

    void SetNavigationHandler(NavigationHandler handler) { navigationHandler_ = std::move(handler); }
    void SetDestroyedHandler(std::function<void()> handler) { destroyedHandler_ = std::move(handler); }

private:
    static LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wParam, LPARAM lParam);
    LRESULT HandleMessage(UINT message, WPARAM wParam, LPARAM lParam);

    HRESULT ConfigureWebView();
    void ServeAsset(ICoreWebView2WebResourceRequestedEventArgs* args);
    void UpdateBounds();
    void Paint();

    HWND window_ = nullptr;
    Options options_;
    bool closed_ = false;
    int missingAssetCount_ = 0;
    std::wstring errorMessage_;
    Microsoft::WRL::ComPtr<ICoreWebView2Environment> environment_;
    Microsoft::WRL::ComPtr<ICoreWebView2Controller> controller_;
    Microsoft::WRL::ComPtr<ICoreWebView2> webView_;
    NavigationHandler navigationHandler_;
    std::function<void()> destroyedHandler_;
};
