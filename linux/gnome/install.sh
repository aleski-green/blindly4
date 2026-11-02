#!/bin/sh
set -eu
if [ "$#" -lt 1 ] || [ "$1" != --accept-foreground-verification ]; then
    echo 'Review Foreground.js and install.sh, then run install.sh --accept-foreground-verification [--shell-version VERSION] to consent to installation.' >&2
    exit 64
fi
case $# in
    1) version=$(gnome-shell --version 2>/dev/null | sed -n 's/^GNOME Shell \([0-9]*\).*/\1/p') ;;
    3) [ "$2" = --shell-version ] || exit 64; version=$3 ;;
    *) exit 64 ;;
esac
case $version in 42|46|50) ;; *) echo 'Supported GNOME Shell versions: 42, 46, 50. Select the installed version.' >&2; exit 64 ;; esac
source_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
case ${XDG_DATA_HOME:-} in
    /*) data=$XDG_DATA_HOME ;;
    *) data=$HOME/.local/share ;;
esac
destination=$data/gnome-shell/extensions/foreground@blindly4.sapiens4
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
if [ "$version" = 42 ]; then
    printf '%s\n' 'const {Gio, Clutter, Meta} = imports.gi;' 'const Main = imports.ui.main;' 'const Extension = Object;' > "$temporary/extension.js"
else
    cat > "$temporary/extension.js" <<'EOF'
import Gio from 'gi://Gio';
import Clutter from 'gi://Clutter';
import Meta from 'gi://Meta';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
EOF
fi
cat "$source_directory/Foreground.js" >> "$temporary/extension.js"
if [ "$version" = 42 ]; then
    printf '\nfunction init() { return new Foreground(); }\n' >> "$temporary/extension.js"
else
    printf '\nexport default Foreground;\n' >> "$temporary/extension.js"
fi
sed 's/"shell-version": \[[^]]*\]/"shell-version": ["'"$version"'"]/' "$source_directory/metadata.json" > "$temporary/metadata.json"
mkdir -p "$destination"
install -m 644 "$temporary/extension.js" "$temporary/metadata.json" "$destination/"
printf 'Installed source in %s\nLog out and back in, then explicitly enable:\ngnome-extensions enable foreground@blindly4.sapiens4\n' "$destination"
