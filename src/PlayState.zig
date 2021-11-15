const std = @import("std");
const err = std.log.err;
const c = @import("sdl.zig");

const Timer = @import("Timer.zig");
const Board = @import("Board.zig");
const Piece = @import("Piece.zig");
const BitmapFont = @import("BitmapFont.zig");
const Texture = @import("Texture.zig");
const constant = @import("constant.zig");
const StateInterfce = @import("interface.zig").StateInterface;
const Statemachine = @import("StateMachine.zig");
const PauseState = @import("PauseState.zig");
const GameOverState = @import("GameOverState.zig");

const Entity = enum { Board, Piece };
const Element = struct { typ: Entity, obj: *const c_void };
const Self = @This();

const left_viewport: c.SDL_Rect = .{
    .x = 0,
    .y = 0,
    .w = constant.BLOCK * 12,
    .h = constant.SCREEN_HEIGHT,
};

const play_viewport: c.SDL_Rect = .{
    .x = constant.BLOCK,
    .y = constant.BLOCK,
    .w = constant.BLOCK * 10,
    .h = constant.BLOCK * constant.ROW,
};

const right_viewport: c.SDL_Rect = .{
    .x = constant.BLOCK * 12,
    .y = 0,
    .w = constant.BLOCK * 7,
    .h = constant.SCREEN_HEIGHT,
};

const level_viewport: c.SDL_Rect = .{
    .x = constant.BLOCK * 12,
    .y = constant.BLOCK,
    .w = constant.VIEWPORT_INFO_WIDTH,
    .h = constant.VIEWPORT_INFO_HEIGHT,
};

const score_viewport: c.SDL_Rect = .{
    .x = constant.BLOCK * 12,
    .y = constant.BLOCK * 8,
    .w = constant.VIEWPORT_INFO_WIDTH,
    .h = constant.VIEWPORT_INFO_HEIGHT,
};

const tetromino_viewport: c.SDL_Rect = .{
    .x = constant.BLOCK * 12,
    .y = constant.BLOCK * 15,
    .w = constant.VIEWPORT_INFO_WIDTH,
    .h = constant.VIEWPORT_INFO_HEIGHT,
};

level: u8 = 1,
score: u32 = 0,
cap_timer: Timer = undefined,
window: *c.SDL_Window = null,
elements: [2]Element = undefined,
renderer: *c.SDL_Renderer = null,
allocator: *std.mem.Allocator = undefined,
bitmap_font: BitmapFont = undefined,
interface: StateInterfce = undefined,
state_machine: *Statemachine = undefined,

pub fn init(allocator: *std.mem.Allocator, window: *c.SDL_Window, renderer: *c.SDL_Renderer, state_machine: *Statemachine) !*Self {
    var self = try allocator.create(Self);

    self.* = Self{
        .allocator = allocator,
        .window = window,
        .renderer = renderer,
        .bitmap_font = BitmapFont.init(),
        .cap_timer = Timer.init(),
        .interface = StateInterfce.init(updateFn, renderFn, onEnterFn, onExitFn, inputFn, stateIDFn),
        .state_machine = state_machine,
    };

    var ptr_font_texture = try allocator.create(Texture);
    ptr_font_texture.* = Texture.init(self.window, self.renderer);

    try ptr_font_texture.loadFromFile("res/font.bmp");
    try self.bitmap_font.buildFont(ptr_font_texture);

    var ptr_board = try allocator.create(Board);
    ptr_board.* = Board.init(self.renderer); // need to do this, so Board is allocated on the Heap

    var ptr_piece = try allocator.create(Piece);
    ptr_piece.* = try Piece.randomPiece(self.renderer, ptr_board, &self.score); // need to do this, so Board is allocated on the Heap

    self.elements = .{
        // .{ .typ = .Board, .obj = &Board.init(self.renderer.?) }, // not working, cause this allocated Board on the Stack
        // .{ .typ = .Piece, .obj = &try Piece.randomPiece(self.renderer.?, aBoard) }, // not working, cause this allocated Piece on the Stack
        .{ .typ = .Board, .obj = ptr_board },
        .{ .typ = .Piece, .obj = ptr_piece },
    };

    return self;
}

fn inputFn(child: *StateInterfce) !void {
    var self = @fieldParentPtr(Self, "interface", child);
    var evt: c.SDL_Event = undefined;

    var piece = for (self.elements) |elem| {
        if (elem.typ == .Piece) {
            break @intToPtr(*Piece, @ptrToInt(elem.obj));
        }
    } else unreachable;

    while (c.SDL_PollEvent(&evt) > 0) {
        switch (evt.type) {
            c.SDL_QUIT => {
                std.os.exit(0);
            },

            c.SDL_KEYDOWN => switch (evt.key.keysym.sym) {
                c.SDLK_ESCAPE => {
                    var pause_state = try self.allocator.create(*PauseState);
                    pause_state.* = try PauseState.init(self.allocator, self.window, self.renderer, self.state_machine);
                    try self.state_machine.pushState(&pause_state.*.*.interface);
                },
                c.SDLK_UP => {
                    if (evt.key.repeat == 0) {
                        piece.rotate();
                    }
                },
                c.SDLK_DOWN => {
                    if ((try piece.moveDown()) == false) {
                        std.os.exit(0);
                    }
                },
                c.SDLK_LEFT => piece.moveLeft(),
                c.SDLK_RIGHT => piece.moveRight(),
                else => {},
            },
            else => {},
        }
    }
}

fn updateFn(child: *StateInterfce) !void {
    var self = @fieldParentPtr(Self, "interface", child);

    var p = for (self.elements) |elem| {
        if (elem.typ == .Piece) {
            break @intToPtr(*Piece, @ptrToInt(elem.obj));
        }
    } else unreachable;

    const elapsed_time = self.cap_timer.getTicks();
    if (elapsed_time >= 1000) {
        if ((try p.moveDown()) == false) {
            var game_over_state = try self.allocator.create(*GameOverState);
            game_over_state.* = try GameOverState.init(self.allocator, self.window, self.renderer, self.state_machine);
            try self.state_machine.changeState(&game_over_state.*.*.interface);
        }

        self.cap_timer.startTimer();
    }
}

fn renderFn(child: *StateInterfce) !void {
    var self = @fieldParentPtr(Self, "interface", child);
    _ = c.SDL_SetRenderDrawColor(self.renderer, 0x00, 0x00, 0x00, 0x00);
    _ = c.SDL_RenderClear(self.renderer);

    // Left viewport
    _ = c.SDL_RenderSetViewport(self.renderer, &Self.left_viewport);
    _ = c.SDL_SetRenderDrawColor(self.renderer, 0x00, 0x00, 0x00, 0x00);
    _ = c.SDL_RenderFillRect(self.renderer, &.{ .x = 0, .y = 0, .w = 360, .h = constant.SCREEN_HEIGHT });

    // Play viewport
    _ = c.SDL_RenderSetViewport(self.renderer, &Self.play_viewport);
    _ = c.SDL_SetRenderDrawColor(self.renderer, 0x00, 0xFF, 0x00, 0xFF);
    _ = c.SDL_RenderDrawRect(self.renderer, &.{
        .x = 0,
        .y = 0,
        .w = 300,
        .h = constant.SCREEN_HEIGHT - constant.BLOCK * 2,
    });

    for (self.elements) |e| {
        var obj_interface = switch (e.typ) {
            .Board => &(@intToPtr(*Board, @ptrToInt(e.obj))).interface,
            .Piece => &(@intToPtr(*Piece, @ptrToInt(e.obj))).interface,
        };

        obj_interface.draw(Piece.View.PlayViewport);
    }

    // Right viewport
    _ = c.SDL_RenderSetViewport(self.renderer, &Self.right_viewport);
    _ = c.SDL_SetRenderDrawColor(self.renderer, 0x00, 0x00, 0x00, 0xFF);
    _ = c.SDL_RenderFillRect(self.renderer, &.{ .x = 0, .y = 0, .w = constant.BLOCK * 6, .h = constant.SCREEN_HEIGHT });

    // Level viewport
    _ = c.SDL_RenderSetViewport(self.renderer, &Self.level_viewport);
    _ = c.SDL_SetRenderDrawColor(self.renderer, 0xFF, 0xFF, 0xFF, 0xFF);
    _ = c.SDL_RenderFillRect(self.renderer, &.{ .x = 0, .y = 0, .w = constant.BLOCK * 6, .h = constant.SCREEN_HEIGHT });

    var txt_width = self.bitmap_font.calculateTextWidth("Level");
    self.bitmap_font.renderText(@intCast(c_int, (constant.VIEWPORT_INFO_WIDTH - txt_width) / 2), 45, "Level");

    var level_txt = try std.fmt.allocPrintZ(self.allocator, "{d}", .{self.level});
    txt_width = self.bitmap_font.calculateTextWidth(level_txt);
    self.bitmap_font.renderText(@intCast(c_int, (constant.VIEWPORT_INFO_WIDTH - txt_width) / 2), 80, level_txt);

    // Score viewport
    _ = c.SDL_RenderSetViewport(self.renderer, &Self.score_viewport);
    _ = c.SDL_SetRenderDrawColor(self.renderer, 0xFF, 0xFF, 0xFF, 0xFF);
    _ = c.SDL_RenderFillRect(self.renderer, &.{ .x = 0, .y = 0, .w = constant.BLOCK * 6, .h = constant.SCREEN_HEIGHT });

    txt_width = self.bitmap_font.calculateTextWidth("Score");
    self.bitmap_font.renderText(@intCast(c_int, (constant.VIEWPORT_INFO_WIDTH - txt_width) / 2), 45, "Score");

    var score_txt = try std.fmt.allocPrintZ(self.allocator, "{d}", .{self.score});
    txt_width = self.bitmap_font.calculateTextWidth(score_txt);
    self.bitmap_font.renderText(@intCast(c_int, (constant.VIEWPORT_INFO_WIDTH - txt_width) / 2), 80, score_txt);

    // Tetromino viewport
    _ = c.SDL_RenderSetViewport(self.renderer, &Self.tetromino_viewport);
    _ = c.SDL_SetRenderDrawColor(self.renderer, 0xFF, 0xFF, 0xFF, 0xFF);
    _ = c.SDL_RenderFillRect(self.renderer, &.{ .x = 0, .y = 0, .w = constant.BLOCK * 6, .h = constant.SCREEN_HEIGHT });

    // Draw next incoming piece
    Piece.next_piece.interface.draw(Piece.View.TetrominoViewport);

    _ = c.SDL_RenderPresent(self.renderer);
}

fn onEnterFn(child: *StateInterfce) !bool {
    var self = @fieldParentPtr(Self, "interface", child);
    self.cap_timer.startTimer();
    return true;
}

fn onExitFn(child: *StateInterfce) !bool {
    var self = @fieldParentPtr(Self, "interface", child);
    _ = self;
    std.log.info("Leaving playing state", .{});
    return true;
}

fn stateIDFn(child: *StateInterfce) []const u8 {
    var self = @fieldParentPtr(Self, "interface", child);
    _ = self;
    return "Play";
}

pub fn close(self: Self) void {
    c.SDL_DestroyWindow(self.window);
    c.SDL_DestroyRenderer(self.renderer);
}
