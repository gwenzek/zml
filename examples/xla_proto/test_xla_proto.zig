const std = @import("std");
const upb = @import("upb");
const c = @import("c");

test "serialize an xla LiteralProto with upb" {
    var upb_alloc: upb.Allocator = .init(std.testing.allocator);
    const arena = c.upb_Arena_Init(null, 0, upb_alloc.inner());
    defer c.upb_Arena_Free(arena);

    const literal = try upb.new(c.xla_LiteralProto, arena);
    const shape = c.xla_LiteralProto_mutable_shape(literal, arena);
    try std.testing.expect(shape != null);

    c.xla_ShapeProto_set_element_type(shape, c.xla_F32);
    try std.testing.expect(c.xla_ShapeProto_add_dimensions(shape, 1, arena));
    try std.testing.expect(c.xla_ShapeProto_add_dimensions(shape, 2, arena));
    try std.testing.expect(c.xla_LiteralProto_add_f32s(literal, 1.25, arena));
    try std.testing.expect(c.xla_LiteralProto_add_f32s(literal, 2.5, arena));

    const serialized = try upb.serialize(literal, arena);
    try std.testing.expect(serialized.len > 0);

    const parsed = try upb.parse(c.xla_LiteralProto, arena, serialized);
    const parsed_shape = c.xla_LiteralProto_shape(parsed);
    try std.testing.expect(parsed_shape != null);
    try std.testing.expectEqual(@as(i32, c.xla_F32), c.xla_ShapeProto_element_type(parsed_shape));

    var dim_count: usize = 0;
    const dims_ptr = c.xla_ShapeProto_dimensions(parsed_shape, &dim_count);
    try std.testing.expectEqual(@as(usize, 2), dim_count);
    try std.testing.expectEqual(@as(i64, 1), dims_ptr[0]);
    try std.testing.expectEqual(@as(i64, 2), dims_ptr[1]);

    var value_count: usize = 0;
    const values_ptr = c.xla_LiteralProto_f32s(parsed, &value_count);
    try std.testing.expectEqual(@as(usize, 2), value_count);
    try std.testing.expectEqual(@as(f32, 1.25), values_ptr[0]);
    try std.testing.expectEqual(@as(f32, 2.5), values_ptr[1]);
}

test "serialize an xla CompileOptionsProto with upb" {
    var upb_alloc: upb.Allocator = .init(std.testing.allocator);
    const arena = c.upb_Arena_Init(null, 0, upb_alloc.inner());
    defer c.upb_Arena_Free(arena);

    const options = try upb.new(c.xla_CompileOptionsProto, arena);
    const executable_build_options = try upb.new(c.xla_ExecutableBuildOptionsProto, arena);
    c.xla_ExecutableBuildOptionsProto_set_num_replicas(executable_build_options, 2);
    c.xla_ExecutableBuildOptionsProto_set_num_partitions(executable_build_options, 4);
    c.xla_ExecutableBuildOptionsProto_set_use_spmd_partitioning(executable_build_options, true);
    c.xla_CompileOptionsProto_set_executable_build_options(options, executable_build_options);

    const serialized = try upb.serialize(options, arena);
    try std.testing.expect(serialized.len > 0);

    const parsed = try upb.parse(c.xla_CompileOptionsProto, arena, serialized);
    const parsed_executable_build_options = c.xla_CompileOptionsProto_executable_build_options(parsed);
    try std.testing.expect(parsed_executable_build_options != null);
    try std.testing.expectEqual(@as(i64, 2), c.xla_ExecutableBuildOptionsProto_num_replicas(parsed_executable_build_options));
    try std.testing.expectEqual(@as(i64, 4), c.xla_ExecutableBuildOptionsProto_num_partitions(parsed_executable_build_options));
    try std.testing.expect(c.xla_ExecutableBuildOptionsProto_use_spmd_partitioning(parsed_executable_build_options));
}

test "serialize tensorflow ProfileOptions with upb" {
    var upb_alloc: upb.Allocator = .init(std.testing.allocator);
    const arena = c.upb_Arena_Init(null, 0, upb_alloc.inner());
    defer c.upb_Arena_Free(arena);

    const options = try upb.new(c.tensorflow_ProfileOptions, arena);
    c.tensorflow_ProfileOptions_set_version(options, 1);
    c.tensorflow_ProfileOptions_set_device_type(options, c.tensorflow_ProfileOptions_CPU);
    c.tensorflow_ProfileOptions_set_repository_path(options, upb.stringView("/tmp/zml-profiler"));

    const serialized = try upb.serialize(options, arena);
    try std.testing.expect(serialized.len > 0);

    const parsed = try upb.parse(c.tensorflow_ProfileOptions, arena, serialized);
    try std.testing.expectEqual(@as(u32, 1), c.tensorflow_ProfileOptions_version(parsed));
    try std.testing.expectEqual(@as(i32, c.tensorflow_ProfileOptions_CPU), c.tensorflow_ProfileOptions_device_type(parsed));
    try std.testing.expectEqualStrings("/tmp/zml-profiler", upb.slice(c.tensorflow_ProfileOptions_repository_path(parsed)).?);
}

test "serialize tensorflow profiler XSpace with upb" {
    var upb_alloc: upb.Allocator = .init(std.testing.allocator);
    const arena = c.upb_Arena_Init(null, 0, upb_alloc.inner());
    defer c.upb_Arena_Free(arena);

    const xspace = try upb.new(c.tensorflow_profiler_XSpace, arena);
    try std.testing.expect(c.tensorflow_profiler_XSpace_add_hostnames(xspace, upb.stringView("localhost"), arena));
    try std.testing.expect(c.tensorflow_profiler_XSpace_add_warnings(xspace, upb.stringView("test-warning"), arena));

    const serialized = try upb.serialize(xspace, arena);
    try std.testing.expect(serialized.len > 0);

    const parsed = try upb.parse(c.tensorflow_profiler_XSpace, arena, serialized);

    var hostname_count: usize = 0;
    const hostnames_ptr = c.tensorflow_profiler_XSpace_hostnames(parsed, &hostname_count);
    try std.testing.expectEqual(@as(usize, 1), hostname_count);
    try std.testing.expectEqualStrings("localhost", upb.slice(hostnames_ptr[0]).?);

    var warning_count: usize = 0;
    const warnings_ptr = c.tensorflow_profiler_XSpace_warnings(parsed, &warning_count);
    try std.testing.expectEqual(@as(usize, 1), warning_count);
    try std.testing.expectEqualStrings("test-warning", upb.slice(warnings_ptr[0]).?);
}
