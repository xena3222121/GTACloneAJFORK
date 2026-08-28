with open("scenes/World.tscn", "r", encoding="utf-8") as f:
    content = f.read()

with open("tools/highway_block.txt", "r", encoding="utf-8") as f:
    highway_block = f.read()

with open("tools/dup_street_output.txt", "r", encoding="utf-8") as f:
    dup_block = f.read()

# Split the highway file into its sub_resource lines and its node lines.
highway_lines = highway_block.split("\n")
split_idx = next(i for i, l in enumerate(highway_lines) if l.startswith('[node name="Highway"'))
highway_subresources = "\n".join(highway_lines[:split_idx]).rstrip("\n")
highway_nodes = "\n".join(highway_lines[split_idx:]).rstrip("\n")

POLICE_BLOCK = '''[node name="Police" type="Node3D" parent="."]

[node name="Police1" parent="Police" instance=ExtResource("22")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 3.9, 0.1, -35)

[node name="Police2" parent="Police" instance=ExtResource("22")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -3.9, 0.1, 20)

[node name="Police3" parent="Police" instance=ExtResource("22")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 63.9, 0.1, -10)

[node name="Police4" parent="Police" instance=ExtResource("22")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 20, 0.1, 46)
'''

# 1. Add the Police.tscn ext_resource right after the last existing one.
old_ext = '[ext_resource type="PackedScene" path="res://scenes/TreeCommon3.tscn" id="21"]'
new_ext = old_ext + '\n[ext_resource type="PackedScene" path="res://scenes/Police.tscn" id="22"]'
assert content.count(old_ext) == 1
content = content.replace(old_ext, new_ext)

# 2. Insert the highway's sub_resources right before the World node.
old_subres_end = '[sub_resource type="BoxMesh" id="BoxMesh_driveway"]\nsize = Vector3(4.5, 0.15, 2.4)\n'
assert content.count(old_subres_end) == 1
content = content.replace(old_subres_end, old_subres_end + "\n" + highway_subresources + "\n")

# 3. Insert the Highway node group, the duplicated block, and the Police
#    group right before the Player node (order doesn't matter for a flat
#    Node3D hierarchy - this just keeps new content grouped together).
old_player_anchor = '[node name="Player" parent="." unique_id=821898990 instance=ExtResource("1")]'
assert content.count(old_player_anchor) == 1
insertion = highway_nodes + "\n\n" + dup_block + "\n" + POLICE_BLOCK + "\n"
content = content.replace(old_player_anchor, insertion + old_player_anchor)

with open("scenes/World.tscn", "w", encoding="utf-8") as f:
    f.write(content)

print("World.tscn assembled successfully.")
print("New line count:", content.count("\n") + 1)
