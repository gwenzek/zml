const std = @import("std");

const stdx = @import("stdx");
const zml_tokenizer = @import("zml/tokenizer");

const log = std.log.scoped(.@"//zml/tokenizer");

const Flags = struct {
    tokenizer: []const u8,
    prompt: ?[]const u8 = null,
    expected: []const u8 = "",
    verbose: bool = false,
};

fn writeEscaped(writer: *std.Io.Writer, text: []const u8) !void {
    for (text) |byte| {
        switch (byte) {
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            '\\' => try writer.writeAll("\\\\"),
            0x20...0x5b, 0x5d...0x7e => try writer.writeByte(byte),
            else => try writer.print("\\x{X:0>2}", .{byte}),
        }
    }
}

fn readStdinAlloc(allocator: std.mem.Allocator, io: std.Io) ![]u8 {
    var stdin_buf: [4096]u8 = undefined;
    var stdin = std.Io.File.stdin().reader(io, &stdin_buf);
    var input: std.ArrayList(u8) = .empty;
    errdefer input.deinit(allocator);

    var chunk: [4096]u8 = undefined;
    while (true) {
        const n = try stdin.interface.readSliceShort(&chunk);
        if (n == 0) break;
        try input.appendSlice(allocator, chunk[0..n]);
        if (n < chunk.len) break;
    }

    return input.toOwnedSlice(allocator);
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();

    const io = threaded.io();

    const args = stdx.flags.parseProcessArgs(init.minimal, Flags);
    const prompt = if (args.prompt) |p| p else try readStdinAlloc(allocator, io);
    defer if (args.prompt == null) allocator.free(prompt);

    log.info("\tLoading tokenizer from {s}", .{args.tokenizer});
    var tokenizer = try zml_tokenizer.Tokenizer.fromFile(allocator, io, args.tokenizer);
    log.info("✅\tLoaded tokenizer from {s}", .{args.tokenizer});
    defer tokenizer.deinit();

    var encoder = try tokenizer.encoder();
    defer encoder.deinit();

    var decoder = try tokenizer.decoder();
    defer decoder.deinit();

    const prompt_tok = try encoder.encodeAlloc(allocator, prompt);
    defer allocator.free(prompt_tok);

    var stdout_buf: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(io, &stdout_buf);
    var token_buf: [4096]u8 = undefined;
    for (prompt_tok) |token_id| {
        const token_text = try decoder.feedOne(token_id, &token_buf);
        try stdout.interface.print("{} ", .{token_id});
        try writeEscaped(&stdout.interface, token_text);
        try stdout.interface.writeByte('\n');
    }
    const final_text = try decoder.finalize(&token_buf);
    if (final_text.len > 0 and prompt_tok.len > 0) {
        try stdout.interface.print("{} ", .{prompt_tok[prompt_tok.len - 1]});
        try writeEscaped(&stdout.interface, final_text);
        try stdout.interface.writeByte('\n');
    }
    try stdout.flush();

    var errors: u8 = 0;
    {
        var check_decoder = try tokenizer.decoder();
        defer check_decoder.deinit();
        var reconstructed = try check_decoder.decodeAlloc(allocator, prompt_tok);
        defer reconstructed.deinit(allocator);
        if (!std.mem.eql(u8, prompt, reconstructed.items)) {
            log.err("Reconstructed string from tokens doesn't match source: {s}", .{reconstructed.items});
            errors += 1;
        }
    }

    if (args.expected.len > 0) {
        var expected: std.ArrayList(u32) = try .initCapacity(allocator, prompt.len);
        var it = std.mem.splitSequence(u8, args.expected, ",");
        while (it.next()) |int_token| {
            const tok = try std.fmt.parseInt(u32, int_token, 10);
            try expected.append(allocator, tok);
        }
        if (!std.mem.eql(u32, expected.items, prompt_tok)) {
            log.err("Doesn't match expected: {any}", .{expected.items});
            errors += 1;
        }
    }

    if (errors == 0) log.info("All good !", .{});

    std.process.exit(errors);
}
