#pragma once

#include <optional>
#include <span>
#include <string>
#include <string_view>

// Origin that serves the embedded after-dark-css assets to WebView2. The
// .example TLD is reserved, so it can never resolve to a real site.
inline constexpr std::wstring_view kAssetOrigin = L"https://slightly-after-dark.example";

std::wstring SaverPageURL(std::wstring_view saverFilename);

// Looks up an embedded asset by its path relative to after-dark-css,
// for example "all/fish.html".
std::optional<std::span<const std::byte>> FindAsset(std::wstring_view path);

// Maps a request URI under kAssetOrigin to an asset path. Returns nullopt for
// any other origin.
std::optional<std::wstring> AssetPathForURI(std::wstring_view uri);

std::wstring_view ContentTypeForAssetPath(std::wstring_view path);

// The shared page-presentation.js function expression, decoded from UTF-8.
const std::wstring& PagePresentationFunctionSource();

std::wstring PagePresentationScript(int objectScalePercent, int playbackSpeedPercent);
