const std = @import("std");

/// !!! This build.zig only exposes some utilities, not ZML the ML framework !!!
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const test_step = b.step("test", "Run all tests across ZML and deps");
    const pure_zig_deps_step = b.step("check_zml_pure_zig_deps", "Compile ZML pure Zig dependencies");
    test_step.dependOn(pure_zig_deps_step);

    // stdx
    const stdx = b.addModule("stdx", .{
        .root_source_file = b.path("stdx/stdx.zig"),
        .target = target,
        .optimize = optimize,
    });

    const stdx_test = b.addTest(.{ .root_module = stdx });
    const run_stdx_tests = b.addRunArtifact(stdx_test);
    test_step.dependOn(&run_stdx_tests.step);

    // vfs
    const vfs = b.addModule("vfs", .{
        .root_source_file = b.path("vfs/vfs.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "stdx", .module = stdx }},
    });

    const vfs_test = b.addTest(.{ .root_module = vfs });
    const run_vfs_tests = b.addRunArtifact(vfs_test);
    test_step.dependOn(&run_vfs_tests.step);

    const vfs_example = b.addExecutable(.{
        .name = "vfs_example",
        .root_module = b.addModule("vfs_example", .{
            .root_source_file = b.path("vfs/example.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "vfs", .module = vfs },
            },
        }),
    });

    const run_vfs_example = b.addRunArtifact(vfs_example);
    if (b.args) |args| {
        run_vfs_example.addArgs(args);
    }
    const step_vfs_example = b.step("run_vfs_example", "Run VFS example");
    step_vfs_example.dependOn(&run_vfs_example.step);

    const protobuf = b.dependency("protobuf", .{
        .target = target,
        .optimize = optimize,
    });
    const xla = b.dependency("xla", .{});
    const rules_zig = b.dependency("rules_zig", .{});

    const ffi_c = addFfiCModule(b, target, optimize);
    const ffi = b.addModule("ffi", .{
        .root_source_file = b.path("ffi/ffi.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "c", .module = ffi_c },
        },
    });

    const bazel_builtin = b.addModule("bazel_builtin", .{
        .root_source_file = b.addWriteFiles().add("bazel_builtin.zig",
            \\pub const current_repository = "zml";
            \\
        ),
        .target = target,
        .optimize = optimize,
    });
    const runfiles = b.addModule("runfiles", .{
        .root_source_file = rules_zig.path("zig/runfiles/runfiles.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "bazel_builtin", .module = bazel_builtin },
        },
    });
    const bazel = b.addModule("bazel", .{
        .root_source_file = b.path("bazel/bazel.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "runfiles", .module = runfiles },
            .{ .name = "stdx", .module = stdx },
        },
    });
    const ffi_check = b.addTest(.{ .root_module = ffi });
    pure_zig_deps_step.dependOn(&ffi_check.step);
    const bazel_check = b.addLibrary(.{
        .name = "bazel_check",
        .root_module = bazel,
    });
    pure_zig_deps_step.dependOn(&bazel_check.step);

    const zml_proto = addZmlProtoLibrary(b, target, optimize, protobuf, xla);
    const upb = b.addModule("upb", .{
        .root_source_file = b.path("upb/upb.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "c", .module = zml_proto },
        },
    });
    const xspace_to_perfetto = b.addModule("tools/xspace_to_perfetto", .{
        .root_source_file = b.path("tools/xspace_to_perfetto/xspace_to_perfetto.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "c", .module = zml_proto },
            .{ .name = "upb", .module = upb },
        },
    });
    const xspace_to_perfetto_check = b.addTest(.{ .root_module = xspace_to_perfetto });
    pure_zig_deps_step.dependOn(&xspace_to_perfetto_check.step);

    const xla_proto_test = b.addTest(.{
        .root_module = b.addModule("test_xla_proto", .{
            .root_source_file = b.path("examples/xla_proto/test_xla_proto.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "upb", .module = upb },
                .{ .name = "c", .module = zml_proto },
            },
        }),
    });
    const run_xla_proto_test = b.addRunArtifact(xla_proto_test);
    const test_xla_proto_step = b.step("test_xla_proto", "Serialize an XLA data proto with UPB");
    test_xla_proto_step.dependOn(&run_xla_proto_test.step);
}

const c_flags = &.{};
const cxx_flags = &.{"-std=c++17"};

fn addFfiCModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    const write_files = b.addWriteFiles();
    const header = write_files.add("ffi.h",
        \\#include "zig_allocator.h"
        \\#include "zig_slice.h"
        \\
    );
    const translate = b.addTranslateC(.{
        .root_source_file = header,
        .target = target,
        .optimize = optimize,
    });
    translate.addIncludePath(b.path("ffi"));
    return translate.addModule("ffi_c");
}

fn addZmlProtoLibrary(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    protobuf: *std.Build.Dependency,
    xla: *std.Build.Dependency,
) *std.Build.Module {
    const protobuf_src = protobuf.builder.dependency("protobuf", .{});
    const abseil = protobuf.builder.dependency("abseil", .{
        .target = target,
        .optimize = optimize,
    });

    const protoc_gen_upb = addUpbProtocPlugin(b, .{
        .name = "protoc-gen-upb",
        .protobuf = protobuf,
        .protobuf_src = protobuf_src,
        .abseil = abseil,
        .target = target,
        .optimize = optimize,
        .c_sources = &.{},
        .cxx_sources = &.{
            "upb_generator/c/generator.cc",
            "upb_generator/c/names.cc",
            "upb_generator/c/names_internal.cc",
        },
    });
    const protoc_gen_upb_minitable = addUpbProtocPlugin(b, .{
        .name = "protoc-gen-upb_minitable",
        .protobuf = protobuf,
        .protobuf_src = protobuf_src,
        .abseil = abseil,
        .target = target,
        .optimize = optimize,
        .c_sources = &.{
            "upb/wire/decode_fast/select.c",
        },
        .cxx_sources = &.{
            "upb_generator/minitable/generator.cc",
            "upb_generator/minitable/main.cc",
        },
    });

    const proto_roots = [_]std.Build.LazyPath{
        xla.path("third_party/tsl"),
        xla.path(""),
        protobuf_src.path("src"),
    };
    const proto_files = [_]UpbProtoSource{
        .{ .file = protobuf_src.path("src/google/protobuf/any.proto"), .output_path = "google/protobuf/any.proto" },
        .{ .file = protobuf_src.path("src/google/protobuf/duration.proto"), .output_path = "google/protobuf/duration.proto" },
        .{ .file = protobuf_src.path("src/google/protobuf/timestamp.proto"), .output_path = "google/protobuf/timestamp.proto" },
        .{ .file = protobuf_src.path("src/google/protobuf/wrappers.proto"), .output_path = "google/protobuf/wrappers.proto" },
        .{ .file = xla.path("xla/xla_data.proto"), .output_path = "xla/xla_data.proto" },
        .{ .file = xla.path("xla/backends/autotuner/backends.proto"), .output_path = "xla/backends/autotuner/backends.proto" },
        .{ .file = xla.path("xla/tsl/protobuf/dnn.proto"), .output_path = "xla/tsl/protobuf/dnn.proto" },
        .{ .file = xla.path("xla/autotuning.proto"), .output_path = "xla/autotuning.proto" },
        .{ .file = xla.path("xla/autotune_results.proto"), .output_path = "xla/autotune_results.proto" },
        .{ .file = xla.path("xla/service/metrics.proto"), .output_path = "xla/service/metrics.proto" },
        .{ .file = xla.path("xla/service/hlo.proto"), .output_path = "xla/service/hlo.proto" },
        .{ .file = xla.path("xla/xla.proto"), .output_path = "xla/xla.proto" },
        .{ .file = xla.path("xla/stream_executor/cuda/cuda_compute_capability.proto"), .output_path = "xla/stream_executor/cuda/cuda_compute_capability.proto" },
        .{ .file = xla.path("xla/stream_executor/sycl/oneapi_compute_capability.proto"), .output_path = "xla/stream_executor/sycl/oneapi_compute_capability.proto" },
        .{ .file = xla.path("xla/stream_executor/device_description.proto"), .output_path = "xla/stream_executor/device_description.proto" },
        .{ .file = xla.path("xla/pjrt/proto/compile_options.proto"), .output_path = "xla/pjrt/proto/compile_options.proto" },
        .{ .file = xla.path("third_party/tsl/tsl/profiler/protobuf/profiler_options.proto"), .output_path = "tsl/profiler/protobuf/profiler_options.proto" },
        .{ .file = xla.path("third_party/tsl/tsl/profiler/protobuf/xplane.proto"), .output_path = "tsl/profiler/protobuf/xplane.proto" },
    };

    const generated = addUpbProtoGeneration(b, .{
        .protoc = protobuf.artifact("protoc"),
        .protoc_gen_upb = protoc_gen_upb,
        .protoc_gen_upb_minitable = protoc_gen_upb_minitable,
        .proto_roots = &proto_roots,
        .proto_files = &proto_files,
    });

    const zml_upb_protos_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    zml_upb_protos_mod.linkLibrary(protobuf.artifact("libupb"));
    addProtobufIncludePaths(zml_upb_protos_mod, protobuf_src);
    zml_upb_protos_mod.addIncludePath(generated.upb);
    zml_upb_protos_mod.addIncludePath(generated.minitable);
    for (proto_files) |proto_file| {
        zml_upb_protos_mod.addCSourceFile(.{
            .file = generated.minitable.path(b, protoGeneratedPath(b, proto_file.output_path, ".upb_minitable.c")),
            .flags = c_flags,
            .language = .c,
        });
        zml_upb_protos_mod.addCSourceFile(.{
            .file = generated.upb.path(b, protoGeneratedPath(b, proto_file.output_path, ".upb.c")),
            .flags = c_flags,
            .language = .c,
        });
    }
    const zml_upb_protos = b.addLibrary(.{
        .name = "zml_upb_protos",
        .root_module = zml_upb_protos_mod,
    });

    const write_files = b.addWriteFiles();
    const umbrella_header = write_files.add("zml_upb_protos.h",
        \\#include "xla/xla_data.upb.h"
        \\#include "xla/pjrt/proto/compile_options.upb.h"
        \\#include "tsl/profiler/protobuf/profiler_options.upb.h"
        \\#include "tsl/profiler/protobuf/xplane.upb.h"
        \\
    );
    const translate = b.addTranslateC(.{
        .root_source_file = umbrella_header,
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    addProtobufTranslateIncludePaths(translate, protobuf_src);
    translate.addIncludePath(generated.upb);
    translate.addIncludePath(generated.minitable);

    const module = translate.addModule("zml_proto");
    module.linkLibrary(zml_upb_protos);
    return module;
}

const UpbProtocPluginOptions = struct {
    name: []const u8,
    protobuf: *std.Build.Dependency,
    protobuf_src: *std.Build.Dependency,
    abseil: *std.Build.Dependency,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    c_sources: []const []const u8,
    cxx_sources: []const []const u8,
};

fn addUpbProtocPlugin(
    b: *std.Build,
    options: UpbProtocPluginOptions,
) *std.Build.Step.Compile {
    const mod = b.createModule(.{
        .target = options.target,
        .optimize = options.optimize,
        .link_libc = true,
        .link_libcpp = true,
    });
    mod.linkLibrary(options.protobuf.artifact("libprotoc"));
    mod.linkLibrary(options.protobuf.artifact("libprotobuf"));
    mod.linkLibrary(options.protobuf.artifact("libupb"));
    mod.linkLibrary(options.abseil.artifact("abseil"));
    addProtobufIncludePaths(mod, options.protobuf_src);

    if (options.c_sources.len > 0) {
        mod.addCSourceFiles(.{
            .root = options.protobuf_src.path(""),
            .files = options.c_sources,
            .flags = c_flags,
            .language = .c,
        });
    }
    if (options.cxx_sources.len > 0) {
        mod.addCSourceFiles(.{
            .root = options.protobuf_src.path(""),
            .files = options.cxx_sources,
            .flags = cxx_flags,
            .language = .cpp,
        });
    }

    return b.addExecutable(.{
        .name = options.name,
        .root_module = mod,
    });
}

const UpbProtoGenerationOptions = struct {
    protoc: *std.Build.Step.Compile,
    protoc_gen_upb: *std.Build.Step.Compile,
    protoc_gen_upb_minitable: *std.Build.Step.Compile,
    proto_roots: []const std.Build.LazyPath,
    proto_files: []const UpbProtoSource,
};

const UpbProtoSource = struct {
    file: std.Build.LazyPath,
    output_path: []const u8,
};

const UpbGeneratedProto = struct {
    upb: std.Build.LazyPath,
    minitable: std.Build.LazyPath,
};

fn addUpbProtoGeneration(
    b: *std.Build,
    options: UpbProtoGenerationOptions,
) UpbGeneratedProto {
    const upb = blk: {
        const run = b.addRunArtifact(options.protoc);
        run.setName("generate xla_data upb sources");
        run.addPrefixedArtifactArg("--plugin=protoc-gen-upb=", options.protoc_gen_upb);
        for (options.proto_roots) |proto_root| {
            run.addPrefixedDirectoryArg("--proto_path=", proto_root);
        }
        const generated = run.addPrefixedOutputDirectoryArg("--upb_out=", "xla-data-upb");
        for (options.proto_files) |proto_file| {
            run.addFileArg(proto_file.file);
        }
        break :blk generated;
    };

    const minitable = blk: {
        const run = b.addRunArtifact(options.protoc);
        run.setName("generate xla_data upb minitables");
        run.addPrefixedArtifactArg("--plugin=protoc-gen-upb_minitable=", options.protoc_gen_upb_minitable);
        for (options.proto_roots) |proto_root| {
            run.addPrefixedDirectoryArg("--proto_path=", proto_root);
        }
        const generated = run.addPrefixedOutputDirectoryArg("--upb_minitable_out=", "xla-data-upb-minitable");
        for (options.proto_files) |proto_file| {
            run.addFileArg(proto_file.file);
        }
        break :blk generated;
    };

    return .{
        .upb = upb,
        .minitable = minitable,
    };
}

fn protoGeneratedPath(b: *std.Build, proto_path: []const u8, suffix: []const u8) []const u8 {
    const extension = ".proto";
    if (!std.mem.endsWith(u8, proto_path, extension)) {
        @panic("UPB proto source paths must end in .proto");
    }
    return b.fmt("{s}{s}", .{ proto_path[0 .. proto_path.len - extension.len], suffix });
}

fn addProtobufIncludePaths(
    mod: *std.Build.Module,
    protobuf_src: *std.Build.Dependency,
) void {
    mod.addIncludePath(protobuf_src.path(""));
    mod.addIncludePath(protobuf_src.path("src"));
    mod.addIncludePath(protobuf_src.path("upb/reflection/cmake"));
    mod.addIncludePath(protobuf_src.path("third_party/utf8_range"));
}

fn addProtobufTranslateIncludePaths(
    translate: *std.Build.Step.TranslateC,
    protobuf_src: *std.Build.Dependency,
) void {
    translate.addIncludePath(protobuf_src.path(""));
    translate.addIncludePath(protobuf_src.path("src"));
    translate.addIncludePath(protobuf_src.path("upb/reflection/cmake"));
    translate.addIncludePath(protobuf_src.path("third_party/utf8_range"));
}
