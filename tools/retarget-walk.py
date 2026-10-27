"""Retarget the Quaternius Universal Animation Library walk onto the Kenney character rig.

Kenney's Animated Characters (protagonists, retro, survivors) share one rig and ship only idle,
jump and run clips. This builds `assets/kenney/characters/walk.fbx` from the CC0 Universal Animation
Library (Standard, `Unreal-Godot/UAL1_Standard.glb`, clip `Walk_Loop`):

    blender -b --factory-startup -P tools/retarget-walk.py -- \\
        <kenney pack>/Animations/run.fbx UAL1_Standard.glb assets/kenney/characters/walk.fbx

Rotations are carried over as world-space changes from a T-pose that both rigs share (UAL's rest,
Kenney's "Targeting Pose" clip; Kenney's own rest hangs the arms down). The hips also take UAL's
travel, scaled by the ratio of the two pelvis heights. Only the walk is exported, as FBX like
Kenney's own clips, so Godot imports its bones in the same frame and units.
"""
import sys

import bpy
from mathutils import Matrix

argv = sys.argv[sys.argv.index("--") + 1:]
KENNEY_FBX, UAL_GLB, OUT_FBX = argv

# Parents come before children, so each target is computed from its already-posed parent.
MAPPING = [
    ("Hips", "pelvis"), ("Spine", "spine_01"), ("Chest", "spine_02"), ("UpperChest", "spine_03"),
    ("Neck", "neck_01"), ("Head", "Head"),
    ("LeftShoulder", "clavicle_l"), ("LeftArm", "upperarm_l"), ("LeftForeArm", "lowerarm_l"), ("LeftHand", "hand_l"),
    ("RightShoulder", "clavicle_r"), ("RightArm", "upperarm_r"), ("RightForeArm", "lowerarm_r"), ("RightHand", "hand_r"),
    ("LeftUpLeg", "thigh_l"), ("LeftLeg", "calf_l"), ("LeftFoot", "foot_l"), ("LeftToes", "ball_l"),
    ("RightUpLeg", "thigh_r"), ("RightLeg", "calf_r"), ("RightFoot", "foot_r"), ("RightToes", "ball_r"),
]
WALK = "Walk_Loop_Armature"
UAL_T_POSE = "A_TPose_Armature"

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=KENNEY_FBX)
kenney = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
bpy.ops.import_scene.gltf(filepath=UAL_GLB)
ual = next(o for o in bpy.data.objects if o.type == 'ARMATURE' and o is not kenney)
for ob in list(bpy.data.objects):
    if ob.type == 'MESH':
        bpy.data.objects.remove(ob, do_unlink=True)

ual_walk = bpy.data.actions[WALK]
ual.animation_data_create()
start, end = int(ual_walk.frame_range[0]), int(ual_walk.frame_range[1])

for name, _ in MAPPING:
    pose_bone = kenney.pose.bones[name]
    if pose_bone.constraints:
        raise SystemExit(f"bone {name} has constraints; they would override the retarget")
    pose_bone.rotation_mode = 'QUATERNION'

# Scale hip travel by the ratio of the two rigs' pelvis heights (Blender Z is up).
hips_rest = kenney.matrix_world @ kenney.data.bones["Hips"].matrix_local
pelvis_rest = ual.matrix_world @ ual.data.bones["pelvis"].matrix_local
height_ratio = hips_rest.translation.z / pelvis_rest.translation.z


def pose_at(armature, action, names):
    """World matrices of `names` with `action` posed at its first frame."""
    armature.animation_data.action = action
    bpy.context.scene.frame_set(int(action.frame_range[0]))
    bpy.context.view_layer.update()
    return {name: armature.matrix_world @ armature.pose.bones[name].matrix for name in names}


ual_reference = pose_at(ual, bpy.data.actions[UAL_T_POSE], [u for _, u in MAPPING])
kenney_t_pose = next(a for a in bpy.data.actions if a.name.endswith("Targeting Pose"))
kenney_reference = pose_at(kenney, kenney_t_pose, [k for k, _ in MAPPING])

walk = bpy.data.actions.new("Walk")
kenney.animation_data.action = walk
ual.animation_data.action = ual_walk
# Bones that are not mapped (fingers, IK controls) stay at rest, not in the targeting pose.
for pose_bone in kenney.pose.bones:
    pose_bone.matrix_basis.identity()
bpy.context.view_layer.update()


def body_frame(left, right, low, high):
    """Rotation whose columns are the body's left, forward and up directions in world space."""
    side = (left - right).normalized()
    up = (high - low).normalized()
    forward = up.cross(side).normalized()
    side = forward.cross(up).normalized()
    return Matrix((side, forward, up)).transposed()


# Changes measured on UAL are turned into Kenney's body frame, so a rig that faces another way
# still swings its arms and legs forward.
ual_frame = body_frame(ual_reference["upperarm_l"].translation, ual_reference["upperarm_r"].translation,
                       ual_reference["pelvis"].translation, ual_reference["Head"].translation)
kenney_frame = body_frame(kenney_reference["LeftArm"].translation, kenney_reference["RightArm"].translation,
                          kenney_reference["Hips"].translation, kenney_reference["Head"].translation)
ual_to_kenney = (kenney_frame @ ual_frame.inverted()).to_quaternion()

scene = bpy.context.scene
for frame in range(start, end + 1):
    scene.frame_set(frame)
    bpy.context.view_layer.update()
    for kenney_name, ual_name in MAPPING:
        ual_pose = ual.matrix_world @ ual.pose.bones[ual_name].matrix
        change = ual_pose.to_quaternion() @ ual_reference[ual_name].to_quaternion().inverted()
        change = ual_to_kenney @ change @ ual_to_kenney.inverted()
        rotation = (change @ kenney_reference[kenney_name].to_quaternion()).to_matrix().to_4x4()
        position = kenney_reference[kenney_name].translation
        if kenney_name == "Hips":
            position = position + ual_to_kenney @ ((ual_pose.translation - ual_reference[ual_name].translation) * height_ratio)
        pose_bone = kenney.pose.bones[kenney_name]
        pose_bone.matrix = kenney.matrix_world.inverted() @ Matrix.Translation(position) @ rotation
        bpy.context.view_layer.update()
        pose_bone.keyframe_insert("rotation_quaternion", frame=frame)
        if kenney_name == "Hips":
            pose_bone.keyframe_insert("location", frame=frame)

# Only the walk goes into the file: the client takes the longest clip it finds.
bpy.data.objects.remove(ual, do_unlink=True)
for action in list(bpy.data.actions):
    if action != walk:
        bpy.data.actions.remove(action)

bpy.ops.object.select_all(action='DESELECT')
kenney.select_set(True)
bpy.context.view_layer.objects.active = kenney
scene.frame_start, scene.frame_end = start, end
bpy.ops.export_scene.fbx(filepath=OUT_FBX, use_selection=True, object_types={'ARMATURE'},
                         add_leaf_bones=False, bake_anim=True, bake_anim_use_all_actions=False,
                         bake_anim_use_nla_strips=False, bake_anim_force_startend_keying=True)
print("exported", OUT_FBX, "frames", start, end)
