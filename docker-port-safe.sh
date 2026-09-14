#!/bin/bash

set -e

FILES=()

[ -f "docker-compose.yml" ] && FILES+=("docker-compose.yml")
[ -f "docker-compose.yaml" ] && FILES+=("docker-compose.yaml")

if [ ${#FILES[@]} -eq 0 ]; then
    echo "❌ 当前目录没有找到 docker-compose.yml 或 docker-compose.yaml"
    exit 1
fi

for FILE in "${FILES[@]}"; do
    echo "🔧 处理: $FILE"

    # 自动备份
    cp "$FILE" "$FILE.bak"

    python3 - "$FILE" <<'PY'
import re
import sys

file = sys.argv[1]

with open(file, "r", encoding="utf-8") as f:
    content = f.read()

def replace_port(match):
    prefix = match.group(1)
    port = match.group(2)

    # 已经绑定 127.0.0.1，不处理
    if prefix == "127.0.0.1:":
        return match.group(0)

    return f"{match.group(0)[:match.group(0).find(port)]}" + port

# 处理:
#   - "8080:8080"
#   - '8080:8080'
#   - - 8080:8080
#
# 只处理 ports 区域中的常见短格式
lines = content.splitlines()

in_ports = False
ports_indent = None

for i, line in enumerate(lines):
    stripped = line.lstrip()
    indent = len(line) - len(stripped)

    # ports:
    if re.match(r'^ports\s*:\s*$', stripped):
        in_ports = True
        ports_indent = indent
        continue

    # 离开 ports 块
    if in_ports:
        if stripped and indent <= ports_indent:
            in_ports = False
            ports_indent = None

    if not in_ports:
        continue

    # 匹配:
    # - "8080:8080"
    # - '8080:8080'
    # - 8080:8080
    m = re.match(
        r'^(\s*-\s*)(["\']?)([^"\':\s]+):([^"\':\s]+)(["\']?)\s*$',
        line
    )

    if not m:
        continue

    prefix, quote1, host, container, quote2 = m.groups()

    # 已经指定 IP，例如:
    # 127.0.0.1:8080:8080
    # 0.0.0.0:8080:8080
    if host.count(".") == 3:
        continue

    # IPv6 或其他复杂写法暂不处理
    if ":" in host:
        continue

    # 修改成 127.0.0.1:HOST:CONTAINER
    lines[i] = (
        f'{prefix}{quote1}'
        f'127.0.0.1:{host}:{container}'
        f'{quote2}'
    )

new_content = "\n".join(lines)

if content.endswith("\n"):
    new_content += "\n"

with open(file, "w", encoding="utf-8") as f:
    f.write(new_content)

PY

    echo "✅ 完成: $FILE"
    echo "   备份: $FILE.bak"
done

echo
echo "完成。可以使用以下命令检查："
echo
echo "docker compose config"
