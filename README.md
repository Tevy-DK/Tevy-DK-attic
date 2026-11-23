# Tevy-DK-attic

个人 Nix 软件源。核心原则：**不自行编译源码，只打包上游 Release 的预编译产物**。目标是极简、构建快、版本新，并且更新流程可重复。

## 包

| 属性 | 版本 | 上游 | 产物 | 平台 |
| --- | --- | --- | --- | --- |
| `omp` | 18.17.0 | [can1357/oh-my-pi](https://github.com/can1357/oh-my-pi) | `omp-linux-{x64,arm64}` | `x86_64-linux`, `aarch64-linux` |
| `chatgpt` | 26.1106.51428 | [OpenAI APT 仓库](https://persistent.oaistatic.com/codex-app-prod/linux/deb) | `chatgpt_26.1106.51428_{amd64,arm64}.deb` | `x86_64-linux`, `aarch64-linux` |
| `sjmcl` | 1.4.0 | [UNIkeEN/SJMCL](https://github.com/UNIkeEN/SJMCL) | `SJMCL_1.4.0_linux_{x86_64,aarch64}_portable` | `x86_64-linux`, `aarch64-linux` |
| `motrix` | 2.3.0 | [agalwood/Motrix](https://github.com/agalwood/Motrix) | `Motrix-2.3.0-{x86_64,arm64}.AppImage` | `x86_64-linux`, `aarch64-linux` |
| `etcher` | 2.1.9 | [balena-io/etcher](https://github.com/balena-io/etcher) | `balena-etcher_2.1.9_amd64.deb` | `x86_64-linux` |
| `antigravity` | 2.33.0 | [antigravity.google](https://antigravity.google/download) | `Antigravity.tar.gz`（`linux-{x64,arm}`） | `x86_64-linux`, `aarch64-linux` |
| `pi` | 1.6.0 | [earendil-works/pi](https://github.com/earendil-works/pi) | `pi-linux-{arm64,x64}.tar.gz` + FHS | `x86_64-linux`, `aarch64-linux` |

`omp` 说明：上游的 `omp-linux-musl-*` 并非静态二进制，而是动态链接 musl 版 `libstdc++`/`libgcc`。在 NixOS（glibc 环境）上给进程注入 musl `libstdc++` 会破坏 omp 派生的 glibc 子进程，因此本仓库使用同一版本的 `omp-linux-*` glibc 资产。omp 首次使用时会把本地嵌入运行时（`fastembed` + 预编译 `onnxruntime-node`）安装到 `~/.omp/cache`，这些库由 `dlopen` 加载并需要 glibc 版 `libstdc++.so.6`；构建期无从修补，所以 launch wrapper 通过 `OMP_NATIVE_LIBRARY_PATH` 声明 `stdenv.cc.cc.lib`/`libgcc` 路径（omp 只把它注入推理 worker 子进程的 `LD_LIBRARY_PATH`），避免 `bge-base-en-v1.5 failed: libstdc++.so.6` 启动错误。

`chatgpt` 是 OpenAI 官方的 ChatGPT 桌面版（Electron），直接打包其签名 APT 仓库里的 Debian 包；上游没有 GitHub Release，因此版本号取自 `dists/stable` 索引。NixOS 上的修补参考 nixpkgs 的表达式和 [ilysenko/codex-desktop-linux](https://github.com/ilysenko/codex-desktop-linux) 的 Nix 说明：`autoPatchelfHook` 会让 `detect-libc` 读不到 `PT_INTERP`，所以把 `app.asar` 里的判断固定为 glibc 后重新打包；只保留本机构架的 `prebuilds`；Electron 运行时会改写自带的插件清单，launcher 把 `resources/plugins` 复制到 `~/.cache` 再通过 `CODEX_ELECTRON_BUNDLED_PLUGINS_RESOURCES_PATH` 指过去。该包是专有软件（`lib.licenses.unfree`），overlay 使用者需要自行开启 `allowUnfree`。

`antigravity` 是 Google 的 agent 桌面应用，直接打包官方 `Antigravity.tar.gz`。上游没有 GitHub Release，版本与构建号取自其自动更新 manifest；tarball 不带 desktop 文件与图标，包内从 `app.asar` 提取图标并生成 desktop entry。tarball 中的 `chrome-sandbox` 在 Debian 包里是 setuid helper，Nix store 无法保留该权限，因此安装时删除，让 Electron 使用非特权 user namespace 沙箱；应用自带的 updater 在非 AppImage 安装下会记录 `APPIMAGE env is not defined`，不会自行替换安装目录；升级由本仓库负责。

`motrix` 使用上游双平台 AppImage，由 `appimageTools.wrapType2` 提供 FHS 运行时，并安装 AppImage 自带的 desktop 文件与图标。`etcher` 上游只发布 amd64 Debian 包，没有 arm64 Linux 产物，因此 `meta.platforms` 仅保留 `x86_64-linux`。Deb 的 `chrome-sandbox` 需要 setuid，而 Nix store 无法保留该权限：包内删除该 helper，Electron 改用非特权 user namespace 沙箱（不传 `--no-sandbox`）。

`pi` 直接打包上游 Release 的 `pi-linux-{arm64,x64}.tar.gz`，外面套 `buildFHSEnv`，因此启动命令仍是 `pi`。tarball 里的 Bun 单文件可执行程序把资源放在同级目录，launcher 通过 `PI_PACKAGE_DIR` 固定这个目录。pi 的插件常把 `/bin/bash`、`/usr/bin/python3`、`/usr/bin/node` 之类的绝对路径写死；FHS 根目录让这些路径在 NixOS 上存在。`targetPkgs` 额外放了一大批常用运行时和 CLI（Node、Bun、Deno、Python、uv、Go、Rust、git、ripgrep、fd、jq、curl、构建工具链等），作为不受控插件的运行表面。插件由 pi 自己在运行时安装，这里不做声明式插件配置。版本由 `.github/workflows/auto-update.yml` 跟随上游 Release 自动更新。

## 使用

### 直接构建 / 运行

```sh
nix build github:Tevy-DK/Tevy-DK-attic#omp
nix build github:Tevy-DK/Tevy-DK-attic#chatgpt
nix build github:Tevy-DK/Tevy-DK-attic#sjmcl
nix build github:Tevy-DK/Tevy-DK-attic#motrix
nix build github:Tevy-DK/Tevy-DK-attic#etcher
nix build github:Tevy-DK/Tevy-DK-attic#antigravity
nix build github:Tevy-DK/Tevy-DK-attic#pi

nix shell github:Tevy-DK/Tevy-DK-attic#omp -c omp --version
nix shell github:Tevy-DK/Tevy-DK-attic#chatgpt -c chatgpt
nix shell github:Tevy-DK/Tevy-DK-attic#sjmcl -c SJMCL
nix shell github:Tevy-DK/Tevy-DK-attic#motrix -c motrix
nix shell github:Tevy-DK/Tevy-DK-attic#etcher -c balena-etcher
nix shell github:Tevy-DK/Tevy-DK-attic#antigravity -c antigravity
nix shell github:Tevy-DK/Tevy-DK-attic#pi -c pi --version
```

本地开发时用短属性：

```sh
nix build .#omp --out-link result-omp
nix build .#chatgpt --out-link result-chatgpt
nix build .#sjmcl --out-link result-sjmcl
nix build .#motrix --out-link result-motrix
nix build .#etcher --out-link result-etcher
nix build .#antigravity --out-link result-antigravity
nix build .#pi --out-link result-pi
```

### Flake + overlay

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    attic.url = "github:Tevy-DK/Tevy-DK-attic";
    attic.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, attic, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ({ pkgs, ... }: {
          nixpkgs.overlays = [ attic.overlays.default ];
          environment.systemPackages = with pkgs; [ omp pi chatgpt sjmcl motrix etcher antigravity ];
        })
      ];
    };
  };
}
```

也可以直接引用包而不使用 overlay：

```nix
environment.systemPackages = [
  attic.packages.x86_64-linux.omp
  attic.packages.x86_64-linux.pi
  attic.packages.x86_64-linux.chatgpt
  attic.packages.x86_64-linux.sjmcl
  attic.packages.x86_64-linux.motrix
  attic.packages.x86_64-linux.etcher
  attic.packages.x86_64-linux.antigravity
];
```

## 开发环境

仓库自带 devShell，包含 `dpkg`、`gh`、`nix-prefetch-url`、`patchelf`、`binutils`、`xvfb` 等维护工具：

```sh
nix develop
# 或使用传统 shell.nix
nix-shell
```

## 目录结构

```text
.
├── .github/workflows/auto-update.yml
├── flake.nix
├── devshell.nix
├── shell.nix
├── AGENTS.md
├── scripts/
│   └── auto-update.sh
└── pkgs/
    ├── appimages/
    │   └── motrix/default.nix
    ├── binaries/
    │   ├── antigravity/default.nix
    │   ├── omp/default.nix
    │   └── sjmcl/default.nix
    ├── deb/
    │   ├── chatgpt/default.nix
    │   └── etcher/default.nix
    └── fhs/
        └── pi/default.nix
```

目录按打包策略划分。未来新增 Deb 包放 `pkgs/deb/<name>/`，AppImage 放 `pkgs/appimages/`，FHS 包装放 `pkgs/fhs/`；只有实际存在包时才创建目录。具体维护规范见 [AGENTS.md](./AGENTS.md)。

## 维护

只跟随上游最新 Release Tag（`chatgpt` 例外：版本来自 OpenAI 的稳定 APT 索引；`antigravity` 例外：版本与构建号来自其 updater manifest），不跟随 `main`。版本与哈希必须来自真实产物，更新后跑 `nix build` 验证。完整流程、Deb/AppImage 处理规则和验证命令写在 [AGENTS.md](./AGENTS.md)。

`.github/workflows/auto-update.yml` 每天在 UTC 00:00 和 12:00 各运行一次自动更新：获取 `omp`、`pi`、`chatgpt`、`sjmcl`、`motrix`、`etcher`、`antigravity` 的最新版本，实测可用平台的哈希并改写版本号（`etcher` 只有 amd64 资产，脚本按单哈希处理；`chatgpt` 读取 APT 索引并实测两个 deb 的哈希；`antigravity` 读取其 updater manifest 并实测两个 Linux tarball 的哈希；`pi` 的 Linux 资产名只含架构）。构建验证通过后以 `chore: auto update binaries [skip ci]` 提交并推送到 `main`。验证失败时工作流终止，不提交任何内容。本地可手动执行：

```sh
nix develop --command bash scripts/auto-update.sh
```

只有加 `--commit` 才会提交并推送。
