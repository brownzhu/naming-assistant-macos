#!/usr/bin/env bash
# Integration tests for the macrename CLI. Each scenario copies a fixture
# directory to a fresh tmp dir, runs macrename, and compares the resulting
# file tree (or stdout) to an expected value.
set -uo pipefail

cd "$(dirname "$0")/.."

echo "Building macrename..."
if ! swift build --product macrename >/dev/null 2>&1; then
  echo "swift build failed." >&2
  swift build --product macrename
  exit 1
fi

CLI="$(pwd)/.build/debug/macrename"
FIXTURES="$(pwd)/Tests/Fixtures"
PASS=0
FAIL=0
FAILED=()

# Compare the file tree under $1 to the newline-separated expected list in $2.
tree_of() {
  # iconv UTF-8-MAC → UTF-8 normalizes macOS NFD filenames (e.g. café) to NFC.
  (cd "$1" && find . -mindepth 1 \! -name '.DS_Store' | sed 's|^\./||' | iconv -f utf-8-mac -t utf-8 | sort)
}

# run_tree NAME FIXTURE EXPECTED_TREE -- ARGS...
# ARGS can use {DIR} as the placeholder for the temp fixture directory.
run_tree() {
  local name="$1" fixture="$2" expected="$3"
  shift 3
  [[ "$1" == "--" ]] && shift
  local tmp; tmp="$(mktemp -d)"
  cp -R "$FIXTURES/$fixture/." "$tmp/"
  local args=()
  for a in "$@"; do
    local expanded="${a//\{DIR\}/$tmp}"
    if [[ "$expanded" == *"*"* ]]; then
      while IFS= read -r g; do args+=("$g"); done < <(printf '%s\n' $expanded | LC_ALL=C sort)
    else
      args+=("$expanded")
    fi
  done
  "$CLI" "${args[@]}" >/dev/null 2>&1 || true
  local actual; actual="$(tree_of "$tmp")"
  if [[ "$actual" == "$expected" ]]; then
    echo "  ✓ $name"; PASS=$((PASS+1))
  else
    echo "  ✗ $name"
    diff <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") | sed 's/^/      /'
    FAIL=$((FAIL+1)); FAILED+=("$name")
  fi
  rm -rf "$tmp"
}

# run_stdout_match NAME FIXTURE REGEX -- ARGS...
# Asserts that macrename's stdout matches the given extended regex.
run_stdout_match() {
  local name="$1" fixture="$2" pattern="$3"
  shift 3
  [[ "$1" == "--" ]] && shift
  local tmp; tmp="$(mktemp -d)"
  cp -R "$FIXTURES/$fixture/." "$tmp/"
  local args=()
  for a in "$@"; do
    local expanded="${a//\{DIR\}/$tmp}"
    if [[ "$expanded" == *"*"* ]]; then
      while IFS= read -r g; do args+=("$g"); done < <(printf '%s\n' $expanded | LC_ALL=C sort)
    else
      args+=("$expanded")
    fi
  done
  local out; out="$("$CLI" "${args[@]}" 2>&1 || true)"
  if grep -qE "$pattern" <<<"$out"; then
    echo "  ✓ $name"; PASS=$((PASS+1))
  else
    echo "  ✗ $name (pattern /$pattern/ not found)"
    echo "      stdout:"
    echo "$out" | sed 's/^/        /'
    FAIL=$((FAIL+1)); FAILED+=("$name")
  fi
  rm -rf "$tmp"
}

echo
echo "=== Basic search/replace ==="
run_tree "literal replace" simple \
$'draft-new.md\nnotes-new.txt\nreport-new.txt' \
  -- rename -s old -r new "{DIR}"

run_tree "case-insensitive (default)" simple \
$'draft-new.md\nnotes-new.txt\nreport-new.txt' \
  -- rename -s OLD -r new "{DIR}"

run_tree "case-sensitive skips mismatched case" simple \
$'draft-old.md\nnotes-old.txt\nreport-old.txt' \
  -- rename -s OLD -r new --case-sensitive "{DIR}"

run_tree "first occurrence only by default" match-all \
$'bb-aa-aa.txt' \
  -- rename -s aa -r bb "{DIR}"

run_tree "match-all replaces every occurrence" match-all \
$'bb-bb-bb.txt' \
  -- rename -s aa -r bb --all "{DIR}"

echo
echo "=== Case transforms ==="
run_tree "uppercase (transform applies when no match)" mixed-case \
$'HELLO_WORLD.MD\nTHE_QUICK_BROWN_FOX.TXT' \
  -- rename -s 'zzzzzz' --uppercase "{DIR}/*"

run_tree "lowercase" mixed-case \
$'hello_world.md\nthe_quick_brown_fox.txt' \
  -- rename -s 'zzzzzz' --lowercase "{DIR}/*"

echo
echo "=== Scope flags ==="
run_tree "name-only leaves extension untouched" simple \
$'draft-new.md\nnotes-new.txt\nreport-new.txt' \
  -- rename -s old -r new --name-only "{DIR}"

run_tree "exclude-files renames only folders" scope \
$'bar-dir\nbar-dir/keep.txt\nfile-foo.txt' \
  -- rename -s foo -r bar --exclude-files "{DIR}"

run_tree "exclude-folders renames only files" scope \
$'file-bar.txt\nfoo-dir\nfoo-dir/keep.txt' \
  -- rename -s foo -r bar --exclude-folders "{DIR}"

echo
echo "=== Recursion ==="
run_tree "default recurses into subfolders" nested \
$'sub1\nsub1/deep-bar.txt\nsub2\nsub2/nested-bar.txt\ntop-bar.txt' \
  -- rename -s foo -r bar "{DIR}"

run_tree "no-recurse only touches top level" nested \
$'sub1\nsub1/deep-foo.txt\nsub2\nsub2/nested-foo.txt\ntop-bar.txt' \
  -- rename -s foo -r bar --no-recurse "{DIR}/*"

echo
echo "=== Regex ==="
run_tree "regex capture groups reorder name" regex \
$'notes-2023.txt\nreport-2024.txt' \
  -- rename --regex -s '^(\d+)-(.+)\.txt$' -r '$2-$1.txt' "{DIR}"

echo
echo "=== Enumeration token ==="
run_tree "enumeration with padding" enum \
$'file01-a.txt\nfile02-b.txt\nfile03-c.txt' \
  -- rename --enumerate -s item -r 'file${start=1,padding=2}' "{DIR}"

echo
echo "=== Tricky names ==="
run_tree "spaces, unicode, multiple dots preserved" tricky-names \
$'RENAMED café.txt\nRENAMED has space.txt\nRENAMED v1.2.3.txt' \
  -- rename --regex -s '^' -r 'RENAMED ' "{DIR}/*"

echo
echo "=== Non-deterministic tokens (format checks) ==="
run_stdout_match "random 4 digits" random \
  '^r1\.txt → [0-9]{4}\.txt' \
  -- preview --randomize -s 'r1' -r '${rstringdigit=4}' "{DIR}/r1.txt"

run_stdout_match "datetime YYYY-MM-DD (modification-time)" random \
  '^r1\.txt → [0-9]{4}-[0-9]{2}-[0-9]{2}\.txt' \
  -- preview --modification-time -s 'r1' -r '$YYYY-$MM-$DD' "{DIR}/r1.txt"

echo
echo "=== EXIF metadata tokens ==="
run_tree "rename from EXIF tokens (make + date + iso)" images \
$'Canon-20240315-ISO400.jpg\nNikon-20231122-ISO800.jpg' \
  -- rename --exif --regex --name-only -s '.+' \
            -r '$CAMERA_MAKE-$DATE_TAKEN_YYYY$DATE_TAKEN_MM$DATE_TAKEN_DD-ISO$ISO' \
            "{DIR}/*.jpg"

run_stdout_match "preview surfaces camera model" images \
  'IMG_0001\.jpg → EOS 5D\.jpg' \
  -- preview --exif --regex --name-only -s '.+' -r '$CAMERA_MODEL' "{DIR}/IMG_0001.jpg"

run_stdout_match "unknown token left as-is when EXIF flag off" images \
  '\$CAMERA_MAKE' \
  -- preview --regex --name-only -s '.+' -r '$CAMERA_MAKE' "{DIR}/IMG_0001.jpg"

echo
echo "=== Unicode normalization ==="
# macOS older HFS+ volumes return NFD filenames; ensure an NFC search term
# still matches a file whose name is stored in NFD.
{
  unicode_tmp="$(mktemp -d)"
  # NFD "café.txt" = "cafe" + U+0301 (combining acute) + ".txt"
  nfd_name="$(printf 'cafe\xcc\x81.txt')"
  touch "$unicode_tmp/$nfd_name"
  "$CLI" rename -s 'é' -r 'É' "$unicode_tmp/$nfd_name" >/dev/null 2>&1 || true
  if (cd "$unicode_tmp" && ls | iconv -f utf-8-mac -t utf-8) | grep -q 'cafÉ'; then
    echo "  ✓ NFD filename matches NFC search term"; PASS=$((PASS+1))
  else
    echo "  ✗ NFD filename matches NFC search term"
    echo "      files: $(cd "$unicode_tmp" && ls | iconv -f utf-8-mac -t utf-8)"
    FAIL=$((FAIL+1)); FAILED+=("NFD/NFC unicode normalization")
  fi
  rm -rf "$unicode_tmp"
}

echo
echo "=== Validation errors (preview only) ==="
run_stdout_match "invalid character / rejected" invalid \
  'invalid characters' \
  -- preview -s 'file' -r 'bad/name' "{DIR}"

# Build a 260-char replacement that exceeds the 255-byte filename limit.
long="$(printf 'a%.0s' {1..260})"
run_stdout_match "filename too long rejected" invalid \
  'filename too long' \
  -- preview -s 'file' -r "$long" "{DIR}"

echo
echo "─────────────────────────────────────────"
echo "Passed: $PASS    Failed: $FAIL"
if (( FAIL > 0 )); then
  printf '  - %s\n' "${FAILED[@]}"
  exit 1
fi
