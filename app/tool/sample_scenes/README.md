# Sample job photos

The demo's sample photos (`assets/samples/*.jpg`) are 3D renders, so they
carry no licensing questions. To re-render them:

```sh
cd app/tool/sample_scenes
npm install three@0.170.0 playwright-core
python3 -m http.server 8799 &
mkdir -p out
CHROME_PATH=/path/to/chrome node render.js \
  living:1 living:2 living:3 fence:1 fence:2 fence:3 driveway:1 driveway:2
```

Then downscale each to 1280x960 and save as `assets/samples/<job>_<n>.jpg`
(`living` becomes `living_room`). The scenes are sized to match the sample
drafts in `packages/core/lib/src/demo_drafts.dart`: a 15 x 13 ft room with
8 ft ceilings, a 96 ft fence run with a 4 ft gate, and an 18 x 40 ft
driveway.
