const mb = @import("moon-base");
const Lua = mb.Lua;
const std = @import("std");

pub const Color = struct {
    rgba: [4]u8,

    pub fn format(color: Color, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("#{x:0>2}{x:0>2}{x:0>2}{x:0>2}", .{
            color.rgba[0],
            color.rgba[1],
            color.rgba[2],
            color.rgba[3],
        });
    }

    pub fn push(color: Color, l: *Lua) c_int {
        const ptr = l.newUserdata(Color, 0);
        ptr.* = color;
        l.setMetatableRegistry("Color");
        return 1;
    }

    pub fn pull(l: *Lua, arg: i32) *Color {
        return l.toUserdata(Color, arg) catch {
            l.argExpected(false, arg, "Color");
            unreachable;
        };
    }

    pub fn fromHex(hex: HexColor) Color {
        const parse = std.fmt.parseInt;
        errdefer unreachable;
        return switch (hex.str) {
            inline else => |str, kind| .{
                .rgba = .{
                    try parse(u8, str[1..3], 16),
                    try parse(u8, str[3..5], 16),
                    try parse(u8, str[5..7], 16),
                    if (kind == .with_alpha) try parse(u8, str[7..9], 16) else 0xff,
                },
            },
        };
    }

    pub fn __add(self: *Color, other: *Color) Color {
        var rgba: [4]u8 = undefined;
        for (&rgba, self.rgba, other.rgba) |*out, a, b| out.* = a +| b;
        return .{ .rgba = rgba };
    }
};

pub const HexColor = struct {
    str: union(enum) {
        with_alpha: *const [9]u8,
        without: *const [7]u8,
    },

    pub fn pull(l: *Lua, arg: i32) HexColor {
        const string = l.checkString(arg);
        l.argCheck((string.len == 7 or string.len == 9) and string[0] == '#', arg, "hexadecimal color string expected!");
        for (string[1..], 1..) |byte, index| switch (byte) {
            '0'...'9', 'a'...'f', 'A'...'F' => {},
            else => l.argError(arg, l.pushFString("invalid character '%c' at index %d", .{ byte, index })),
        };
        return .{
            .str = if (string.len == 9)
                .{ .with_alpha = string[0..9] }
            else
                .{ .without = string[0..7] },
        };
    }
};

comptime {
    mb.Userdata(Color, "Color");
}
