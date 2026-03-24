// swift-tools-version: 5.9
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Torlando Tech LLC

import PackageDescription

let package = Package(
    name: "LXSTSwift",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "LXSTSwift",
            targets: ["LXSTSwift"]
        )
    ],
    dependencies: [
        .package(path: "../reticulum-swift-lib"),
    ],
    targets: [
        // Opus codec compiled from source (v1.5.2)
        .target(
            name: "COpus",
            path: "Sources/COpus",
            exclude: [
                // Build system / meta files
                "AUTHORS", "COPYING", "ChangeLog", "INSTALL", "NEWS", "README",
                "CMakeLists.txt", "Makefile.am", "Makefile.in", "Makefile.unix", "Makefile.mips",
                "configure", "configure.ac", "config.guess", "config.sub", "config.h.in",
                "aclocal.m4", "compile", "depcomp", "install-sh", "ltmain.sh", "missing", "test-driver",
                "meson.build", "meson_options.txt",
                "opus.m4", "opus.pc.in", "opus-uninstalled.pc.in", "package_version",
                "celt_headers.mk", "celt_sources.mk", "opus_headers.mk", "opus_sources.mk",
                "silk_headers.mk", "silk_sources.mk", "lpcnet_headers.mk", "lpcnet_sources.mk",
                // Directories to exclude
                "cmake", "doc", "m4", "meson", "tests", "dnn",
                // Platform-specific SIMD (not needed for generic float build)
                "celt/arm", "celt/mips", "celt/x86",
                "silk/arm", "silk/mips", "silk/x86",
                "silk/fixed",  // Fixed-point — we use floating-point
                "silk/float/x86",  // AVX2 intrinsics in float subdir
                // Test/demo files in source dirs
                "celt/tests", "silk/tests",
                "celt/opus_custom_demo.c",
                "src/opus_demo.c", "src/opus_compare.c", "src/repacketizer_demo.c",
                // Sub-dir meson/build files
                "celt/meson.build", "silk/meson.build",
                "src/meson.build", "include/meson.build",
            ],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("."),
                .headerSearchPath("celt"),
                .headerSearchPath("silk"),
                .headerSearchPath("silk/float"),
                .headerSearchPath("src"),
                .define("OPUS_BUILD"),
                .define("VAR_ARRAYS", to: "1"),
                .define("FLOATING_POINT"),
                .define("HAVE_LRINT", to: "1"),
                .define("HAVE_LRINTF", to: "1"),
                .define("HAVE_STDINT_H", to: "1"),
                .define("HAVE_DLFCN_H", to: "1"),
                .define("HAVE_INTTYPES_H", to: "1"),
                .define("HAVE_MEMORY_H", to: "1"),
                .define("HAVE_STDLIB_H", to: "1"),
                .define("HAVE_STRING_H", to: "1"),
            ]
        ),
        // Codec2 voice codec compiled from source (v1.2.0)
        .target(
            name: "CCodec2",
            path: "Sources/CCodec2",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("."),
                .headerSearchPath("include"),
                .define("CODEC2_VERSION_MAJOR", to: "1"),
                .define("CODEC2_VERSION_MINOR", to: "2"),
                .define("CODEC2_VERSION_PATCH", to: "0"),
                .define("CODEC2_VERSION", to: "\"1.2.0\""),
                .define("GIT_HASH", to: "\"None\""),
                .define("HAVE_STDLIB_H", to: "1"),
                .define("HAVE_STRING_H", to: "1"),
                .define("SIZEOF_INT", to: "4"),
            ],
            linkerSettings: [
                .linkedLibrary("m", .when(platforms: [.linux])),
            ]
        ),
        .target(
            name: "LXSTSwift",
            dependencies: [
                .product(name: "ReticulumSwift", package: "reticulum-swift-lib"),
                "COpus",
                "CCodec2",
            ],
            path: "Sources/LXSTSwift"
        ),
        .testTarget(
            name: "LXSTSwiftTests",
            dependencies: ["LXSTSwift"],
            path: "Tests/LXSTSwiftTests"
        ),
    ]
)
