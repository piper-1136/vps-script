#!/usr/bin/env bash

set -e

find . -type f \( \
    -name "docker-compose.yml" -o \
    -name "docker-compose.yaml" -o \
    -name "compose.yml" -o \
    -name "compose.yaml" \
\) -print0 |
while IFS= read -r -d '' file; do

    # 备份
    cp "$file" "$file.bak"

    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "文件: $file"

    python3 - "$file" <<'PY'
import sys
import re

file = sys.argv[1]

with open(file, "r", encoding="utf-8") as f:
    text = f.read()

lines = text.splitlines(keepends=True)

in_ports = False
ports_indent = None
changes = []

# 匹配：
# "8080:80"
# 8080:80
# "8080:80/tcp"
pattern = re.compile(
    r'(^[ \t]*-[ \t]*["\']?)'
    r'(?P<host>\d+)'
    r':'
    r'(?P<container>\d+)'
    r'(?P<protocol>/[a-zA-Z0-9]+)?'
    r'(["\']?[ \t]*$)'
)

for i, line in enumerate(lines):

    # 找到 ports:
    m = re.match(r'^(\s*)ports\s*:\s*$', line)

    if m:
        in_ports = True
        ports_indent = len(m.group(1).replace('\t', '    '))
        continue

    if not in_ports:
        continue

    stripped = line.lstrip()

    # ports 下出现新的同级配置
    if stripped and not stripped.startswith("-"):
        indent = len(line) - len(stripped)

        if indent <= ports_indent:
            in_ports = False
            ports_indent = None
            continue

    if in_ports:
        m = pattern.match(line)

        if m:
            host = m.group("host")
            container = m.group("container")
            protocol = m.group("protocol") or ""

            old = line.rstrip("\n")

            new = (
                m.group(1)
                + f"127.0.0.1:{host}:{container}"
                + protocol
                + m.group(5)
            )

            if new != old:
                lines[i] = new + ("\n" if line.endswith("\n") else "")

                changes.append(
                    (i + 1, old.strip(), new.strip())
                )

with open(file, "w", encoding="utf-8") as f:
    f.write("".join(lines))

if changes:
    for line_no, old, new in changes:
        print(f"  第 {line_no} 行:")
        print(f"    - {old}")
        print(f"    + {new}")

    print(f"  共修改 {len(changes)} 个端口")
else:
    print("  无需修改")
PY

done

echo
echo "========================================"
echo "处理完成"
echo "========================================"
echo "原文件已备份为 *.bak"
