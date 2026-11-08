# Tevy-DK-attic

个人 Nix 软件源。核心原则：**不编译源码，只打包上游 Release 的预编译产物**。目标是极简、构建快、版本新，并且更新流程可重复。

## 包

| 属性 | 版本 | 上游 | 产物 | 平台 |
| --- | --- | --- | --- | --- |
| `omp` | 18.17.0 | [can1357/oh-my-pi](https://github.com/can1357/oh-my-pi) | `omp-linux-{x64,arm64}` | `x86_64-linux`, `aarch64-linux` |
| `codex` | 0.167.0 | [openai/codex](https://github.com/openai/codex) | `codex-{x86_64,aarch64}-unknown-linux-musl.tar.gz` | `x86_64-linux`, `aarch64-linux` |
| `sjmcl` | 1.4.0 | [UNIkeEN/SJMCL](https://github.com/UNIkeEN/SJMCL) | `SJMCL_1.4.0_linux_{x86_64,aarch64}_portable` | `x86_64-linux`, `aarch64-linux` |
| `motrix` | 2.3.0 | [agalwood/Motrix](https://github.com/agalwood/Motrix) | `Motrix-2.3.0-{x86_64,arm64}.AppImage` | `x86_64-linux`, `aarch64-linux` |
| `etcher` | 2.1.9 | [balena-io/etcher](https://github.com/balena-io/etcher) | `balena-etcher_2.1.9_amd64.deb` | `x86_64-linux` |
| `dsh-desktop` | `2.0.22-next-unstable-2026-11-06` | [anywhere-labs/dsh-desktop](https://github.com/anywhere-labs/dsh-desktop)（由 [deepseek-harness.nix](https://github.com/moraxyc/deepseek-harness.nix) 构建） | 源码构建：nixpkgs Electron 外壳 + 共享 `dsh` runtime | `x86_64-linux`, `aarch64-linux` |

`omp` 说明：上游的 `omp-linux-musl-*` 并非静态二进制，而是动态链接 musl 版 `libstdc++`/`libgcc`。在 NixOS（glibc 环境）上给进程注入 musl `libstdc++` 会破坏 omp 派生的 glibc 子进程，因此本仓库使用同一版本的 `omp-linux-*` glibc 资产。omp 首次使用时会把本地嵌入运行时（`fastembed` + 预编译 `onnxruntime-node`）安装到 `~/.omp/cache`，这些库由 `dlopen` 加载并需要 glibc 版 `libstdc++.so.6`；构建期无从修补，所以 launch wrapper 通过 `OMP_NATIVE_LIBRARY_PATH` 声明 `stdenv.cc.cc.lib`/`libgcc` 路径（omp 只把它注入推理 worker 子进程的 `LD_LIBRARY_PATH`），避免 `bge-base-en-v1.5 failed: libstdc++.so.6` 启动错误。`codex` 的 musl 资产是真正的 static-pie，直接安装。

`motrix` 使用上游双平台 AppImage，由 `appimageTools.wrapType2` 提供 FHS 运行时，并安装 AppImage 自带的 desktop 文件与图标。`etcher` 上游只发布 amd64 Debian 包，没有 arm64 Linux 产物，因此 `meta.platforms` 仅保留 `x86_64-linux`。Deb 的 `chrome-sandbox` 需要 setuid，而 Nix store 无法保留该权限：包内删除该 helper，Electron 改用非特权 user namespace 沙箱（不传 `--no-sandbox`）。

`dsh-desktop` 是唯一不打包 Release 产物的条目：上游只发布自解压 Electron 包（内含需要 setuid 的 `chrome-sandbox`），直接安装无法在 NixOS 上工作。本仓库转发 [moraxyc/deepseek-harness.nix](https://github.com/moraxyc/deepseek-harness.nix) 的 `dsh-desktop-unofficial`——它用 nixpkgs Electron 重建外壳，并把 `resources/host` 指向共享 `dsh` runtime。首次构建建议启用其 Cachix 缓存，否则会在本地编译 Electron 外壳与 dsh runtime：

```sh
nix build .#dsh-desktop --out-link result-dsh-desktop \
  --extra-substituters https://deepseek-harness-nix.cachix.org \
  --extra-trusted-public-keys 'deepseek-harness-nix.cachix.org-1:5NrkwLN9veNMhiINtU5ZeV4isXFhFsOwn6Ms7J1M+TA='
```

升级不经过本仓库的 `scripts/auto-update.sh`，而是 `nix flake update deepseek-harness` 后重新提交 `flake.lock`。

## 使用

### 直接构建 / 运行

```sh
nix build github:Tevy-DK/Tevy-DK-attic#omp
nix build github:Tevy-DK/Tevy-DK-attic#codex
nix build github:Tevy-DK/Tevy-DK-attic#sjmcl
nix build github:Tevy-DK/Tevy-DK-attic#motrix
nix build github:Tevy-DK/Tevy-DK-attic#etcher
nix build github:Tevy-DK/Tevy-DK-attic#dsh-desktop

nix shell github:Tevy-DK/Tevy-DK-attic#omp -c omp --version
nix shell github:Tevy-DK/Tevy-DK-attic#codex -c codex --version
nix shell github:Tevy-DK/Tevy-DK-attic#sjmcl -c SJMCL
nix shell github:Tevy-DK/Tevy-DK-attic#motrix -c motrix
nix shell github:Tevy-DK/Tevy-DK-attic#etcher -c balena-etcher
nix shell github:Tevy-DK/Tevy-DK-attic#dsh-desktop -c dsh-desktop
```

本地开发时用短属性：

```sh
nix build .#omp --out-link result-omp
nix build .#codex --out-link result-codex
nix build .#sjmcl --out-link result-sjmcl
nix build .#motrix --out-link result-motrix
nix build .#etcher --out-link result-etcher
nix build .#dsh-desktop --out-link result-dsh-desktop
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
          environment.systemPackages = with pkgs; [ omp codex sjmcl motrix etcher ];
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
  attic.packages.x86_64-linux.codex
  attic.packages.x86_64-linux.sjmcl
  attic.packages.x86_64-linux.motrix
  attic.packages.x86_64-linux.etcher
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
    │   ├── omp/default.nix
    │   ├── codex/default.nix
    │   └── sjmcl/default.nix
    └── deb/
        └── etcher/default.nix
```

目录按打包策略划分。未来新增 Deb 包放 `pkgs/deb/<name>/`，AppImage 放 `pkgs/appimages/<name>/`；只有实际存在包时才创建目录。具体维护规范见 [AGENTS.md](./AGENTS.md)。

## 维护

只跟随上游最新 Release Tag，不跟随 `main`。版本与哈希必须来自真实产物，更新后跑 `nix build` 验证。完整流程、Deb/AppImage 处理规则和验证命令写在 [AGENTS.md](./AGENTS.md)。

`.github/workflows/auto-update.yml` 每天在 UTC 00:00 和 12:00 各运行一次自动更新：获取 `omp`、`codex`、`sjmcl`、`motrix`、`etcher` 的最新 Release，实测可用平台的哈希并改写版本号（`etcher` 只有 amd64 资产，脚本按单哈希处理；`dsh-desktop` 由上游 flake 提供，不在此列）。构建验证通过后以 `chore: auto update binaries [skip ci]` 提交并推送到 `main`。验证失败时工作流终止，不提交任何内容。本地可手动执行：

```sh
nix develop --command bash scripts/auto-update.sh
```

只有加 `--commit` 才会提交并推送。
