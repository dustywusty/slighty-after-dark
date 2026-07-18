#!/bin/sh

set -eu

bundle=${1:?"usage: verify-bundle.sh /path/to/Slightly After Dark.saver"}
info_plist="$bundle/Contents/Info.plist"

if [ ! -d "$bundle" ]; then
    echo "error: Screen saver bundle does not exist: $bundle" >&2
    exit 1
fi

/usr/bin/plutil -lint "$info_plist" >/dev/null

executable_name=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$info_plist")
executable="$bundle/Contents/MacOS/$executable_name"
architectures=$(/usr/bin/lipo -archs "$executable")

for architecture in arm64 x86_64
do
    case " $architectures " in
        *" $architecture "*) ;;
        *)
            echo "error: Bundle executable is missing $architecture (found: $architectures)" >&2
            exit 1
            ;;
    esac
done

/usr/bin/codesign --verify --deep --strict "$bundle"
/bin/sh "$(dirname "$0")/validate-assets.sh" "$bundle/Contents/Resources/after-dark-css"

echo "Verified universal, locally signed screen saver bundle: $bundle"
