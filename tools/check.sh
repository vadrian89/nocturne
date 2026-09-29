#!/usr/bin/env bash
# Syntax-checks every Lua file in the repo with luajit or luac.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0

if command -v luajit >/dev/null 2>&1; then
    CHECK=(luajit -bl)
elif command -v luac >/dev/null 2>&1; then
    CHECK=(luac -p)
else
    echo "error: neither luajit nor luac found on PATH" >&2
    exit 1
fi

while IFS= read -r -d '' f; do
    if ! "${CHECK[@]}" "$f" >/dev/null 2>/tmp/nocturne_check_err; then
        echo "syntax error: $f"
        cat /tmp/nocturne_check_err
        fail=1
    fi
done < <(find "$ROOT/addons" -name '*.lua' -print0)

rm -f /tmp/nocturne_check_err
[[ $fail -eq 0 ]] && echo "OK"
exit $fail
