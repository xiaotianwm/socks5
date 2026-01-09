# Simple SOCKS5 Server & TCP Optimizer

这是一个基于 Go 语言编写的轻量级 SOCKS5 服务器，专注于隐私（无日志记录）和高性能。本项目包含完整的 `main.go` 源码，你可以直接使用一键脚本部署，也可以自行编译修改。

此外，本项目还附带了一个用于 Linux 服务器的 TCP/BBR 网络优化脚本。

## ✨ 功能特点

* **极简主义**：无配置文件，无日志记录，保护隐私。
* **高性能**：基于 Go 语言的高并发处理能力。
* **一键部署**：提供全自动安装脚本，自动配置 Systemd 服务、开机自启。
* **网络优化**：附带 BBR 及 TCP 协议栈调优脚本，提升传输速度。
* **开源透明**：提供完整源码，可自行审计或编译。

### 🚀 快速开始 (使用预编译脚本)

如果你不想手动编译，可以直接使用预设脚本在服务器上运行。请使用 **Root** 用户执行。

### 1. 开启 BBR 及网络优化 (推荐)

在安装服务前，建议先运行此脚本以优化服务器网络性能：

```bash
bash <(wget -qO- https://raw.githubusercontent.com/xiaotianwm/socks5/main/bbr.sh)

```

### 2. 一键安装 SOCKS5 服务

使用以下命令安装并启动服务。请替换 `<端口>`、`<用户名>` 和 `<密码>` 为你自己的设置。

**语法：**

```bash
bash <(wget -qO- https://raw.githubusercontent.com/xiaotianwm/socks5/main/install.sh) <端口> <用户名> <密码>

```

**示例 (开启 2080 端口，账号 admin，密码 123456)：**

```bash
bash <(wget -qO- https://raw.githubusercontent.com/xiaotianwm/socks5/main/install.sh) 2080 admin 123456

```

> **⚠️ 注意**：请勿使用常用系统端口（如 22, 80, 443）或保留端口（如 123），建议使用 1024 - 65535 之间的端口。

---

## 🏗️ 手动编译 (可选)

如果你希望自行从源码编译二进制文件，请确保本地已安装 [Go 环境](https://go.dev/dl/)。

### 1. 下载源码

```bash
git clone [https://github.com/xiaotianwm/socks5.git](https://github.com/xiaotianwm/socks5.git)
cd socks5

```

### 2. 编译命令

针对 Linux 服务器 (amd64 架构) 的编译命令如下：

**在 Linux/macOS 上编译：**

```bash
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o socks5-server main.go

```

**在 Windows (PowerShell) 上编译：**

```powershell
$env:CGO_ENABLED="0"
$env:GOOS="linux"
$env:GOARCH="amd64"
go build -o socks5-server main.go

```

编译完成后，你会得到一个 `socks5-server` 文件，将其上传至服务器并赋予执行权限即可运行。

---

## 🛠 服务管理

安装完成后，服务会自动在后台运行并开机自启。你可以使用以下命令进行管理：

* **查看运行状态**：
```bash
systemctl status mysocks5

```


* **停止服务**：
```bash
systemctl stop mysocks5

```


* **重启服务**：
```bash
systemctl restart mysocks5

```


* **卸载服务**：
```bash
systemctl stop mysocks5
systemctl disable mysocks5
rm /usr/local/bin/socks5-server
rm /etc/systemd/system/mysocks5.service
systemctl daemon-reload

```



## 📝 说明

* **SOCKS5 程序**：编译自 `main.go`，仅保留核心转发逻辑，去除所有控制台输出和日志记录，适合静默运行。
* **BBR 脚本**：自动开启 BBR 拥塞控制，调整 TCP 窗口大小、缓冲区及队列长度，优化高并发与大带宽环境下的连接稳定性。

```

```
