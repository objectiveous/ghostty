const Manual = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const renderer = @import("../renderer.zig");
const terminal = @import("../terminal/main.zig");
const termio = @import("../termio.zig");

pub const Config = struct {
    userdata: ?*anyopaque = null,
    write: *const fn (?*anyopaque, [*]const u8, usize) callconv(.c) void,
    resize: ?*const fn (?*anyopaque, u16, u16, u32, u32) callconv(.c) void = null,
    focus: ?*const fn (?*anyopaque, bool) callconv(.c) void = null,
};

config: Config,

pub fn init(_: Allocator, cfg: Config) !Manual {
    return .{ .config = cfg };
}

pub fn deinit(self: *Manual) void {
    self.* = undefined;
}

pub fn initTerminal(_: *Manual, _: *terminal.Terminal) void {}

pub fn threadEnter(
    self: *Manual,
    _: Allocator,
    _: *termio.Termio,
    td: *termio.Termio.ThreadData,
) !void {
    td.backend = .{ .manual = .{ .config = self.config } };
}

pub fn threadExit(_: *Manual, _: *termio.Termio.ThreadData) void {}

pub fn focusGained(
    self: *Manual,
    _: *termio.Termio.ThreadData,
    focused: bool,
) !void {
    if (self.config.focus) |focus| {
        focus(self.config.userdata, focused);
    }
}

pub fn resize(
    self: *Manual,
    grid_size: renderer.GridSize,
    screen_size: renderer.ScreenSize,
) !void {
    if (self.config.resize) |resize_cb| {
        resize_cb(
            self.config.userdata,
            @intCast(grid_size.columns),
            @intCast(grid_size.rows),
            screen_size.width,
            screen_size.height,
        );
    }
}

pub fn queueWrite(
    self: *Manual,
    alloc: Allocator,
    _: *termio.Termio.ThreadData,
    data: []const u8,
    linefeed: bool,
) !void {
    if (!linefeed) {
        self.config.write(self.config.userdata, data.ptr, data.len);
        return;
    }

    const expanded = try expandLinefeed(alloc, data);
    defer alloc.free(expanded);
    self.config.write(self.config.userdata, expanded.ptr, expanded.len);
}

pub fn childExitedAbnormally(
    _: *Manual,
    _: Allocator,
    _: *terminal.Terminal,
    _: u32,
    _: u64,
) !void {}

fn expandLinefeed(alloc: Allocator, data: []const u8) ![]u8 {
    var expanded: std.ArrayList(u8) = .empty;
    errdefer expanded.deinit(alloc);

    for (data) |byte| {
        try expanded.append(alloc, byte);
        if (byte == '\r') {
            try expanded.append(alloc, '\n');
        }
    }

    return expanded.toOwnedSlice(alloc);
}

pub const ThreadData = struct {
    config: Config,

    pub fn deinit(self: *ThreadData, _: Allocator) void {
        self.* = undefined;
    }
};
