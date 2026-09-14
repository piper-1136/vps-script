# vps-script

个人常用的 VPS 运维脚本集合，无需 clone 仓库，一条命令即可拉起菜单选择运行。

## 使用方法

直接运行菜单脚本，会自动从本仓库拉取最新脚本列表：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/piper-1136/vps-script/main/menu.sh)
```

运行后会看到编号菜单，输入数字选择要执行的脚本，确认后自动下载并运行。

## 脚本列表

| 脚本 | 说明 |
| --- | --- |
| `docker-port-safe.sh` | Docker 端口安全相关处理 |
| `port-forward.sh` | 端口转发配置 |
| `menu.sh` | 入口菜单脚本，扫描并列出仓库内所有 `.sh` 脚本 |

> 新增脚本到仓库根目录后，菜单会自动识别，无需修改 `menu.sh`。

## 依赖

- `bash`
- `curl`
- `jq`（可选，未安装时自动降级为正则解析）

## 注意事项

- 脚本通过 `curl | bash` 方式执行远程代码，运行前请确认来源可信。
- 未认证的 GitHub API 请求存在速率限制（每 IP 每小时 60 次），高频调用可能失败。
- 部分脚本可能需要 root 权限，请按需使用 `sudo`。
