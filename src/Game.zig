const std = @import("std");
const err = std.log.err;
const c = @import("sdl.zig");

const Timer = @import("Timer.zig");
const constant = @import("constant.zig");
const StateMachine = @import("StateMachine.zig");
const PlayState = @import("PlayState.zig");
const PauseState = @import("PauseState.zig");
const Self = @This();

fps_timer: Timer = undefined,
window: ?*c.SDL_Window = null,
renderer: ?*c.SDL_Renderer = null,
allocator: *std.mem.Allocator = undefined,
state_machine: StateMachine = undefined,

pub fn init(allocator: *std.mem.Allocator) !Self {
    if (c.SDL_Init(c.SDL_INIT_VIDEO) < 0) {
        err("Couldn't initialize SDL: {s}", .{c.SDL_GetError()});
        return error.ERROR_INIT_SDL;
    }

    var self = Self{
        .fps_timer = Timer.init(),
        .allocator = allocator,
    };

    self.window = c.SDL_CreateWindow(
        constant.GAME_NAME,
        c.SDL_WINDOWPOS_CENTERED,
        c.SDL_WINDOWPOS_CENTERED,
        constant.SCREEN_WIDTH,
        constant.SCREEN_HEIGHT,
        0,
    ) orelse {
        err("Error creating window. SDL Error: {s}", .{c.SDL_GetError()});
        return error.ERROR_CREATE_WINDOW;
    };

    self.renderer = c.SDL_CreateRenderer(self.window.?, -1, c.SDL_RENDERER_ACCELERATED) orelse {
        err("Error creating renderer. SDL Error: {s}", .{c.SDL_GetError()});
        return error.ERROR_CREATE_RENDERER;
    };

    self.state_machine = StateMachine.init(allocator);

    var play_state = try allocator.create(*PlayState);
    play_state.* = try PlayState.init(allocator, self.window.?, self.renderer.?, self.state_machine);

    try self.state_machine.changeState(&play_state.*.*.interface);

    return self;
}

pub fn loop(self: *Self) !void {
    while (true) {
        self.fps_timer.startTimer();

        try self.state_machine.input();
        try self.state_machine.update();
        try self.state_machine.render();

        const time_taken = @intToFloat(f64, self.fps_timer.getTicks());
        if (time_taken < constant.TICKS_PER_FRAME) {
            c.SDL_Delay(@floatToInt(u32, constant.TICKS_PER_FRAME - time_taken));
        }
    }
}

pub fn close(self: Self) void {
    c.SDL_DestroyWindow(self.window.?);
    c.SDL_DestroyRenderer(self.renderer.?);
}
