const std = @import("std");
const zlua = @import("zlua");
const Lua = zlua.Lua;

pub fn main() !void {
    var dba: std.heap.DebugAllocator(.{}) = .init;
    defer _ = dba.deinit();
    const gpa = dba.allocator();

    const lua: *Lua = try .init(gpa);
    defer lua.deinit();

    lua.openLibs();

    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    if (args.len < 2) fail("no filename provided");
    lua.doFile(args[1]) catch {
        std.debug.panic("{s}\n", .{lua.toStringEx(lua.getTop())});
    };
}

fn fail(msg: []const u8) noreturn {
    std.debug.print("{s}\n", .{msg});
    std.process.exit(1);
}
