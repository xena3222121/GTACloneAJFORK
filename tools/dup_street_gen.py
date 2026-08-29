import re
import sys

# Generalized version of dup_street.py - always duplicates the ORIGINAL
# (unsuffixed) group rather than a specific existing copy, parameterized by
# suffix/offset so it can stamp out additional neighborhoods (C, D, ...)
# the same proven way "B" was made, instead of hand-placing hundreds of nodes.

SUFFIX = sys.argv[1]
X_OFFSET = float(sys.argv[2])
OUT_PATH = sys.argv[3]

with open("scenes/World.tscn", "r", encoding="utf-8") as f:
    content = f.read()

GROUPS = ["Street", "Houses", "Driveways", "ParkedCars", "TrafficCars", "Trees", "NPCs"]

lines = content.split("\n")

def find_group_block(name):
    start = None
    for i, line in enumerate(lines):
        if re.match(rf'^\[node name="{name}" type="Node3D" parent="\."', line):
            start = i
            break
    if start is None:
        raise ValueError(f"Group {name} not found")
    end = start + 1
    while end < len(lines):
        if re.match(r'^\[node name="\w+" type="\w+" parent="\."', lines[end]):
            break
        end += 1
    return start, end

def shift_transform_line(line, dx):
    m = re.match(r'^(transform = Transform3D\()(.+)(\))$', line)
    if not m:
        return line
    nums = [p.strip() for p in m.group(2).split(",")]
    assert len(nums) == 12, f"unexpected transform field count: {line}"
    tx = float(nums[9]) + dx
    nums[9] = _fmt(tx)
    return m.group(1) + ", ".join(nums) + m.group(3)

def _fmt(v):
    s = f"{v:.6f}".rstrip("0").rstrip(".")
    return s if s else "0"

out_blocks = []
for gname in GROUPS:
    start, end = find_group_block(gname)
    block = lines[start:end]
    new_block = []
    is_direct_child_of_group = False
    for line in block:
        node_match = re.match(r'^\[node name="[^"]+"(?: type="[^"]+")? parent="([^"]+)"', line)
        if node_match:
            parent_val = node_match.group(1)
            is_direct_child_of_group = (parent_val == gname)

        line = re.sub(r'^\[node name="' + gname + r'"', f'[node name="{gname}{SUFFIX}"', line)
        line = re.sub(r'parent="' + gname + r'"', f'parent="{gname}{SUFFIX}"', line)
        line = re.sub(r'parent="' + gname + r'/', f'parent="{gname}{SUFFIX}/', line)
        line = re.sub(r'\s*unique_id=\d+', '', line)
        if line.startswith("transform = Transform3D(") and is_direct_child_of_group:
            line = shift_transform_line(line, X_OFFSET)
        new_block.append(line)
    out_blocks.append("\n".join(new_block))
    print(f"Duplicated group '{gname}' -> '{gname}{SUFFIX}' (offset {X_OFFSET}): {len(block)} lines")

with open(OUT_PATH, "w", encoding="utf-8") as f:
    f.write("\n\n".join(out_blocks) + "\n")

print(f"Wrote {OUT_PATH}")
