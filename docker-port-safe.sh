#!/usr/bin/env bash

set -e

find . -type f \( -name "docker-compose.yml" -o -name "docker-compose.yaml" -o -name "compose.yml" -o -name "compose.yaml" \) -print0 |
while IFS= read -r -d '' file; do
    echo "处理: $file"

    cp "$file" "$file.bak"

    python3 - "$file" <<'PY'
import sys
import re

file = sys.argv[1]

with open(file, "r", encoding="utf-8") as f:
    text = f.read()

# 修改 ports: 下的短格式：
#
#   - "8080:80"
#   - 8080:80
#   - "8080:80/tcp"
#
# 为：
#
#   - "127.0.0.1:8080:80"
#   - "127.0.0.1:8080:80/tcp"

pattern = re.compile(
    r'(^[ \t]*-[ \t]*["\']?)'
    r'(?P<host>\d+)'
    r':'
    r'(?P<container>\d+)'
    r'(?P<protocol>/[a-zA-Z0-9]+)?'
    r'(["\']?[ \t]*$)',
    re.MULTILINE
)

lines = text.splitlines(keepends=True)

in_ports = False
ports_indent = None
changed = False

for i, line in enumerate(lines):
    # 判断 ports:
    m = re.match(r'^(\s*)ports\s*:\s*$', line)
    if m:
        in_ports = True
        ports_indent = len(m.group(1).replace('\t', '    '))
        continue

    if in_ports:
        # 遇到同级/更高一级的配置项，退出 ports
        stripped = line.lstrip()

        if stripped and not stripped.startswith("-"):
            indent = len(line) - len(stripped)
            indent = len(line[:len(line)-len(stripped)].replace('\t', '    '))

            if indent <= ports_indent:
                in_ports = False
                ports_indent = None
                continue

        # 只处理 ports 列表
        if in_ports:
            m = pattern.match(line)

            if m:
                host = m.group("host")
                container = m.group("container")
                protocol = m.group("protocol") or ""

                newline = (
                    m.group(1)
                    + f"127.0.0.1:{host}:{container}"
                    + protocol
                    + m.group(5)
                )

                if newline != line:
                    lines[i] = newline
                    changed = True

with open(file, "w", encoding="utf-8") as f:
    f.write("".join(lines))

if changed:
    print("  ✓ 已修改")
else:
    print("  - 无需修改")
PY

done

echo
echo "完成。原文件已备份为 *.bak"
