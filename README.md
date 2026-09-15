# vps-script

个人常用的 VPS 运维脚本集合，无需 clone 仓库，一条命令即可拉起菜单选择运行。

## 使用方法

直接运行菜单脚本，会自动从本仓库拉取最新脚本列表：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/piper-1136/vps-script/main/menu.sh)
```

代理版本
```bash
bash <(curl -fsSL https://o-o.men/https://raw.githubusercontent.com/piper-1136/vps-script/main/menu.sh)
```

运行后会看到编号菜单，输入数字选择要执行的脚本，确认后自动下载并运行。

## 脚本列表

| 脚本 | 说明 |
| --- | --- |
| `docker-bash.sh` | 按关键字匹配运行中的 Docker 容器并进入其终端（自动检测 bash / sh） |
| `docker-port-safe.sh` | 将 docker-compose 中的端口绑定改为 `127.0.0.1`，避免向公网暴露（自动备份为 `*.bak`） |
| `port-forward.sh` | iptables 端口转发管理：添加 / 查看 / 删除转发规则（TCP+UDP，需 root） |
| `menu.sh` | 入口菜单脚本，扫描并列出仓库内所有 `.sh` 脚本 |

> 新增脚本到仓库根目录后，菜单会自动识别，无需修改 `menu.sh`。
