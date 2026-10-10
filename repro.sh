#!/usr/bin/env bash
# Starts dotnet watch, makes its re-evaluation fail, then changes one file.
# Expected: dotnet watch reports the error and waits for a fix.
# Actual:   dotnet watch dies with a NullReferenceException (exit 134).
set -u
cd "$(dirname "$0")"
export DOTNET_CLI_UI_LANGUAGE=en

log=watch.log
rm -f break-evaluation "$log"

wait_for() { # pattern, seconds
  for _ in $(seq 1 "$2"); do grep -q -E "$1" "$log" && return 0; sleep 1; done
  echo "Timed out waiting for: $1"; return 1
}

dotnet --version
dotnet watch run < /dev/null > "$log" 2>&1 &
watch_pid=$!

wait_for "Waiting for changes" 120 || { kill "$watch_pid"; exit 1; }

echo "1. Creating break-evaluation: re-evaluation fails on purpose."
touch break-evaluation
wait_for "Fix the error to continue" 60 || { kill "$watch_pid"; exit 1; }

echo "2. Deleting break-evaluation: any file change will do."
sleep 1
rm break-evaluation

for _ in $(seq 1 20); do kill -0 "$watch_pid" 2>/dev/null || break; sleep 1; done
if kill -0 "$watch_pid" 2>/dev/null; then
  echo "NOT REPRODUCED: dotnet watch is still running."
  kill "$watch_pid"
  exit 1
fi
wait "$watch_pid"
code=$?

echo
sed -n '/Unhandled exception/,$p' "$log"
echo
echo "dotnet watch exited with code $code."
pkill -f "bin/Debug/net10.0/Repro" && echo "The app outlived dotnet watch and was left running; stopped it now."
grep -q "NullReferenceException" "$log" && echo "REPRODUCED. Full output: $log"
