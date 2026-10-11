#!/bin/bash
# 核显机 mpv 诊断版一键构建链(2026-10-07)
set -x
cd ~/mpv-winbuild-cmake

# 对齐 CI 版本与 cmake 4 兼容(2026-10-11): Ubuntu 26.04 的 meson 1.10.1 与
# cmake 4.2 对旧式包(minimum_required<3.5)存在兼容问题——CI(run29)为 1.12.1。
if ! meson --version 2>/dev/null | grep -q "1.12"; then
  pip3 install --break-system-packages -q meson==1.12.1 2>&1 | tail -1
  hash -r
fi
export CMAKE_POLICY_VERSION_MINIMUM=3.5

# 0) configure(CI workflow 同款参数)
if [[ ! -f build_x86_64_v3/CMakeCache.txt ]]; then
  cmake -DTARGET_ARCH=x86_64-w64-mingw32 -DGCC_ARCH=x86-64-v3 \
    -DSINGLE_SOURCE_LOCATION=$PWD/src_packages \
    -DRUSTUP_LOCATION=$PWD/clang_root/install_rustup \
    -DENABLE_CCACHE=ON \
    -DMPV_REPO=https://github.com/HumanMus1c/mpv.git \
    -DMPV_REF=fix/log-file-lost-wakeup \
    --fresh -G Ninja -B build_x86_64_v3 -S $PWD
fi

# 1) 源码下载(全部依赖+mpv)
ninja -C build_x86_64_v3 download || true

# 2) 工具链自举(已存在则跳过)
if [[ ! -f build_x86_64_v3/install/bin/cross-gcc ]]; then
  ninja -C build_x86_64_v3 gcc
fi

# 3) mpv 全量(依赖+mpv 本体)
ninja -C build_x86_64_v3 update || true
ninja -C build_x86_64_v3 mpv

echo "BUILD_DONE rc=$?"
ls -la build_x86_64_v3/packages/mpv-prefix/src/mpv-build/libmpv-2.dll 2>/dev/null
ls -la build_x86_64_v3/packages/mpv-prefix/src/mpv-build/mpv.exe 2>/dev/null
