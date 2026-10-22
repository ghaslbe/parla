// swift-tools-version:5.9
import PackageDescription

// NOTE: the CWhisper module links static libraries produced by
// `scripts/build-whisper.sh` (run automatically by `make`). Those libs live in
// third_party/lib and are not checked in. Build via `make`, not bare
// `swift build`, so whisper.cpp is compiled first.
let package = Package(
    name: "Parla",
    platforms: [.macOS(.v13)],
    targets: [
        .systemLibrary(name: "CWhisper", path: "Sources/CWhisper"),
        .executableTarget(
            name: "Parla",
            dependencies: ["CWhisper"],
            path: "Sources/Parla",
            linkerSettings: [
                .unsafeFlags([
                    "-L", "third_party/lib",
                    "-lwhisper", "-lggml", "-lggml-base", "-lggml-cpu",
                    "-lggml-metal", "-lggml-blas", "-lparakeet", "-lc++",
                    "-framework", "Metal",
                    "-framework", "MetalKit",
                    "-framework", "Foundation",
                    "-framework", "Accelerate",
                ])
            ]
        ),
    ]
)
