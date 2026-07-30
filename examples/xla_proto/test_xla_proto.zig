const std = @import("std");
const upb = @import("upb");
const c = @import("xla_data_proto");

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
