#!/usr/bin/env bash
# make-widgetkit-spi.sh — stage a copy of the SDK WidgetKit framework with a few
# SPI declarations appended, so the widget target can call `preferredBackgroundStyle(.transparent)`.
#
# Why this exists: Apple ships `WidgetConfiguration.preferredBackgroundStyle(_:)` (and its
# `WidgetBackgroundStyle` enum) inside WidgetKit.framework, but the public .swiftinterface does
# not declare them on iOS 27. Real-device evidence (2026-09-21, device-probe4-P4P5-preferred-
# transparent-no-dim.jpg): when called, the widget renders fully transparent on the default
# Home Screen — no dim. The single-symbol call site is `PanelWidget.swift`; everything else
# is left untouched. Nothing from the SDK is committed: the framework is copied under
# `$DERIVED_FILE_DIR`-like paths only (PROJECT_TEMP_DIR per xcodegen), never under the repo.
#
# Usage:
#   make-widgetkit-spi.sh <SDKROOT> <OUT_DIR>
#     SDKROOT  — the SDK root Xcode hands the script ($SDKROOT) — device or simulator.
#     OUT_DIR  — platform-scoped staging dir (e.g. $PROJECT_TEMP_DIR/WidgetKitSPI/iphonesimulator).
#
# Idempotent: if the SPI symbols are already present, nothing is re-appended.

set -euo pipefail

SDKROOT="${1:?Usage: $0 SDKROOT OUT_DIR (SDKROOT = device or simulator SDK root)}"
OUT_DIR="${2:?Usage: $0 SDKROOT OUT_DIR}"

FRAMEWORK_SRC="$SDKROOT/System/Library/Frameworks/WidgetKit.framework"
SPI_BLOCK_FILE="$(mktemp -t widgetkit-spi.XXXXXX)"
trap 'rm -f "$SPI_BLOCK_FILE"' EXIT

# 1. Stage a writable copy of the framework under OUT_DIR.
rm -rf "$OUT_DIR/WidgetKit.framework"
mkdir -p "$OUT_DIR"
cp -R "$FRAMEWORK_SRC" "$OUT_DIR/"
chmod -R u+w "$OUT_DIR/WidgetKit.framework"

# 2. The SPI block. Verbatim — the .swiftinterface parser is whitespace-sensitive enough
#    that any divergence will fail the compile with "expected declaration" at this offset.
cat > "$SPI_BLOCK_FILE" <<'SPI'
@available(iOS 26.0, macOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
@available(visionOS, unavailable)
public enum WidgetBackgroundStyle : Swift::Int {
  case transparent
  case blur
  case opaque
  public init?(rawValue: Swift::Int)
  public typealias RawValue = Swift::Int
  public var rawValue: Swift::Int {
    get
  }
}
@available(iOS 26.0, macOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
@available(visionOS, unavailable)
extension SwiftUI::WidgetConfiguration {
  @_Concurrency::MainActor @preconcurrency public func preferredBackgroundStyle(_ style: WidgetKit::WidgetBackgroundStyle) -> some SwiftUI::WidgetConfiguration

}
SPI

# 3. Append to every .swiftinterface in the staged module. Idempotent: skip files that
#    already contain the SPI signature.
shopt -s nullglob
for f in "$OUT_DIR/WidgetKit.framework/Modules/WidgetKit.swiftmodule/"*.swiftinterface; do
  if grep -q "func preferredBackgroundStyle" "$f"; then
    continue
  fi
  printf '\n%s\n' "$(cat "$SPI_BLOCK_FILE")" >> "$f"
done
shopt -u nullglob

echo "staged WidgetKit SPI at $OUT_DIR/WidgetKit.framework"