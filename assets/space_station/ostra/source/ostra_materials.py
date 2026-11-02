"""Waypost Ostra's placeholder materials, shared by the kit's build scripts (the shell, the exterior, the furniture and
the dressing): one per name. In the game OstraLook (game/space_station/ostra_look.gd) swaps each for the station's
own material of the same name, so these only show in Blender's previews and as the .glb's fallback; a new name needs
its material there too.
"""

import bpy

# name: (base color, roughness, metallic, transmission, emission strength; an emissive one glows in its base color)
MATERIALS = {
    "OstraPaint": ((0.40, 0.38, 0.34), 0.6, 0.0, 0.0, 0.0),
    "OstraPaintDark": ((0.10, 0.10, 0.10), 0.55, 0.0, 0.0, 0.0),
    "OstraMetal": ((0.5, 0.5, 0.5), 0.4, 1.0, 0.0, 0.0),
    "OstraFloor": ((0.22, 0.22, 0.22), 0.5, 0.0, 0.0, 0.0),
    "OstraGrating": ((0.3, 0.3, 0.3), 0.45, 1.0, 0.0, 0.0),
    "OstraHazard": ((0.8, 0.6, 0.1), 0.6, 0.0, 0.0, 0.0),
    "OstraRubber": ((0.03, 0.03, 0.03), 0.8, 0.0, 0.0, 0.0),
    "OstraFabric": ((0.2, 0.12, 0.08), 0.75, 0.0, 0.0, 0.0),
    "OstraWood": ((0.3, 0.18, 0.1), 0.45, 0.0, 0.0, 0.0),
    "OstraCanvas": ((0.33, 0.29, 0.21), 0.9, 0.0, 0.0, 0.0),
    "OstraGlass": ((0.6, 0.7, 0.75), 0.05, 0.0, 1.0, 0.0),
    "OstraBottle": ((0.25, 0.12, 0.04), 0.15, 0.0, 0.5, 0.0),
    "OstraScreen": ((0.2, 0.9, 0.85), 0.3, 0.0, 0.0, 3.0),
    "OstraLamp": ((1.0, 0.8, 0.55), 0.3, 0.0, 0.0, 6.0),
    "OstraAmber": ((1.0, 0.55, 0.12), 0.3, 0.0, 0.0, 4.0),
    "OstraRed": ((1.0, 0.1, 0.05), 0.3, 0.0, 0.0, 4.0),
    "OstraPlant": ((0.12, 0.3, 0.08), 0.7, 0.0, 0.0, 0.0),
    "OstraOrange": ((0.75, 0.3, 0.05), 0.5, 0.0, 0.0, 0.0),
    "OstraContainerRed": ((0.35, 0.1, 0.07), 0.6, 0.0, 0.0, 0.0),
    "OstraContainerBlue": ((0.12, 0.2, 0.3), 0.6, 0.0, 0.0, 0.0),
    "OstraContainerOlive": ((0.25, 0.27, 0.15), 0.6, 0.0, 0.0, 0.0),
}


def material(name: str) -> bpy.types.Material:
    """The placeholder material `name` (made the first time it's asked for)."""
    mat = bpy.data.materials.get(name)
    if mat is not None:
        return mat
    color, roughness, metallic, transmission, emission = MATERIALS[name]
    mat = bpy.data.materials.new(name)
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Transmission Weight"].default_value = transmission
    if emission:
        bsdf.inputs["Emission Color"].default_value = (*color, 1)
        bsdf.inputs["Emission Strength"].default_value = emission
    return mat
