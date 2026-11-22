#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

# Build only the logging code on the macOS runner; no signing or iOS
# simulator required. A tiny stub supplies SwiftyTubeLog's public interface.
cat > "$temp_dir/SwiftyTube.swift" <<'SWIFT'
public enum SwiftyTubeLog {
    public enum Level { case debug, info, notice, error }
    public static var handler: (@Sendable (String, Level) -> Void)? {
        get { nil }
        set {}
    }
}
SWIFT

swiftc -swift-version 6 -emit-module -module-name SwiftyTube \
  "$temp_dir/SwiftyTube.swift" \
  -emit-module-path "$temp_dir/SwiftyTube.swiftmodule"

swiftc -swift-version 6 -strict-concurrency=complete -parse-as-library \
  -I "$temp_dir" Trop/Utilities/Log.swift \
  tests/Logging/FileLogLaunchChecks.swift \
  -o "$temp_dir/file-log-launch-checks"

"$temp_dir/file-log-launch-checks" --explicit
"$temp_dir/file-log-launch-checks" --implicit

# Ensure startup owns the reset, not scenePhase or foreground notifications.
grep -Fq 'FileLog.shared.beginNewLaunch()' Trop/TropApp.swift
grep -Fq 'APP_LOG_SESSION_START build=' Trop/TropApp.swift
grep -Fq 'self.prepareLaunchFileIfNeeded(url)' Trop/Utilities/Log.swift
grep -Fq 'try Data().write(to: url, options: .atomic)' Trop/Utilities/Log.swift

echo 'Trop log reset per process checks passed'
