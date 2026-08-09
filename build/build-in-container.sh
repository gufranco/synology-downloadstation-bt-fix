#!/usr/bin/env bash
set -euo pipefail

TRANSMISSION_VERSION="${TRANSMISSION_VERSION:?}"
BUILD_JOBS="${BUILD_JOBS:-1}"
export DEBIAN_FRONTEND=noninteractive

mkdir -p /out

apt-get update -qq
apt-get install -y -qq --no-install-recommends \
  build-essential cmake pkg-config ca-certificates curl xz-utils python3 \
  libcurl4-openssl-dev libssl-dev libevent-dev zlib1g-dev libdeflate-dev libpsl-dev \
  >/dev/null

cd /tmp
curl -fsSL -o transmission.tar.xz \
  "https://github.com/transmission/transmission/releases/download/${TRANSMISSION_VERSION}/transmission-${TRANSMISSION_VERSION}.tar.xz"
tar xf transmission.tar.xz
cd "transmission-${TRANSMISSION_VERSION}"

if [ -d /patches ] && compgen -G "/patches/*.patch" > /dev/null; then
  for patch_file in /patches/*.patch; do
    printf 'applying %s\n' "$patch_file"
    patch -p1 < "$patch_file"
  done
fi

cmake -S . -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DENABLE_DAEMON=ON \
  -DENABLE_CLI=OFF \
  -DENABLE_GTK=OFF \
  -DENABLE_QT=OFF \
  -DENABLE_MAC=OFF \
  -DENABLE_TESTS=OFF \
  -DENABLE_UTILS=OFF \
  -DENABLE_WEB=OFF \
  -DREBUILD_WEB=OFF \
  -DINSTALL_DOC=OFF \
  -DRUN_CLANG_TIDY=OFF \
  -DUSE_SYSTEM_EVENT2=OFF \
  -DUSE_SYSTEM_DEFLATE=OFF \
  -DUSE_SYSTEM_PSL=OFF \
  -DUSE_SYSTEM_B64=OFF \
  -DUSE_SYSTEM_DHT=OFF \
  -DUSE_SYSTEM_UTP=OFF \
  -DUSE_SYSTEM_NATPMP=OFF \
  -DUSE_SYSTEM_MINIUPNPC=OFF \
  -DCMAKE_C_FLAGS="-g0" \
  -DCMAKE_CXX_FLAGS="-g0" \
  -DCMAKE_EXE_LINKER_FLAGS="-static-libstdc++ -static-libgcc"

cmake --build build --target transmission-daemon -j "$BUILD_JOBS"

find build -name transmission-daemon -type f -exec cp -f {} /out/transmission-daemon \;
strip /out/transmission-daemon

/out/transmission-daemon --version
ldd /out/transmission-daemon
