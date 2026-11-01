# Tevy-DK-attic

个人 Nix 软件源。核心原则：**不编译源码，只打包上游 Release 的预编译产物**。目标是极简、构建快、版本新，并且更新流程可重复。

## 包

| 属性 | 版本 | 上游 | 产物 | 平台 |
| --- | --- | --- | --- | --- |
| `omp` | 18.14.2 | [can1357/oh-my-pi](https://github.com/can1357/oh-my-pi) | `omp-linux-{x64,arm64}` | `x86_64-linux`, `aarch64-linux` |
| `codex` | 0.166.0 | [openai/codex](https://github.com/openai/codex) | `codex-{x86_64,aarch64}-unknown-linux-musl.tar.gz` | `x86_64-linux`, `aarch64-linux` |
| `sjmcl` | 1.4.0 | [UNIkeEN/SJMCL](https://github.com/UNIkeEN/SJMCL) | `SJMCL_1.4.0_linux_{x86_64,aarch64}_portable` | `x86_64-linux`, `aarch64-linux` |

`omp` 说明：上游的 `omp-linux-musl-*` 并非静态二进制，而是动态链接 musl 版 `libstdc++`/`libgcc`。在 NixOS（glibc 环境）上给进程注入 musl `libstdc++` 会破坏 omp 派生的 glibc 子进程，因此本仓库使用同一版本的 `omp-linux-*` glibc 资产。`codex` 的 musl 资产是真正的 static-pie，直接安装。

## 使用

### 直接构建 / 运行

```sh
nix build github:Tevy-DK/Tevy-DK-attic#omp
nix build github:Tevy-DK/Tevy-DK-attic#codex
nix build github:Tevy-DK/Tevy-DK-attic#sjmcl

nix shell github:Tevy-DK/Tevy-DK-attic#omp -c omp --version
nix shell github:Tevy-DK/Tevy-DK-attic#codex -c codex --version
nix shell github:Tevy-DK/Tevy-DK-attic#sjmcl -c SJMCL
```

本地开发时用短属性：

```sh
nix build .#omp --out-link result-omp
nix build .#codex --out-link result-codex
nix build .#sjmcl --out-link result-sjmcl
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
          environment.systemPackages = with pkgs; [ omp codex sjmcl ];
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
    └── binaries/
        ├── omp/default.nix
        ├── codex/default.nix
        └── sjmcl/default.nix
```

目录按打包策略划分。未来新增 Deb 包放 `pkgs/deb/<name>/`，AppImage 放 `pkgs/appimages/<name>/`；只有实际存在包时才创建目录。具体维护规范见 [AGENTS.md](./AGENTS.md)。

## 维护

只跟随上游最新 Release Tag，不跟随 `main`。版本与哈希必须来自真实产物，更新后跑 `nix build` 验证。完整流程、Deb/AppImage 处理规则和验证命令写在 [AGENTS.md](./AGENTS.md)。

`.github/workflows/auto-update.yml` 每天在 UTC 00:00 和 12:00 各运行一次自动更新：获取 `omp`、`codex`、`sjmcl` 的最新 Release，实测双平台哈希并改写表达式，构建验证通过后以 `chore: auto update binaries [skip ci]` 提交并推送到 `main`。验证失败时工作流终止，不提交任何内容。本地可手动执行：

```sh
nix develop --command bash scripts/auto-update.sh
```

只有加 `--commit` 才会提交并推送。
