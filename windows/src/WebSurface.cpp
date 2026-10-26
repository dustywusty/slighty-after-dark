#include "WebSurface.h"

#include "Assets.h"

#include <shlobj.h>
#include <shlwapi.h>
#include <wrl/event.h>

using Microsoft::WRL::Callback;
using Microsoft::WRL::ComPtr;

namespace {

constexpr wchar_t kWindowClassName[] = L"SlightlyAfterDarkSurface";

// Hides the pointer inside the page; WM_SETCURSOR only covers the host window.
constexpr wchar_t kHideCursorScript[] =
    L"document.addEventListener('DOMContentLoaded', function () {"
    L"var style = document.createElement('style');"
    L"style.textContent = '*, *::before, *::after { cursor: none !important; }';"
    L"document.documentElement.appendChild(style);"
    L"});";

void RegisterWindowClass(WNDPROC windowProc)
{
    static bool registered = false;
    if (registered) {
        return;
    }
    WNDCLASSEXW windowClass = {sizeof(windowClass)};
    windowClass.style = CS_HREDRAW | CS_VREDRAW;
    windowClass.lpfnWndProc = windowProc;
    windowClass.hInstance = GetModuleHandleW(nullptr);
    windowClass.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    windowClass.hbrBackground = static_cast<HBRUSH>(GetStockObject(BLACK_BRUSH));
    windowClass.lpszClassName = kWindowClassName;
    RegisterClassExW(&windowClass);
    registered = true;
}

std::wstring TakeCoTaskString(LPWSTR value)
{
    std::wstring result = value != nullptr ? value : L"";
    CoTaskMemFree(value);
    return result;
}

}  // namespace

HRESULT CreateSaverEnvironment(
    std::function<void(HRESULT, ICoreWebView2Environment*)> completion)
{
    PWSTR localAppData = nullptr;
    HRESULT result = SHGetKnownFolderPath(FOLDERID_LocalAppData, KF_FLAG_CREATE, nullptr, &localAppData);
    if (FAILED(result)) {
        return result;
    }
    std::wstring userDataFolder = TakeCoTaskString(localAppData) + L"\\Slightly After Dark\\WebView2";

    return CreateCoreWebView2EnvironmentWithOptions(nullptr, userDataFolder.c_str(), nullptr,
        Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>(
            [completion](HRESULT error, ICoreWebView2Environment* environment) -> HRESULT {
                completion(error, environment);
                return S_OK;
            }).Get());
}

WebSurface::WebSurface(const Options& options)
    : options_(options)
{
    RegisterWindowClass(&WebSurface::WindowProc);
    const RECT& bounds = options.bounds;
    window_ = CreateWindowExW(options.extendedStyle, kWindowClassName, L"Slightly After Dark",
                              options.style, bounds.left, bounds.top,
                              bounds.right - bounds.left, bounds.bottom - bounds.top,
                              options.parent, nullptr, GetModuleHandleW(nullptr), this);
}

WebSurface::~WebSurface()
{
    Close();
    if (window_ != nullptr) {
        SetWindowLongPtrW(window_, GWLP_USERDATA, 0);
        DestroyWindow(window_);
    }
}

void WebSurface::CreateWebView(ICoreWebView2Environment* environment, CompletionHandler completion)
{
    environment_ = environment;
    HRESULT result = environment->CreateCoreWebView2Controller(window_,
        Callback<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>(
            [this, completion](HRESULT error, ICoreWebView2Controller* controller) -> HRESULT {
                if (closed_) {
                    if (controller != nullptr) {
                        controller->Close();
                    }
                    return S_OK;
                }
                if (SUCCEEDED(error) && controller != nullptr) {
                    controller_ = controller;
                    error = ConfigureWebView();
                }
                if (FAILED(error)) {
                    ShowError(L"Slightly After Dark could not start the WebView2 renderer.");
                }
                if (completion) {
                    completion(error);
                }
                return S_OK;
            }).Get());
    if (FAILED(result)) {
        ShowError(L"Slightly After Dark could not start the WebView2 renderer.");
        if (completion) {
            completion(result);
        }
    }
}

HRESULT WebSurface::ConfigureWebView()
{
    HRESULT result = controller_->get_CoreWebView2(&webView_);
    if (FAILED(result)) {
        return result;
    }

    ComPtr<ICoreWebView2Controller2> controller2;
    if (SUCCEEDED(controller_.As(&controller2))) {
        controller2->put_DefaultBackgroundColor(COREWEBVIEW2_COLOR{255, 0, 0, 0});
    }

    ComPtr<ICoreWebView2Settings> settings;
    if (SUCCEEDED(webView_->get_Settings(&settings))) {
        settings->put_AreDefaultContextMenusEnabled(FALSE);
        settings->put_AreDefaultScriptDialogsEnabled(FALSE);
        settings->put_AreDevToolsEnabled(FALSE);
        settings->put_IsStatusBarEnabled(FALSE);
        settings->put_IsZoomControlEnabled(FALSE);
        ComPtr<ICoreWebView2Settings3> settings3;
        if (SUCCEEDED(settings.As(&settings3))) {
            settings3->put_AreBrowserAcceleratorKeysEnabled(FALSE);
        }
    }

    std::wstring filter(kAssetOrigin);
    filter += L"/*";
    result = webView_->AddWebResourceRequestedFilter(filter.c_str(), COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL);
    if (FAILED(result)) {
        return result;
    }

    EventRegistrationToken token;
    webView_->add_WebResourceRequested(
        Callback<ICoreWebView2WebResourceRequestedEventHandler>(
            [this](ICoreWebView2*, ICoreWebView2WebResourceRequestedEventArgs* args) -> HRESULT {
                ServeAsset(args);
                return S_OK;
            }).Get(),
        &token);

    // Screen savers only ever show the bundled pages.
    webView_->add_NavigationStarting(
        Callback<ICoreWebView2NavigationStartingEventHandler>(
            [](ICoreWebView2*, ICoreWebView2NavigationStartingEventArgs* args) -> HRESULT {
                LPWSTR uri = nullptr;
                if (FAILED(args->get_Uri(&uri)) || !AssetPathForURI(TakeCoTaskString(uri))) {
                    args->put_Cancel(TRUE);
                }
                return S_OK;
            }).Get(),
        &token);
    webView_->add_NewWindowRequested(
        Callback<ICoreWebView2NewWindowRequestedEventHandler>(
            [](ICoreWebView2*, ICoreWebView2NewWindowRequestedEventArgs* args) -> HRESULT {
                args->put_Handled(TRUE);
                return S_OK;
            }).Get(),
        &token);
    webView_->add_NavigationCompleted(
        Callback<ICoreWebView2NavigationCompletedEventHandler>(
            [this](ICoreWebView2*, ICoreWebView2NavigationCompletedEventArgs* args) -> HRESULT {
                BOOL succeeded = FALSE;
                args->get_IsSuccess(&succeeded);
                if (navigationHandler_) {
                    navigationHandler_(succeeded != FALSE);
                }
                return S_OK;
            }).Get(),
        &token);

    if (options_.hidesCursor) {
        webView_->AddScriptToExecuteOnDocumentCreated(kHideCursorScript, nullptr);
    }

    controller_->put_ZoomFactor(options_.zoomFactor);
    UpdateBounds();
    controller_->put_IsVisible(TRUE);
    return S_OK;
}

void WebSurface::ServeAsset(ICoreWebView2WebResourceRequestedEventArgs* args)
{
    ComPtr<ICoreWebView2WebResourceRequest> request;
    LPWSTR rawURI = nullptr;
    if (FAILED(args->get_Request(&request)) || FAILED(request->get_Uri(&rawURI))) {
        return;
    }
    std::wstring uri = TakeCoTaskString(rawURI);

    ComPtr<ICoreWebView2WebResourceResponse> response;
    std::optional<std::wstring> path = AssetPathForURI(uri);
    std::optional<std::span<const std::byte>> asset = path ? FindAsset(*path) : std::nullopt;
    if (!asset) {
        ++missingAssetCount_;
        environment_->CreateWebResourceResponse(nullptr, 404, L"Not Found", L"", &response);
    } else {
        ComPtr<IStream> stream;
        stream.Attach(SHCreateMemStream(reinterpret_cast<const BYTE*>(asset->data()),
                                        static_cast<UINT>(asset->size())));
        std::wstring headers = L"Content-Type: ";
        headers += ContentTypeForAssetPath(*path);
        environment_->CreateWebResourceResponse(stream.Get(), 200, L"OK", headers.c_str(), &response);
    }
    if (response != nullptr) {
        args->put_Response(response.Get());
    }
}

void WebSurface::Navigate(const std::wstring& url)
{
    if (webView_ != nullptr) {
        webView_->Navigate(url.c_str());
    }
}

void WebSurface::ExecuteScript(const std::wstring& script, ScriptHandler completion)
{
    if (webView_ == nullptr || script.empty()) {
        if (completion) {
            completion(E_NOT_VALID_STATE, L"");
        }
        return;
    }
    webView_->ExecuteScript(script.c_str(),
        Callback<ICoreWebView2ExecuteScriptCompletedHandler>(
            [completion](HRESULT error, LPCWSTR resultJSON) -> HRESULT {
                if (completion) {
                    completion(error, resultJSON != nullptr ? resultJSON : L"");
                }
                return S_OK;
            }).Get());
}

void WebSurface::ShowError(std::wstring message)
{
    errorMessage_ = std::move(message);
    if (window_ != nullptr) {
        InvalidateRect(window_, nullptr, TRUE);
    }
}

void WebSurface::Close()
{
    if (closed_) {
        return;
    }
    closed_ = true;
    if (controller_ != nullptr) {
        controller_->Close();
    }
    controller_.Reset();
    webView_.Reset();
    environment_.Reset();
}

void WebSurface::UpdateBounds()
{
    if (controller_ == nullptr) {
        return;
    }
    RECT bounds;
    GetClientRect(window_, &bounds);
    controller_->put_Bounds(bounds);
}

void WebSurface::Paint()
{
    PAINTSTRUCT paint;
    HDC context = BeginPaint(window_, &paint);
    RECT bounds;
    GetClientRect(window_, &bounds);
    FillRect(context, &bounds, static_cast<HBRUSH>(GetStockObject(BLACK_BRUSH)));
    if (!errorMessage_.empty()) {
        SetBkMode(context, TRANSPARENT);
        SetTextColor(context, RGB(255, 255, 255));
        HGDIOBJ previousFont = SelectObject(context, GetStockObject(DEFAULT_GUI_FONT));
        InflateRect(&bounds, -16, -16);
        DrawTextW(context, errorMessage_.c_str(), -1, &bounds,
                  DT_CENTER | DT_VCENTER | DT_WORDBREAK);
        SelectObject(context, previousFont);
    }
    EndPaint(window_, &paint);
}

LRESULT CALLBACK WebSurface::WindowProc(HWND window, UINT message, WPARAM wParam, LPARAM lParam)
{
    if (message == WM_NCCREATE) {
        auto create = reinterpret_cast<CREATESTRUCTW*>(lParam);
        auto surface = static_cast<WebSurface*>(create->lpCreateParams);
        surface->window_ = window;
        SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(surface));
    }
    auto surface = reinterpret_cast<WebSurface*>(GetWindowLongPtrW(window, GWLP_USERDATA));
    if (surface == nullptr) {
        return DefWindowProcW(window, message, wParam, lParam);
    }
    return surface->HandleMessage(message, wParam, lParam);
}

LRESULT WebSurface::HandleMessage(UINT message, WPARAM wParam, LPARAM lParam)
{
    switch (message) {
    case WM_SIZE:
        UpdateBounds();
        return 0;
    case WM_PAINT:
        Paint();
        return 0;
    case WM_ERASEBKGND:
        return 1;
    case WM_SETCURSOR:
        if (options_.hidesCursor) {
            SetCursor(nullptr);
            return TRUE;
        }
        break;
    case WM_DESTROY: {
        HWND window = window_;
        Close();
        window_ = nullptr;
        SetWindowLongPtrW(window, GWLP_USERDATA, 0);
        if (destroyedHandler_) {
            destroyedHandler_();
        }
        return 0;
    }
    }
    return DefWindowProcW(window_, message, wParam, lParam);
}
