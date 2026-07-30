const std = @import("std");

/// !!! This build.zig only exposes some utilities, not ZML the ML framework !!!
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const test_step = b.step("test", "Run all tests across ZML and deps");

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

    const xla_data_proto = addXlaDataProto(b, target, optimize, protobuf);
    const upb = b.addModule("upb", .{
        .root_source_file = b.path("upb/upb.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "c", .module = xla_data_proto },
        },
    });

    const xla_proto_test = b.addTest(.{
        .root_module = b.addModule("test_xla_proto", .{
            .root_source_file = b.path("examples/xla_proto/test_xla_proto.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "upb", .module = upb },
                .{ .name = "xla_data_proto", .module = xla_data_proto },
            },
        }),
    });
    const run_xla_proto_test = b.addRunArtifact(xla_proto_test);
    const test_xla_proto_step = b.step("test_xla_proto", "Serialize an XLA data proto with UPB");
    test_xla_proto_step.dependOn(&run_xla_proto_test.step);
}

const c_flags = &.{};
const cxx_flags = &.{"-std=c++17"};

fn addXlaDataProto(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    protobuf: *std.Build.Dependency,
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

    const generated = addUpbProtoGeneration(b, .{
        .protoc = protobuf.artifact("protoc"),
        .protoc_gen_upb = protoc_gen_upb,
        .protoc_gen_upb_minitable = protoc_gen_upb_minitable,
        .proto_root = b.path("third_party/xla/protos"),
        .proto_file = b.path("third_party/xla/protos/xla/xla_data.proto"),
    });

    const xla_data_upb_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    xla_data_upb_mod.linkLibrary(protobuf.artifact("libupb"));
    addProtobufIncludePaths(xla_data_upb_mod, protobuf_src);
    xla_data_upb_mod.addIncludePath(generated.upb);
    xla_data_upb_mod.addIncludePath(generated.minitable);
    xla_data_upb_mod.addCSourceFile(.{
        .file = generated.minitable.path(b, "xla/xla_data.upb_minitable.c"),
        .flags = c_flags,
        .language = .c,
    });
    xla_data_upb_mod.addCSourceFile(.{
        .file = generated.upb.path(b, "xla/xla_data.upb.c"),
        .flags = c_flags,
        .language = .c,
    });
    const xla_data_upb = b.addLibrary(.{
        .name = "xla_data_upb",
        .root_module = xla_data_upb_mod,
    });

    const translate = b.addTranslateC(.{
        .root_source_file = generated.upb.path(b, "xla/xla_data.upb.h"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    addProtobufTranslateIncludePaths(translate, protobuf_src);
    translate.addIncludePath(generated.upb);
    translate.addIncludePath(generated.minitable);

    const module = translate.addModule("xla_data_proto");
    module.linkLibrary(xla_data_upb);
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
    proto_root: std.Build.LazyPath,
    proto_file: std.Build.LazyPath,
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
        run.addPrefixedDirectoryArg("--proto_path=", options.proto_root);
        const generated = run.addPrefixedOutputDirectoryArg("--upb_out=", "xla-data-upb");
        run.addFileArg(options.proto_file);
        break :blk generated;
    };

    const minitable = blk: {
        const run = b.addRunArtifact(options.protoc);
        run.setName("generate xla_data upb minitables");
        run.addPrefixedArtifactArg("--plugin=protoc-gen-upb_minitable=", options.protoc_gen_upb_minitable);
        run.addPrefixedDirectoryArg("--proto_path=", options.proto_root);
        const generated = run.addPrefixedOutputDirectoryArg("--upb_minitable_out=", "xla-data-upb-minitable");
        run.addFileArg(options.proto_file);
        break :blk generated;
    };

    return .{
        .upb = upb,
        .minitable = minitable,
    };
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
