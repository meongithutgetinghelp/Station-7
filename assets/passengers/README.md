# Station 7 passenger model

Original geometry authored for this project by `tools/build_passenger_model.py`.
`passenger_base.glb` is the runtime model; editable Blender source is in
`builds/passenger-redesign/passenger_base.blend`.

The model has 19 deform bones, tapered clothing, a shaped face, ears, nose,
hands, shoes, four interchangeable hair silhouettes, optional glasses and a bag.
Ordinary eyes have dark pupils, with no emission. Runtime idle/walk/seated poses
are driven by `passenger_visual.gd`. This is a stylized low-poly pass, not final
scanned or sculpted character art. The user's separate monster animations are
not authored by this passenger generator.

Passenger names deterministically select visual variation, matching portraits,
saved identities and co-op replicas. Existing profile skin/hair/coat colors stay
intact. The example first passenger draws 4,158 triangles; exact visible cost
varies with hair and accessories. Mesh resources and palette materials are
shared. Every mesh of an anomalous passenger uses layer 2 so the existing CCTV
absence rule is preserved. Routes, tickets and game decisions remain host-owned.

Regenerate with Blender 5.1:
`Blender --background --python tools/build_passenger_model.py`, then reimport the
project in Godot. Keep the output's bone names and palette material names intact.
