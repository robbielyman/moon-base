//! By convention, root.zig is the root source file when making a library. If
//! you are making an executable, the convention is to delete this file and
//! start with main.zig instead.
pub const zlua = @import("zlua");
pub const Lua = zlua.Lua;
const std = @import("std");
const testing = std.testing;

pub const LuaBuffer = struct {
    const vtable: std.io.Writer.VTable = .{
        .drain = drain,
    };

    fn drain(w: *std.io.Writer, data: []const []const u8, splat: usize) error{WriteFailed}!usize {
        var ret = w.end;
        const lb: *LuaBuffer = @fieldParentPtr("interface", w);
        lb.buffer.addString(w.buffer[0..w.end]);
        w.end = 0;
        for (0..data.len - 1) |i| {
            const chunk = data[i];
            lb.buffer.addString(chunk);
            ret += chunk.len;
        }
        for (0..splat) |_| {
            const chunk = data[data.len - 1];
            lb.buffer.addString(chunk);
            ret += chunk.len;
        }
        return ret;
    }
    interface: std.io.Writer,
    buffer: zlua.Buffer,
    arr: [1024]u8,

    pub fn init(lb: *LuaBuffer, l: *Lua) void {
        lb.* = .{
            .buffer = undefined,
            .arr = undefined,
            .interface = .{
                .buffer = &lb.arr,
                .end = 0,
                .vtable = &vtable,
            },
        };
        lb.buffer.init(l);
    }

    pub fn push(lb: *LuaBuffer) void {
        lb.interface.flush() catch unreachable;
        lb.buffer.pushResult();
    }
};

/// this function is tasked with producing a valid object of type T
/// from the argument at the given lua index
/// in case of failure, a lua error will be raised
/// when T is a user-defined Zig type, (or a pointer to such) T must have a decl named "pull"
/// of signature `fn (*Lua, index) T` (or `fn (*Lua, index) *T`)
/// which either assembles a value of type T (or `*T`) with its invariants intact
/// or raises a lua error.
pub fn pull(l: *Lua, arg: i32, comptime T: type) T {
    return switch (@typeInfo(T)) {
        .bool => l.toBoolean(arg),
        .int => std.math.cast(T, l.checkInteger(arg)) orelse
            l.argError(arg, "does not fit in a value of type " ++ @typeName(T) ++ "!"),
        .float => @floatCast(l.checkNumber(arg)),
        .@"enum", .@"struct", .@"union", .@"opaque" => T.pull(l, arg),
        .optional => |info| if (l.isNil(arg)) null else pull(l, arg, info.child),
        .pointer => |info| if (info.child == u8 and info.is_const)
            l.checkString(arg)
        else
            info.child.pull(l, arg),
        else => {
            @compileLog(T);
            @compileError("unsupported type passed to pull!");
        },
    };
}

/// this function is tasked with pushing the return value of a Zig function
/// onto the Lua stack and returning the number of values pushed.
/// in the case that value is an error,
/// err_handler is called on it, otherwise err_handler is ignored.
/// err_handler, when necessary, should have type `fn(*Lua, anyerror) noreturn`
/// when @TypeOf(value) is a user-defined Zig type T (or *T),
/// T must have a decl named "push" of signature `fn (T, *Lua) c_int`
/// (or `fn (*T, *Lua) c_int)`) which performs the push.
/// when T is a tuple, each field will be pushed in sequence.
pub fn pushReturn(l: *Lua, value: anytype, comptime err_handler: anytype) c_int {
    return num: switch (@typeInfo(@TypeOf(value))) {
        .void => 0,
        .bool => {
            l.pushBoolean(value);
            break :num 1;
        },
        .int => {
            l.pushInteger(std.math.cast(c_longlong, value) orelse
                l.raiseErrorStr("value %d does not fit in a Lua integer!", .{value}));
            break :num 1;
        },
        .float => {
            l.pushNumber(@floatCast(value));
            break :num 1;
        },
        .@"enum", .@"struct", .@"union", .@"opaque" => @TypeOf(value).push(value, l),
        .optional => if (value) |inner|
            pushReturn(l, inner, err_handler)
        else nil: {
            l.pushNil();
            break :nil 1;
        },
        .pointer => |info| if (info.child == u8) str: {
            l.pushString(value);
            break :str 1;
        } else info.child.push(value, l),
        .error_union => {
            const inner = value catch |err| {
                @call(.always_inline, err_handler, .{ l, err });
                unreachable;
            };
            break :num pushReturn(l, inner, err_handler);
        },
        else => {
            @compileLog(@TypeOf(value));
            @compileError("unsupported type!");
        },
    };
}

pub fn function(comptime zig_function: anytype, comptime err_handler: anytype) zlua.CFn {
    return struct {
        fn call(l: ?*zlua.LuaState) callconv(.c) c_int {
            const lua: *Lua = @ptrCast(l.?);
            const info = @typeInfo(@TypeOf(zig_function)).@"fn";
            const Tuple = std.meta.ArgsTuple(@TypeOf(zig_function));
            var args: Tuple = undefined;
            inline for (info.params, 0..) |param, arg| {
                args[arg] = pull(lua, @intCast(arg + 1), param.type.?);
            }
            return pushReturn(
                lua,
                @call(.always_inline, zig_function, args),
                err_handler,
            );
        }
    }.call;
}

const skipped: std.StaticStringMap(void) = .initComptime(.{
    .{ "__err", {} },
    .{ "__open", {} },
    .{ "push", {} },
    .{ "pull", {} },
    .{ "format", {} },
});

pub fn Functions(comptime T: type) []const zlua.FnReg {
    const decls = comptime std.meta.declarations(T);
    const err_handler = if (@hasDecl(T, "__err")) T.__err else {};
    return comptime reg: {
        var ret: []const zlua.FnReg = &.{};
        var has_fmt = false;
        for (decls) |decl| {
            const name = decl.name;
            if (std.mem.eql(u8, name, "format")) has_fmt = true;
            const skip = skipped.get(name) != null;
            if (!skip and @typeInfo(@TypeOf(@field(T, name))) == .@"fn") {
                const reg: zlua.FnReg = .{
                    .func = function(@field(T, name), err_handler),
                    .name = name,
                };
                ret = ret ++ .{reg};
            }
        }
        if (has_fmt) {
            const reg: zlua.FnReg = .{
                .func = struct {
                    fn __tostring(l: ?*zlua.LuaState) callconv(.c) c_int {
                        const lua: *Lua = @ptrCast(l.?);
                        const val = T.pull(lua, 1);
                        var w: LuaBuffer = undefined;
                        w.init(lua);
                        errdefer unreachable;
                        try w.interface.print("{f}", .{val});
                        w.push();
                        return 1;
                    }
                }.__tostring,
                .name = "__tostring",
            };
            ret = ret ++ .{reg};
        }
        const fns = ret;
        break :reg fns;
    };
}

pub fn Userdata(comptime U: type, comptime name: [:0]const u8) void {
    const Closure = struct {
        fn open(l: ?*zlua.LuaState) callconv(.c) c_int {
            const lua: *Lua = @ptrCast(l.?);
            blk: {
                lua.newMetatable(name) catch break :blk;
                const upvalues = if (@hasDecl(U, "__open")) U.__open(lua) else 0;
                const funcs = Functions(U);
                lua.setFuncs(funcs, upvalues);
            }
            return 1;
        }
    };

    @export(&Closure.open, .{ .linkage = .strong, .name = "luaopen_" ++ name });
}
