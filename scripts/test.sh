#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

flags=()
if ! xcode-select -p 2>/dev/null | grep -q '\.app/'; then
    toolchain=/Library/Developer/CommandLineTools
    frameworks=$toolchain/Library/Developer/Frameworks
    libraries=$toolchain/Library/Developer/usr/lib
    testing_plugins=$toolchain/usr/lib/swift/host/plugins/testing
    flags=(
        -Xswiftc -F -Xswiftc "$frameworks"
        -Xlinker -rpath -Xlinker "$frameworks"
        -Xlinker -rpath -Xlinker "$libraries"
    )
    if [ -d "$testing_plugins" ]; then
        flags+=(-Xswiftc -plugin-path -Xswiftc "$testing_plugins")
    fi
fi

exec swift test ${flags[@]+"${flags[@]}"} "$@"
