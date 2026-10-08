#!/bin/bash
# Build de Dictee : whisper.cpp (Metal) + app Swift barre de menus + CLI + tests.
# Usage : ./build.sh [test|cli|app|all]   (défaut : all)
set -euo pipefail
cd "$(dirname "$0")"
TARGET="${1:-all}"

W=vendor/whisper.cpp
mkdir -p build

# ---- 0. cmake : celui du système, sinon celui du venv, sinon on l'installe dans un venv local
find_cmake() {
  if command -v cmake >/dev/null 2>&1; then echo "cmake"; return; fi
  if [ -x .venv-build/bin/cmake ]; then echo "$PWD/.venv-build/bin/cmake"; return; fi
  if [ -x .venv/bin/cmake ]; then echo "$PWD/.venv/bin/cmake"; return; fi
  echo ">> cmake absent : installation locale (pip, dans .venv-build)" >&2
  /usr/bin/python3 -m venv .venv-build >&2
  .venv-build/bin/pip install -q cmake >&2
  echo "$PWD/.venv-build/bin/cmake"
}

# ---- 1. whisper.cpp (cloné si absent, compilé une seule fois)
if [ ! -d "$W" ]; then
  echo ">> Clonage de whisper.cpp (GitHub officiel ggml-org)"
  git clone --depth 1 https://github.com/ggml-org/whisper.cpp.git "$W"
  if ls patches/*.patch >/dev/null 2>&1; then
    echo ">> Application des patchs locaux"
    (cd "$W" && for p in ../../patches/*.patch; do git apply "$p"; done)
  fi
fi
if [ ! -f "$W/build/src/libwhisper.a" ]; then
  echo ">> Compilation de whisper.cpp (Metal)"
  CMAKE=$(find_cmake)
  "$CMAKE" -S "$W" -B "$W/build" -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON \
    -DBUILD_SHARED_LIBS=OFF -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_EXAMPLES=OFF \
    -DCMAKE_BUILD_TYPE=Release > build/cmake-configure.log
  "$CMAKE" --build "$W/build" --config Release -j"$(sysctl -n hw.ncpu)" --target whisper > build/cmake-build.log
fi

LIBS="$W/build/src/libwhisper.a $W/build/ggml/src/libggml.a $W/build/ggml/src/libggml-base.a \
$W/build/ggml/src/libggml-cpu.a $W/build/ggml/src/ggml-metal/libggml-metal.a $W/build/ggml/src/ggml-blas/libggml-blas.a"
FRAMEWORKS="-framework Foundation -framework AVFoundation -framework Metal -framework MetalKit \
-framework Accelerate -framework CoreAudio -lc++"
INCLUDES="-I Sources/CWhisper -Xcc -I$W/include -Xcc -I$W/ggml/include"

# ---- 2. tests unitaires (sans whisper : texte pur)
if [ "$TARGET" = "test" ] || [ "$TARGET" = "all" ]; then
  echo ">> Tests unitaires"
  swiftc -O Sources/Core/Paths.swift Sources/Core/Log.swift Sources/Core/Config.swift \
    Sources/Core/TextUtil.swift Sources/Core/Dictionary.swift Sources/Core/Cleaner.swift \
    Sources/Core/Learner.swift Sources/Tests/main.swift -o build/dictee-tests
  ./build/dictee-tests
fi

# ---- 3. CLI de test (transcription de fichiers)
if [ "$TARGET" = "cli" ] || [ "$TARGET" = "all" ]; then
  echo ">> CLI (build/dictee-cli)"
  # shellcheck disable=SC2086
  swiftc -O $INCLUDES Sources/Core/*.swift Sources/CLI/main.swift $LIBS $FRAMEWORKS -o build/dictee-cli
fi

# ---- 4. app barre de menus (.app signée ad hoc)
if [ "$TARGET" = "app" ] || [ "$TARGET" = "all" ]; then
  echo ">> App (build/Dictee.app)"
  APP=build/Dictee.app
  rm -rf "$APP"
  mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/defaults"
  # shellcheck disable=SC2086
  swiftc -O -parse-as-library $INCLUDES Sources/Core/*.swift Sources/App/*.swift \
    $LIBS $FRAMEWORKS -framework ApplicationServices \
    -o "$APP/Contents/MacOS/Dictee"
  cp app/Info.plist "$APP/Contents/Info.plist"
  cp defaults/*.json "$APP/Contents/Resources/defaults/"
  xattr -cr "$APP"
  codesign -s - --force --deep "$APP"
  echo ">> OK : $APP (signée ad hoc)"
fi
echo ">> Build terminé"
