Slavic World Free
Maciej EmacArt
================================================================

HOW TO ADD IT TO YOUR PROJECT
  Unpack the zip, open the "SlavicWorldFree" folder and copy its
  CONTENTS (Prefabs, Objects, Materials, Textures, Shaders, Skybox,
  Terrain, SourceFiles, Demo, Documentation) into your Godot project
  folder. That is all -- the pack is self-contained and does not
  require any plugins or add-ons.

  You can also open "SlavicWorldFree" directly as a Godot project
  and look at the demo scenes first.

WHAT IS WHERE
  Prefabs/        ready-to-use object scenes (.scn) -- these are
                  what you instance in your own scenes
  Objects/        source FBX files and the meshes extracted from
                  them (Objects/extracted)
  Materials/      materials
  Textures/       palette and terrain textures
  Shaders/        grass wind, skybox and water shaders
  Skybox/         skybox material and cubemap textures
  Terrain/        terrain meshes, splatmaps and terrain materials
  SourceFiles/    alternative palette texture and materials
  Demo/           showcase scenes
  Documentation/  this file, license, contents list

HOW TO USE
  Drag a .scn file from Prefabs/ into your scene, or use
  "Instantiate Child Scene". Every object already comes with its
  mesh and material.

COLLISION
  Buildings, props, fences, rocks, roads, trees, stumps and both
  terrain scenes have collision (StaticBody3D with a trimesh
  collision shape), so the player walks on them and bumps into them
  straight away.

  Grass, bushes, sweet flag, moss and small plants have NO collision
  on purpose -- they are meant to be walked through, and thousands of
  scattered plants with collision shapes would cost performance for
  nothing.

RECOLOURING THE WHOLE PACK
  The pack uses one shared material with a single palette texture.
  Replace the texture in Textures/ and every object changes at once.

TESTED ON
  Godot 4.7.1

LICENSE
  EmacEArt Asset License -- free for personal and commercial use,
  but resale or redistribution of the assets as standalone files
  or asset packs is prohibited. No credit is required, though it
  is always welcome. See LICENSE.txt in this folder.

CONTACT
  Website: emaceart.dev
  Discord: https://discord.com/invite/ctXaf5Ftqw

================================================================
