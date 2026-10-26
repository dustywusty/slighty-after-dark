#include "Assets.h"

#include "resource.h"

#include <windows.h>

namespace {

struct AssetEntry {
    std::wstring_view path;
    int resourceID;
};

constexpr AssetEntry kAssets[] = {
#include "asset_table.inc"
};

std::optional<std::span<const std::byte>> LoadResourceData(int resourceID)
{
    HMODULE module = GetModuleHandleW(nullptr);
    HRSRC resource = FindResourceW(module, MAKEINTRESOURCEW(resourceID), RT_RCDATA);
    if (resource == nullptr) {
        return std::nullopt;
    }
    HGLOBAL handle = LoadResource(module, resource);
    const void* data = handle != nullptr ? LockResource(handle) : nullptr;
    if (data == nullptr) {
        return std::nullopt;
    }
    return std::span(static_cast<const std::byte*>(data), SizeofResource(module, resource));
}

}  // namespace

std::wstring SaverPageURL(std::wstring_view saverFilename)
{
    std::wstring url(kAssetOrigin);
    url += L"/all/";
    url += saverFilename;
    url += L".html";
    return url;
}

std::optional<std::span<const std::byte>> FindAsset(std::wstring_view path)
{
    for (const AssetEntry& asset : kAssets) {
        if (asset.path == path) {
            return LoadResourceData(asset.resourceID);
        }
    }
    return std::nullopt;
}

std::optional<std::wstring> AssetPathForURI(std::wstring_view uri)
{
    if (!uri.starts_with(kAssetOrigin) || uri.size() <= kAssetOrigin.size()
        || uri[kAssetOrigin.size()] != L'/') {
        return std::nullopt;
    }
    std::wstring_view path = uri.substr(kAssetOrigin.size() + 1);
    path = path.substr(0, path.find_first_of(L"?#"));
    return std::wstring(path);
}

std::wstring_view ContentTypeForAssetPath(std::wstring_view path)
{
    struct Mapping {
        std::wstring_view extension;
        std::wstring_view contentType;
    };
    static constexpr Mapping kMappings[] = {
        {L".html", L"text/html; charset=utf-8"},
        {L".css", L"text/css; charset=utf-8"},
        {L".js", L"text/javascript; charset=utf-8"},
        {L".png", L"image/png"},
        {L".gif", L"image/gif"},
        {L".jpg", L"image/jpeg"},
        {L".svg", L"image/svg+xml"},
        {L".ttf", L"font/ttf"},
        {L".woff", L"font/woff"},
        {L".woff2", L"font/woff2"},
    };
    for (const Mapping& mapping : kMappings) {
        if (path.ends_with(mapping.extension)) {
            return mapping.contentType;
        }
    }
    return L"application/octet-stream";
}

const std::wstring& PagePresentationFunctionSource()
{
    static const std::wstring source = [] {
        auto data = LoadResourceData(IDR_PAGE_PRESENTATION_SCRIPT);
        if (!data || data->empty()) {
            return std::wstring();
        }
        auto bytes = reinterpret_cast<const char*>(data->data());
        int length = static_cast<int>(data->size());
        if (length >= 3 && bytes[0] == '\xEF' && bytes[1] == '\xBB' && bytes[2] == '\xBF') {
            bytes += 3;
            length -= 3;
        }
        std::wstring decoded(MultiByteToWideChar(CP_UTF8, 0, bytes, length, nullptr, 0), L'\0');
        MultiByteToWideChar(CP_UTF8, 0, bytes, length, decoded.data(), static_cast<int>(decoded.size()));
        return decoded;
    }();
    return source;
}

std::wstring PagePresentationScript(int objectScalePercent, int playbackSpeedPercent)
{
    const std::wstring& source = PagePresentationFunctionSource();
    if (source.empty()) {
        return {};
    }
    // Chromium follows the display refresh rate and owns the CSS timeline, so
    // the page script controls animation speed directly, as with WKWebView.
    return source + L"(" + std::to_wstring(objectScalePercent) + L", "
        + std::to_wstring(playbackSpeedPercent) + L", true)";
}
