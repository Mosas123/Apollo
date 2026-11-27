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

swiftc -swift-version 6 -emit-library -emit-module -module-name SwiftyTube \
  "$temp_dir/SwiftyTube.swift" \
  -emit-module-path "$temp_dir/SwiftyTube.swiftmodule" \
  -o "$temp_dir/libSwiftyTube.dylib"

swiftc -swift-version 6 -strict-concurrency=complete -parse-as-library \
  -I "$temp_dir" -L "$temp_dir" -lSwiftyTube \
  Apollo/Utilities/Log.swift tests/Logging/FileLogLaunchChecks.swift \
  -o "$temp_dir/file-log-launch-checks"

DYLD_LIBRARY_PATH="$temp_dir" "$temp_dir/file-log-launch-checks" --explicit
DYLD_LIBRARY_PATH="$temp_dir" "$temp_dir/file-log-launch-checks" --implicit

# Ensure startup owns the reset, not scenePhase or foreground notifications.
grep -Fq 'FileLog.shared.beginNewLaunch()' Apollo/ApolloApp.swift
grep -Fq 'APP_LOG_SESSION_START build=' Apollo/ApolloApp.swift
grep -Fq 'self.prepareLaunchFileIfNeeded(url)' Apollo/Utilities/Log.swift
grep -Fq 'try Data().write(to: url, options: .atomic)' Apollo/Utilities/Log.swift
grep -Fq 'appendingPathComponent("log.previous.txt")' Apollo/Utilities/Log.swift

echo 'Apollo log reset per process checks passed'
