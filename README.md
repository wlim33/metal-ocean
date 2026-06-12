# metal-ocean

![macOS](https://img.shields.io/badge/macOS-13%2B-lightgrey)
![Metal](https://img.shields.io/badge/Metal-3-blue)
![C++](https://img.shields.io/badge/C%2B%2B-20-00599C)
![License](https://img.shields.io/badge/license-MIT-green)

Real-time ocean water for macOS. Tessendorf-style FFT waves, simulated and
shaded entirely on the GPU with Metal. No engine underneath, just AppKit and
C++20 with a thin Objective-C++ layer.

![metal-ocean](docs/screenshot.jpg)

Each frame, a Phillips spectrum (with a swell parameter for directional
spread) is advanced in time and inverse-FFT'd — Stockham radix-2, all in
compute — into displacement and normal maps for three wave cascades: 271 m,
73 m and 17 m patches at 256×256 each. The maps displace a projected grid
(Johanson 2004), so the mesh always fills the frustum regardless of camera
height. Whitecaps come from thresholding the Jacobian of the horizontal
displacement; shading is Fresnel over a Preetham analytic sky baked to a
cubemap, plus sun specular, a depth-fog refraction approximation,
subsurface scatter on backlit crests, and ACES tonemapping. The whole thing
costs about 1.0–1.5 ms of GPU time per frame on an Apple Silicon laptop.

## Building

Needs macOS 13+ (the shaders target Metal 3), Xcode for the Metal compiler,
CMake 3.24+ and Ninja. Dependencies (glm, toml++, Dear ImGui, googletest)
are fetched by CMake on the first configure, so that step needs network
access.

```sh
cmake -B build -G Ninja
cmake --build build
cmake --build build --target run   # builds and opens metal-ocean.app
```

## Running

Drag to orbit the camera, scroll to zoom. Wind speed, choppiness, swell,
sun position, turbidity, foam and the rest are live sliders in the ImGui
panel.

Settings come from `default-config.toml`, which is baked into the app
bundle at build time. Point at another file with `--config`, or override
single values with repeatable `--set`:

```sh
./build/metal-ocean.app/Contents/MacOS/metal-ocean \
    --config stormy.toml --set wave.wind_speed_mps=20 --set sky.turbidity=6
```

## Benchmarking

```sh
./build/metal-ocean.app/Contents/MacOS/metal-ocean --set bench.bench_mode=true
```

flies a deterministic camera orbit (60 warm-up + 600 measured frames) and
writes per-frame CPU/GPU timings, drawable wait and a config hash to
`bench-<timestamp>.csv` in the working directory.

## Tests

The simulation core (spectrum, FFT reference, projected grid, camera,
config) is plain C++ with no Metal dependency:

```sh
ctest --test-dir build
```

## References

- Jerry Tessendorf, *Simulating Ocean Water*, SIGGRAPH course notes, 2001
- Claes Johanson, *Real-time Water Rendering: Introducing the Projected Grid Concept*, 2004
- A. J. Preetham, Peter Shirley, Brian Smits, *A Practical Analytic Model for Daylight*, SIGGRAPH 1999

MIT licensed.
