---
description: Abstract pack textures — masks tinted in-shader; only a texture with a consumer is imported
paths:
  - "assets/textures/abstract/**"
---

A pack texture is a luminance mask tinted in-shader (never its raw colours), and only a texture with a consumer is imported — `test_abstract_texture_library.gd` gates it. See docs/domain/abstract-textures.md
