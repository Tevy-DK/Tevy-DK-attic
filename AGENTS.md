# AGENTS.md

面向未来维护者（包括 AI）的仓库规范。目标：只打包上游 Release 二进制（`chatgpt` 打包 OpenAI 签名 APT 稳定索引中的 Debian 包），保持版本新、构建快、哈希真实、结构可预测。

## 仓库布局

| 路径 | 用途 |
| --- | --- |
| `pkgs/binaries/<name>/default.nix` | 裸二进制、tarball 中的二进制、自解压 portable ELF |
| `pkgs/deb/<name>/default.nix` | Debian 包解包/修补后安装 |
| `pkgs/appimages/<name>/default.nix` | AppImage 包装 |
| `devshell.nix` | 维护工具集合，flake 和 `shell.nix` 共用 |
| `flake.nix` | `packages.${system}`、`overlays.default`、`devShells` |

新增包时按打包策略建目录，不要预建空目录。`flake.nix` 的 `packages` 和 `overlays.default` 必须同时注册新包。

平台固定为 `x86_64-linux` 和 `aarch64-linux`。不支持某平台的包在 `meta.platforms` 中明确限制；能在两个平台构建的包必须给出两套真实哈希。

## 强制规则

### 1. 只认 Release

- 只追踪上游 **最新 Release Tag**，绝不追踪 `main`、`master` 或提交哈希。
- 使用 GitHub Releases API 或 `gh release view <tag>` 获取资产列表，不要猜文件名。
- 版本更新必须同时更新 `version`、资产 URL 模式、每个平台的哈希。
- 上游只发布 x86_64 资产时（如 `etcher`），表达式只保留一个 `hash = "sha256-...";` 行，并用 `meta.platforms` 限制平台；自动更新脚本用 `-` 占位表示缺失的 arm64 资产。
- `chatgpt` 没有 GitHub Release：版本与 deb 路径取自 `https://persistent.oaistatic.com/codex-app-prod/linux/deb` 的 `dists/stable/main/binary-{amd64,arm64}/Packages`，两个架构的 `Version` 必须一致，`Filename` 必须与表达式里的 URL 模板一致。
- `flake.lock` 只固定 nixpkgs；升级 nixpkgs 后重新构建全部包。

发现最新 Release：

```sh
gh release view --repo can1357/oh-my-pi --json tagName,assets
# 或无 gh 时：
curl -fsSL https://api.github.com/repos/can1357/oh-my-pi/releases/latest \
  | jq -r '.tag_name, (.assets[].browser_download_url)'
```

### 2. 哈希必须实测

严禁编造哈希、使用 `lib.fakeHash`、或从网页复制未经校验的值。推荐直接让 Nix 下载并返回 SRI：

```sh
nix store prefetch-file --json <URL> | jq -r .hash
```

需要先检查文件内容时：

```sh
curl -fL -o /tmp/artifact <URL>
sha256sum /tmp/artifact
nix hash convert --hash-algo sha256 --to sri <sha256-hex>
```

更新后必须跑构建。构建失败时不要提交；先修正依赖/哈希/解包逻辑。

### 3. 自给自足的构建环境

进入仓库根目录后：

```sh
nix develop
```

devShell 已提供：`dpkg`、`rpm`、`squashfsTools`、`binutils`、`file`、`patchelf`、`python3`、`gh`、`git`、`nix-prefetch-scripts`、`xz`/`zstd`/`gzip`/`bzip2`、`xvfb`。不要在包表达式里偷偷依赖宿主机命令；构建期需要的工具写进 `nativeBuildInputs`。

### 4. Deb 包处理

优先读取 Deb 自带的控制信息，不要凭经验猜依赖：

```sh
dpkg-deb -f package.deb Package Version Depends Recommends
dpkg-deb -x package.deb /tmp/pkg-root
```

处理流程：

1. 从 `Depends` 中提取共享库/运行时名字，映射到 nixpkgs 属性。
2. 普通链接依赖放 `buildInputs`，并加 `autoPatchelfHook`。
3. 仅通过 `dlopen` 加载、没有 `DT_NEEDED` 的库，放 `runtimeDependencies`，或显式加入 wrapper 的 `LD_LIBRARY_PATH`/`lib.makeLibraryPath`。
4. 非标准安装布局用 `installPhase` 显式复制到 `$out`，不要依赖上游 `Makefile`。
5. 桌面集成（`.desktop`、图标、GSettings schema）用 `makeDesktopItem`、`wrapGAppsHook3`、`gsettings-desktop-schemas` 等 nixpkgs 设施补齐。

如果 Deb 内部还带自解压资源，先确认它的 trailer/布局，再决定是否像 `sjmcl` 一样剥离资源。

### 5. AppImage 兜底

优先：

```nix
appimageTools.wrapType2 {
  pname = "...";
  version = "...";
  src = fetchurl { url = "..."; hash = "..."; };
  extraPkgs = pkgs: [ /* 额外运行时库 */ ];
}
```

如果补依赖超过 5 个仍然运行报错，放弃逐个补库，改用 `buildFHSEnv` 套壳，并在包注释中写明原因和已验证的启动方式。

### 6. 构建验证

每次改动至少执行：

```sh
nix build .#omp --out-link result-omp
./result-omp/bin/omp --version
./result-omp/bin/omp --smoke-test

nix build .#chatgpt --out-link result-chatgpt
xvfb-run -a timeout 30 ./result-chatgpt/bin/chatgpt --version

nix build .#sjmcl --out-link result-sjmcl
xvfb-run -a timeout 15 ./result-sjmcl/bin/SJMCL --version

nix build .#motrix --out-link result-motrix
xvfb-run -a timeout 20 ./result-motrix/bin/motrix --version

nix build .#etcher --out-link result-etcher
xvfb-run -a timeout 20 ./result-etcher/bin/balena-etcher --version
```

GUI 程序会把 `--version` 当作普通参数并打开窗口，`timeout` 返回 124 说明启动成功；其他非零状态才算失败。

同时验证 aarch64 表达式可求值（本机没有 aarch64 builder 时至少做到这一步）：

```sh
nix eval .#packages.aarch64-linux.omp.drvPath
nix eval .#packages.aarch64-linux.chatgpt.drvPath
nix eval .#packages.aarch64-linux.sjmcl.drvPath
nix eval .#packages.aarch64-linux.motrix.drvPath
```

`etcher` 没有 aarch64 Linux 产物，不参与 aarch64 求值；确认 `meta.platforms` 仍为 `[ "x86_64-linux" ]`。

`nix flake check` 可选；它不会替代实际构建和冒烟测试。

### 7. 自动更新

`.github/workflows/auto-update.yml` 每天在 UTC 00:00 和 12:00 各执行一次 `scripts/auto-update.sh`，运行环境为 `nix develop`：

- 通过 GitHub Releases API 获取 `omp`、`sjmcl`、`motrix`、`etcher` 的最新 Tag 和资产 URL，`chatgpt` 则读取 OpenAI 稳定 APT 索引；
- 双平台包（`omp`、`chatgpt`、`sjmcl`、`motrix`）实测两个平台的 SRI 哈希，改写 `default.nix` 中的 `version` 与 `if isAarch64 then ... else ...` 双哈希块；
- `etcher` 只有 amd64 Deb，`update_package` 的 arm64 资产参数传 `-`，脚本改写单个 `hash = "sha256-...";` 行并跳过 aarch64 求值；
- `chatgpt` 由 `update_apt_package` 处理：解析 `Packages` 的 `Version`/`Filename`，实测两个 deb 的 SRI 哈希后改写同一个双哈希块；
- 更新后始终构建 `omp` 和 `chatgpt`，并构建任何其他发生变更的包；任一构建或冒烟测试失败则工作流终止，不提交；
- 全部通过后提交 `chore: auto update binaries [skip ci]` 并推送到 `main`。

脚本依赖 devShell 提供的 `gh`、`curl`、`jq`、`python3`、`git` 和 `nix`，workflow 不额外安装这些工具。表达式的 `version` 行和双哈希块布局是脚本的解析约定；修改布局时必须同步更新脚本。

## 已知包的约束

### omp

- 上游 `omp-linux-musl-*` **不是静态二进制**，动态依赖 musl 版 `libstdc++`/`libgcc`。
- NixOS 是 glibc 环境。通过 `LD_LIBRARY_PATH` 注入 musl `libstdc++` 会污染 omp 派生的 glibc 子进程（实测 `node` 报 `no version information available` 并失败）。
- 因此本包使用 `omp-linux-{x64,arm64}` glibc 资产，并用 `autoPatchelfHook` 修补 interpreter/RPATH。若上游未来发布真正静态的 musl 构建，再切换资产。
- `autoPatchelfIgnoreMissingDeps` 中列出的 `ld-linux-*` 是 ELF interpreter，不是普通共享库。
- omp 首次使用时会把本地推理运行时（`fastembed` + 预编译 `onnxruntime-node`/`tokenizers`）安装到 `~/.omp/cache`，这些 `.node`/`.so` 由 `dlopen` 加载、自带 `DT_RUNPATH`，依赖 glibc 版 `libstdc++.so.6`/`libgcc_s.so.1`。它们构建期不存在，`autoPatchelfHook` 无法修补，可执行文件自身的 RPATH 也不会用于解析 addon 的依赖。因此 launch wrapper 设置 `--set-default OMP_NATIVE_LIBRARY_PATH`（`stdenv.cc.cc.lib` + `libgcc`）：omp 只把这个值追加到推理 worker 子进程的 `LD_LIBRARY_PATH`，不会污染 bash/eval/daemon 派生的子进程。不要改成全局导出 `LD_LIBRARY_PATH`，更不要注入 musl 版 `libstdc++`。

### chatgpt

- 上游没有 GitHub Release，只通过 `https://persistent.oaistatic.com/codex-app-prod/linux/deb` 发布签名 APT 包 `chatgpt_<version>_{amd64,arm64}.deb`；版本号取自 `dists/stable` 的 `Packages` 索引。
- 这是约 563 MB 的 Electron 包，安装后约 1.8 GB。`usr/bin/chatgpt` 指向 `usr/lib/chatgpt/codex-launcher`，真正的 ELF 名为 `ChatGPT`。
- `autoPatchelfHook` 会把 `PT_INTERP` 移出 `detect-libc` 读取的前 2 KiB，Electron 退到 `process.report` 后崩溃；必须解包 `resources/app.asar`，把 `node_modules/@parcel/watcher/index.js` 里的 `const family = familySync();` 固定为 glibc，再用 `asar pack --unpack-dir` 按原有 unpacked 目录重新打包。
- `resources/app.asar.unpacked/**/prebuilds` 带 darwin/win32/android/musl 全套产物；必须在 `autoPatchelfHook` 之前只保留 `*linux-x64`（aarch64 为 `*linux-arm64`），否则异构 ELF 会被改写。
- Electron 运行时会改写 `resources/plugins` 里的插件清单，因此 launcher 把该目录复制到 `$XDG_CACHE_HOME/chatgpt/bundled-plugins-v2/<store 名>`，其余资源软链到 store，并设置 `CODEX_ELECTRON_BUNDLED_PLUGINS_RESOURCES_PATH`。
- `resources/codex`、`resources/rg` 是 static-pie，`resources/tectonic/tectonic` 是静态链接：这些不需要修补；`resources/cua_node/bin/node` 是动态 ELF，会被正常 patchelf。
- `libqt6_shim.so` 是 Qt 6 输入法 shim，保留并让 `qt6.qtbase` 进入 `buildInputs`；`libqt5_shim.so` 无用，安装时删除。
- 包是专有软件（`meta.license = lib.licenses.unfree`）；flake 自己的 `packages` 用 `config.allowUnfree = true` 导入 nixpkgs，overlay 使用者需自行开启。
- 冒烟测试：`xvfb-run -a timeout 30 ./result-chatgpt/bin/chatgpt --version`；首次启动要把 29 MB 插件复制进缓存，比其它 GUI 包慢。

### sjmcl

- 上游 portable 文件 = ELF + 追加 ZIP + 12 字节 `PORT` trailer。安装时必须：
  1. 按 trailer 的 `elf_size`/`zip_size` 拆出 ELF 和资源 ZIP；
  2. 资源解压到 `$out/lib/SJMCL`；
  3. 只安装去掉 trailer 的 ELF，禁用 portable 模式；
  4. 用 `patchelf` 设置 interpreter 和 RPATH。
- 不要对完整 portable 文件直接 `patchelf`，会破坏追加数据。
- aarch64 使用 `ld-linux-aarch64.so.1`，x86_64 使用 `ld-linux-x86-64.so.2`。
- launcher 和游戏 JVM 是两套运行时：launcher 需要 Tauri/GTK/WebKit 库；游戏需要 JDK、OpenGL/Vulkan/声音库。两者都要在 wrapper 中考虑。

### motrix

- 上游同时发布 x86_64 与 arm64 AppImage，但文件名后缀不同：`Motrix-<version>-x86_64.AppImage` / `Motrix-<version>-arm64.AppImage`。更新时用 Releases API 确认，不要套用 1.x 的 `Motrix-<version>.AppImage` 命名。
- 用 `appimageTools.wrapType2` 提供 FHS 运行时；desktop 文件与图标直接从 AppImage 内容安装，并把 `Exec=AppRun` 改成 `Exec=motrix`，否则启动器找不到命令。
- 生成的 wrapper 通过 `bubblewrap` 创建 FHS 沙箱，需要非特权 user namespace。Ubuntu 24.04+ 用 AppArmor 限制了它（`kernel.apparmor_restrict_unprivileged_userns=1`），冒烟测试会直接死在 `bwrap: setting up uid map: Permission denied`；CI 因此先关掉该限制再构建。
- 2.x 是上游重写版（Electron 45），与 nixpkgs 中的 1.8.19 表达式不是同一套资产布局。

### etcher

- 上游只有 `balena-etcher_<version>_amd64.deb`，没有 arm64 Linux 资产；`meta.platforms` 必须限制为 `x86_64-linux`。
- Deb 的 `chrome-sandbox` 是 setuid root helper。Nix store 不能保留 setuid，而保留一个不可用的 helper 会让 Chromium 直接退出，所以安装时删除该文件，让 Electron 使用非特权 user namespace 沙箱；不要加 `--no-sandbox`。
- `dpkg-deb --extract` 会尝试恢复 `chrome-sandbox` 的 setuid 位并在沙箱中失败；解包用 `dpkg-deb --fsys-tarfile "$src" | tar -x --no-same-owner --no-same-permissions`。
- Electron 通过 `dlopen` 加载 `libEGL.so.1`，不会走可执行文件的 RUNPATH；wrapper 必须把 `libglvnd` 和 `${addDriverRunpath.driverLink}/lib` 加进 `LD_LIBRARY_PATH`，否则 GPU 进程报 `Could not dlopen native EGL`。
- `resources/etcher-util` 是 `pkg` 打包的 Node 程序，payload 追加在 ELF 末尾并记录绝对偏移。Nix 的 strip 会重写 ELF、丢掉 payload，导致 sidecar 以 `Pkg: Error reading from file.` 启动失败（GUI 报 `Failed to start the flasher sidecar process`）。必须 `stripExclude = [ "etcher-util" ];`。
- sidecar 从 payload 里 `dlopen` 原生模块（`lzma-native`、`libext2fs`、`drivelist`），依赖对 `autoPatchelfHook` 不可见。设 `dontAutoPatchelf = true;`，在 `postFixup` 手动调用 `autoPatchelf "$out"`，再用 `patchelf --force-rpath --set-rpath` 给 `etcher-util` 加上 glibc/libstdc++/libgcc/udev；必须用 `DT_RPATH`（`--force-rpath`），因为 `dlopen` 不查 `DT_RUNPATH`。
- 渲染层 bundle 硬编码 `/usr/bin/pkexec` 和 `/bin/bash`，NixOS 上都不存在。安装时用 `asar` 解包、替换为 `/run/wrappers/bin/pkexec`（setuid 的 NixOS wrapper）和 `${bash}/bin/bash`，再重新打包；不要依赖 PATH 里的 `pkexec`（polkit 包里的 `pkexec` 不是 setuid）。

## 提交前检查清单

- [ ] 版本来自最新 Release Tag，不是 `main`。
- [ ] 每个平台的哈希都从真实资产测得。
- [ ] `nix build` 通过，并实际运行了包的 `--version`/冒烟命令。
- [ ] aarch64 表达式求值通过（或已在 aarch64 机器上构建）。
- [ ] `meta.platforms`、`mainProgram`、`license`、`sourceProvenance` 正确。
- [ ] GitHub Actions 仅用于 Release 自动更新/构建验证，不引入源码构建 CI。
- [ ] 没有提交 `result*` 链接、临时下载文件或 `lib.fakeHash`。

## 风格

- 包文件使用 `stdenv.mkDerivation (finalAttrs: { ... })`，`version` 只写一次。
- 平台分支集中在文件顶部 `let` 中，URL/哈希/interpreter 一起映射，避免在构建阶段散落 `if`。
- 注释只解释上游产物的真实布局、为何做某个修补、以及不明显的运行时依赖；不要复述 Nix 语法。
- 保持 `nixfmt` 格式：`nix fmt .`。
