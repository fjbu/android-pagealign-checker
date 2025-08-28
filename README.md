# scan_align

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Fast, accurate checker for **Google Play's 16 KB page size requirement** on Android native libraries (`.so`) inside **AAB** or **APK** files.

- ✅ Works on **AAB** and **APK**
- ✅ Handles **nested APKs** inside AABs
- ✅ Accurate: reads **Program Headers ✢ Align** column (no false highs)
- ✅ macOS & Linux
- ✅ No signing required (debug builds are fine)
---

## Why?

Google Play now rejects apps if any native library (`.so`) uses a **page size > 16 KB**. This script finds offenders quickly so you can rebuild or update the right dependency.

---

## Requirements

- **zsh**
- A `readelf` implementation:
  - macOS: `brew install binutils` — `greadelf`
  - or `brew install llvm` — `llvm-readelf`
  - Linux: `binutils` (`readelf`)
- `unzip` (usually present)

No Gradle/Android Studio required to scan — you just need an **AAB** or **APK** file.

---

## Install

Clone this repo and make the script executable:

```bash
# change permission once
chmod +x scan_align.zsh
```

(Optionally add it to your $PATH).

## Usage

```bash
# Scan an AAB
./scan_align.zsh app/build/outputs/bundle/release/app-release.aab

# Scan an APK (e.g., from the Android Studio “Run/Play” build)
./scan_align.zsh app/build/outputs/apk/debug/app-debug.apk
```


Tip: Build a local bundle without CI:

```bash
./gradlew :app:bundleRelease   # or :app:bundleDebug / :app:bundleYourFlavorDebug
```

Outputs typically land in:
- `app/build/outputs/bundle/<buildType>/*.aab`
- `app/build/outputs/apk/<buildType>/*.apk`

---

## Example output

```
Using: /opt/homebrew/opt/binutils/bin/greadelf
Found 20 .so file(s).

arm64-v8a  libc++_shared.so    -> Max page size: 16384  OK
arm64-v8a   libjniPdfium.so     -> Max page size: 16384  OK
x86_64     libmodpng.so        -> Max page size: 16384  OK
x86        libfoo.so           -> Max page size: 4096   OK

All native libraries comply with the 16 KB page-size requirement.
```

Violations:

```
arm64-x8va  libbar.so -> Max page size: 65536 VIOLATION
+Found 1 offending libraries (> 16384). Rebuild/update those with:
  -Wl,-z,max-page-size=16384

Offenders: 
/lib/arm64-x8va/libbar.so -> 65536
```

---

## Exit codes

- `0` - All good (no violations)
- `2` - One or more violations found
- `>0` other - Tooling/setup errors (e.g., no readelf found)

Use this to **fail CI** when violations appear.

---

## CI usage (GitHub Actions)

Add `.github/workflows/ci.yml`

```a
name: Page Size Check
on: [push, pull_request]

jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up JDK
        uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: 17

      - name: Build AAB
        run: ./gradlew :app:bundleRelease

      - name: Install binutils
        run: sudo apt-get update && sudo apt-get install -y binutils unzip

      - name: Run scan
        run: |
          chmod +x scan_align.zsh
          ./scan_align.zsh app/build/outputs/bundle/release/app-release.aab
```

---

## Fixing violations (quick pointers)

- **Rebuild native libs** with:
  ````
  -Wl,-z,max-page-size=16384
  ````
  - **CMake**:
    ````cmake
    target_link_options(<target> PRIVATE "-Wl,-z,max-page-size=16384")
    ````
  - **ndk-build**:
    ````make
    LOCAL_LDFLAGS += -Wl,-z,max-page-size=16384
    ````

- **Update 3rd-party SDKs** that bundle `.so` files to versions that comply with 16 KB.

- **Avoid obsolete ABIs** (e.g., `mips`/`mips64`) via Gradle:
  ```gradle
  android {
    defaultConfig {
      ndk { abiFilters "arm64-v8a", "armeabi-v7a" }
    }
    packagingOptions {
      jniLibs {
        excludes += ["*/mips/*", "**/mips64/**"]
      }
    }
  ```

- **libc++_shared.so conflicts**: if a dependency ships a non-compliant one, override with the NDK copy in `app/src/main/jniLibs/`.

---

## How it works (technical)

For each `.so`, the script runs `readelf -W -l` and:

1. Uses the direct `Max page size:` field if GNU readelf provides it.
2. Otherwise parses **Program Headers** and takes the **maximum Align** value among `LOAD` segments.  Hex like `0x4000` — 16384. Any value **> 16384** is flagged.

This avoids false positives from “naive hex` greps.

---

## FAQ

**Does signing matter?**
No. The script just unzips and reads ELF headers. Signed/unsigned, debug/release - all fine.

**The “Play” button builds an APK – is that OK?**
Yes. You can scan the APK produced by Android Studio (it’s in `app/build/outputs/apk/...`). For parity with Play Console, scan the AAB. 

**I see `4096`. Is that OK?**
Yes. The rule is —"‎16384". Many libs still align at 4 KB.

**Windows?**
Use WSL or run the script on a macOS/Linux host.

---

## License

[MIT](LICENSE)

---

## Contributing

PRs welcome!

