#!/usr/bin/env zsh
# Accurate 16 KB page-size scanner using the Program Headers "Align" column.
set -euo pipefail

ART="${1:?Usage: $0 <your.aab|your.apk>}"

# Pick a readelf variant
if command -v greadelf >/dev/null 2>&1; then
  READ_ELF="greadelf"
elif [[ -x "$(brew --prefix binutils 2>/dev/null)/bin/greadelf" ]]; then
  READ_ELF="$(brew --prefix binutils)/bin/greadelf"
elif command -v readelf >/dev/null 2>&1; then
  READ_ELF="readelf"
elif command -v llvm-readelf >/dev/null 2>&1; then
  READ_ELF="llvm-readelf"
else
  echo "Need readelf. Try: brew install binutils" >&2
  exit 1
fi

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
unzip -q "$ART" -d "$tmp"

# If bundle contains APKs, unzip them too so we see their .so files
apklist=$(find "$tmp" -type f -name '*.apk' || true)
if [[ -n "$apklist" ]]; then
  while IFS= read -r apk; do
    d="$tmp/nested/${apk##*/}"
    mkdir -p "$d"
    unzip -q "$apk" -d "$d"
  done <<< "$apklist"
fi

# All .so files
sos=$(find "$tmp" -type f -name '*.so' | sort || true)
cnt=$(print -r -- "$sos" | grep -c . || true)

echo "Using: $READ_ELF"
echo "Found $cnt .so file(s)."
[[ "$cnt" == "0" ]] && { echo "Nothing to scan."; exit 0; }
echo

# Get max page size by reading the Align column on LOAD rows
psize_align() {
  local so="$1"
  local out maxhex
  out="$("$READ_ELF" -W -l "$so" 2>/dev/null)" || { echo ""; return; }

  # 1) direct "Max page size:" (GNU readelf sometimes prints this)
  local direct
  direct="$(printf "%s\n" "$out" | awk '/Max page size:/ {print $4; found=1} END{if(!found) print ""}')"
  [[ -n "$direct" ]] && { echo "$direct"; return; }

  # 2) Parse Align column robustly
  maxhex="$(
    printf "%s\n" "$out" \
    | awk '
        /^ *Type/ {
          ai=0;
          for(i=1;i<=NF;i++) if($i=="Align"){ ai=i; break }
          next
        }
        ai && /^ *LOAD/ { print $ai }
      ' \
    | awk '
        BEGIN{max=""}
        {
          val=$0
          # normalize: ensure hex string like 0x... where possible
          if (val ~ /^0x[0-9a-fA-F]+$/) {
            h=val
          } else if (val ~ /^[0-9]+$/) {
            # decimal: print as is (we will handle in zsh)
            print val; next
          } else {
            next
          }
          # track maximum hex by length then lexicographic (case-insensitive)
          nh=h; mh=max
          gsub(/^0x/,"",nh); gsub(/^0x/,"",mh)
          if (max=="" || length(nh)>length(mh) || (length(nh)==length(mh) && toupper(nh)>toupper(mh))) max=h
        }
        END{
          if (max!="") print max
        }
      '
  )"

  # If decimal already, return it
  if [[ "$maxhex" == <-> ]]; then
    echo "$maxhex"; return
  fi
  # If hex like 0x..., convert to decimal with zsh arithmetic
  if [[ "$maxhex" == 0x* ]]; then
    echo $(( maxhex )); return
  fi

  echo ""
}

violations_file="$tmp/violations.txt"
: > "$violations_file"

print -r -- "$sos" | while IFS= read -r so; do
  [[ -n "$so" ]] || continue
  ps="$(psize_align "$so")"

  # Derive ABI from path .../lib/<abi>/libX.so if present
  abi="${so##*/lib/}"; abi="${abi%%/*}"; [[ "$abi" == "$so" || -z "$abi" ]] && abi="?"
  name="${so##*/}"

  if [[ -z "$ps" || "$ps" == "0" ]]; then
    printf "%-10s %-48s -> could not determine page size\n" "$abi" "$name"
    continue
  fi

  if (( ps > 16384 )); then
    printf "%-10s %-48s -> Max page size: %-6s **VIOLATION**\n" "$abi" "$name" "$ps"
    echo "$so -> $ps" >> "$violations_file"
  else
    printf "%-10s %-48s -> Max page size: %-6s OK\n" "$abi" "$name" "$ps"
  fi
done

echo
if [[ -s "$violations_file" ]]; then
  bad=$(wc -l < "$violations_file" | tr -d ' ')
  echo "Found $bad offending libraries (> 16384). Rebuild/update those with:"
  echo '  -Wl,-z,max-page-size=16384'
  echo
  echo "Offenders:"
  sed 's/^/ - /' "$violations_file"
  exit 2
else
  echo "All native libraries comply with the 16 KB page-size requirement."
fi
