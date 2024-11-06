# Chiefsters-Shaders
This is a repo for the shaders I've been making for the Halo editing kits.
Currently only contains a custom shader for Halo 4: srf_ggx. More will come over time.

## Install instructions
You can download a zip containing the data and tags, and from there just extract them into your H4EK directory. I've already compiled the shaders so they'll be be good to go.

## Halo 4 shaders
**srf_ggx**: A custom PBR material shader made for Halo 4, also compatible with Halo 2 Anniversary Multiplayer.
Textures:
- Albedo Map
- PBR ORM Map
- Normal Map
- Detail Normal Map (togglable; off by default)
- Reflection Map
Parameters:
- surface_color_tint
- roughness_scalar
- roughness_bias
- metalness_scalar
- metalness_bias
- detail_normal_intensity

The **PBR ORM Map** is a texture with Ambient Occlusion in the red channel, Roughness in the green channel, and Metalness in the blue channel. The _cov shaders use the alpha channel as a mask for the specular tint colors.<br/>
This texture should be set to linear when imported into the editing kit, with its Usuage set to **22. Blend Map (linear for terrains)**<br/>
There are also alternate versions of srf_ggx, like one with color change, self-illum, colored spec-gloss support and support for H2AMP's combo maps.