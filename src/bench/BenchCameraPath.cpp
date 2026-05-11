#include "bench/BenchCameraPath.h"
#include <cmath>
namespace mo {
void apply_bench_path(OrbitCamera& cam, CameraPath path, int frame_idx) {
    float t = (float)frame_idx / 60.0f;
    switch (path) {
        case CameraPath::Static:
            cam.yaw_rad = 0.4f; cam.pitch_rad = 0.25f; cam.distance = 80.0f; break;
        case CameraPath::Orbit:
            cam.yaw_rad = 0.4f + t * 0.3f;
            cam.pitch_rad = 0.25f + 0.05f * std::sin(t * 0.5f);
            cam.distance = 80.0f; break;
        case CameraPath::Flyby:
            cam.yaw_rad = 1.5f - t * 0.05f;
            cam.pitch_rad = 0.05f + 0.02f * std::sin(t * 0.7f);
            cam.distance = 40.0f + 30.0f * std::sin(t * 0.2f); break;
    }
}
}
