#!/bin/sh
set -eu
umask 077
pid="$1"; package="$2"; target="$3"; work="$4"
case "$package" in "$work"/payload/*.app) ;; *) exit 2 ;; esac
case "$target" in /*.app) ;; *) exit 2 ;; esac
[ ! -L "$target" ] || exit 2
parent=$(/usr/bin/dirname "$target")
stage="$parent/.WindowNest-update-$$.app"
previous="$parent/.WindowNest-rollback-$$.app"
finish() {
    result=$?
    trap - EXIT
    if [ "$result" -ne 0 ]; then
        if [ -d "$previous" ]; then
            /bin/rm -rf "$target"
            /bin/mv "$previous" "$target"
        fi
        printf '%s\n' 'Update failed; the previous application and all user data were retained.' > "$work/install-error.txt"
        if [ "${5:-}" != "--no-launch" ]; then /usr/bin/open "$target" || true; fi
    fi
    /bin/rm -rf "$stage"
    exit "$result"
}
trap finish EXIT
count=0
while /bin/kill -0 "$pid" 2>/dev/null; do
    count=$((count+1));[ "$count" -lt 150 ] || exit 3
    /bin/sleep 0.2
done
[ "$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$package/Contents/Info.plist")" = "local.windownest.app" ]
[ "$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$target/Contents/Info.plist")" = "local.windownest.app" ]
/usr/bin/ditto "$package" "$stage"
/usr/bin/codesign --verify --deep --strict "$stage"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$target" "$work/previous.zip"
/bin/mv "$target" "$previous"
/bin/mv "$stage" "$target"
if [ "${5:-}" != "--no-launch" ]; then /usr/bin/open "$target"; fi
/bin/rm -rf "$previous" "$package"
/bin/rm -f "$work/update.zip"
printf '%s\n' installed > "$work/status.txt"
updates=$(/usr/bin/dirname "$work")
for obsolete in "$updates"/*.noindex; do
    [ "$obsolete" != "$work" ] || continue
    if [ -f "$obsolete/status.txt" ] && [ "$(/bin/cat "$obsolete/status.txt")" = installed ]; then
        /bin/rm -rf "$obsolete"
    fi
done
