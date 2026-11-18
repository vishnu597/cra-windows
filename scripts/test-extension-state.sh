#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d /tmp/cra-extension-state.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT
C=Packages/CraCore/Sources/CraCore
# ExtensionImport shares this profile-folder predicate with the bookmark/session importer.
# Compile its production method without pulling that importer's unrelated model dependencies.
{ echo "public enum ChromiumImporter {"; sed -n '/^    public static func isProfileFolder(/,/^    }/p' "$C/ChromiumImport.swift"; echo "}"; } \
  > "$TEST_DIR/ChromiumProfileFolders+Production.swift"
test "$(grep -c '^    public static func isProfileFolder(' "$TEST_DIR/ChromiumProfileFolders+Production.swift")" -eq 1
xcrun swiftc -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} Sources/Cra/Services/Import/ExtensionImporter.swift \
  "$TEST_DIR/ChromiumProfileFolders+Production.swift" \
  Packages/CraCore/Sources/CraCore/ExtensionIcons.swift Packages/CraCore/Sources/CraCore/InstalledExtensions.swift Packages/CraCore/Sources/CraCore/ExtensionImport.swift \
  Tests/ExtensionStateTests.swift -o "$TEST_DIR/extension-state-tests"
"$TEST_DIR/extension-state-tests"
[ -z "${CRA_TEST_KEEP:-}" ] || cp "$TEST_DIR/extension-state-tests" "$CRA_TEST_KEEP/"
