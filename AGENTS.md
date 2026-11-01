# AGENTS.md

面向未来维护者（包括 AI）的仓库规范。目标：只打包上游 Release 二进制，保持版本新、构建快、哈希真实、结构可预测。

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

nix build .#codex --out-link result-codex
./result-codex/bin/codex --version

nix build .#sjmcl --out-link result-sjmcl
xvfb-run -a timeout 15 ./result-sjmcl/bin/SJMCL --version
```

同时验证 aarch64 表达式可求值（本机没有 aarch64 builder 时至少做到这一步）：

```sh
nix eval .#packages.aarch64-linux.omp.drvPath
nix eval .#packages.aarch64-linux.codex.drvPath
nix eval .#packages.aarch64-linux.sjmcl.drvPath
```

`nix flake check` 可选；它不会替代实际构建和冒烟测试。

### 7. 自动更新

`.github/workflows/auto-update.yml` 每天在 UTC 00:00 和 12:00 各执行一次 `scripts/auto-update.sh`，运行环境为 `nix develop`：

- 通过 GitHub Releases API 获取 `omp`、`codex`、`sjmcl`、`command-code` 的最新 Tag 和资产 URL；
- 双平台包（`omp`、`codex`、`sjmcl`）实测两个平台的 SRI 哈希，改写 `default.nix` 中的 `version` 与 `if isAarch64 then ... else ...` 双哈希块；
- 单平台包（`command-code`）实测 `.deb` 的 SRI 哈希，改写 `version` 与单一 `hash = "...";` 行；x86_64-only 包跳过 aarch64 求值；
- 更新后始终构建 `omp` 和 `codex`，并构建任何其他发生变更的包（含 `command-code` 的 Xvfb 启动冒烟测试）；任一构建或冒烟测试失败则工作流终止，不提交；
- 全部通过后提交 `chore: auto update binaries [skip ci]` 并推送到 `main`。

脚本依赖 devShell 提供的 `gh`、`curl`、`jq`、`python3`、`git` 和 `nix`，workflow 不额外安装这些工具。表达式的 `version` 行和双哈希块布局是脚本的解析约定；修改布局时必须同步更新脚本。

## 已知包的约束

### command-code

- 上游只发布 `CommandCode-<version>-amd64.deb`，没有 Linux arm64 资产，`meta.platforms` 固定为 `x86_64-linux`。
- Electron 应用：`dpkg-deb -x` 解包，`autoPatchelfHook` 修补随包的 ELF，`wrapGAppsHook3` 处理 GTK/GSettings/XDG 数据目录。
- `.deb` 内包含所有平台的原生模块（`@lydell/node-pty-*`、`@parcel/watcher-*`、`@crosscopy/clipboard-*`）。`installPhase` 只保留 glibc x86_64 版本；其他架构的 ELF 会让 `autoPatchelfHook` 失败，其余平台文件是死重量。
- 运行依赖 `libsecret`、`libnotify`、`libappindicator-gtk3`、`libXScrnSaver`、`libXtst`、`libdrm`、`libGL`、`vulkan-loader` 等，其中多数是 `dlopen`，不在 `DT_NEEDED` 里，必须放进 wrapper 的 `LD_LIBRARY_PATH`。
- Chromium sandbox 依赖 NixOS 默认启用的 user namespaces；不要加 `--no-sandbox`。包装器只追加 `--ozone-platform-hint=auto`，让 niri/Wayland 走原生 Wayland。
- 自动更新脚本用 `update_single_package` 处理这个单平台、单哈希的包；升级时同时更新 `version`、deb URL 和哈希。
- CI 冒烟测试用 Xvfb + `--no-sandbox --disable-gpu` 启动；`--no-sandbox` 仅用于 GitHub runner 受限的 user namespaces，不进入安装后的 wrapper。

### omp

- 上游 `omp-linux-musl-*` **不是静态二进制**，动态依赖 musl 版 `libstdc++`/`libgcc`。
- NixOS 是 glibc 环境。通过 `LD_LIBRARY_PATH` 注入 musl `libstdc++` 会污染 omp 派生的 glibc 子进程（实测 `node` 报 `no version information available` 并失败）。
- 因此本包使用 `omp-linux-{x64,arm64}` glibc 资产，并用 `autoPatchelfHook` 修补 interpreter/RPATH。若上游未来发布真正静态的 musl 构建，再切换资产。
- `autoPatchelfIgnoreMissingDeps` 中列出的 `ld-linux-*` 是 ELF interpreter，不是普通共享库。

### codex

- 上游 `codex-*-unknown-linux-musl.tar.gz` 是 static-pie，已 stripped。
- 不要给 codex 加 `autoPatchelfHook`，也不要 strip；tarball 根目录就是二进制，安装时重命名为 `codex`。

### sjmcl

- 上游 portable 文件 = ELF + 追加 ZIP + 12 字节 `PORT` trailer。安装时必须：
  1. 按 trailer 的 `elf_size`/`zip_size` 拆出 ELF 和资源 ZIP；
  2. 资源解压到 `$out/lib/SJMCL`；
  3. 只安装去掉 trailer 的 ELF，禁用 portable 模式；
  4. 用 `patchelf` 设置 interpreter 和 RPATH。
- 不要对完整 portable 文件直接 `patchelf`，会破坏追加数据。
- aarch64 使用 `ld-linux-aarch64.so.1`，x86_64 使用 `ld-linux-x86-64.so.2`。
- launcher 和游戏 JVM 是两套运行时：launcher 需要 Tauri/GTK/WebKit 库；游戏需要 JDK、OpenGL/Vulkan/声音库。两者都要在 wrapper 中考虑。

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
