#!/bin/sh
# gleam watch — file watcher: rebuild on source changes
# Usage: ./scripts/watch.sh [--test]

GLEAM_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$GLEAM_DIR"

echo "👁  Watching Gleamunison source files for changes..."
echo "   Press Ctrl+C to stop."

LAST_HASH=""

while true; do
  # Compute hash of all source files
  CURRENT_HASH=$(find src -name '*.gleam' -o -name '*.erl' | sort | xargs cat 2>/dev/null | shasum -a 256 2>/dev/null)

  if [ "$CURRENT_HASH" != "$LAST_HASH" ] && [ -n "$LAST_HASH" ]; then
    echo ""
    echo "📦 Change detected — rebuilding..."
    gleam build
    BUILD_EXIT=$?

    if [ $BUILD_EXIT -eq 0 ]; then
      echo "✅ Build succeeded"

      if [ "$1" = "--test" ]; then
        echo "🧪 Running tests..."
        gleam test
        TEST_EXIT=$?
        if [ $TEST_EXIT -eq 0 ]; then
          echo "✅ Tests passed"
        else
          echo "❌ Tests failed"
        fi
      fi
    else
      echo "❌ Build failed"
    fi

    echo "👁  Watching for changes..."
  fi

  LAST_HASH="$CURRENT_HASH"
  sleep 1
done
