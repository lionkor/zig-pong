const std = @import("std");
const Vec2 = @import("Vec2.zig");
const SDLContext = @This();
const sdl2 = @cImport(@cInclude("SDL2/SDL.h"));

renderer: ?*sdl2.SDL_Renderer = null,
window: ?*sdl2.SDL_Window = null,
is_open: bool = false,
is_w_pressed: bool = false,
is_s_pressed: bool = false,
is_up_pressed: bool = false,
is_down_pressed: bool = false,
is_space_pressed: bool = false,
fps_limit: u32 = 0,
last_frame_time_ms: i64 = 0,

pub const Rect = struct {
    x: i32,
    y: i32,
    w: i32,
    h: i32,
    color: Color,

    // AABB collision between two rectangles
    pub fn collidesWith(self: *const Rect, other: *const Rect) bool {
        for ([_]i32{ self.x, self.x + self.w }) |x| {
            for ([_]i32{ self.y, self.y + self.h }) |y| {
                if (x >= other.x and
                    x <= other.x + other.w and
                    y >= other.y and
                    y <= other.y + other.h)
                {
                    return true;
                }
            }
        }
        return false;
    }
};

pub const WIDTH: i32 = 800;
pub const HEIGHT: i32 = 600;

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    pub fn toU32(self: *Color) u32 {
        return (@intCast(u32, self.r) << 24) |
            (@intCast(u32, self.g) << 16) |
            (@intCast(u32, self.b) << 8) |
            (255 << 0);
    }
};

pub fn drawRect(self: *SDLContext, rect: *Rect) void {
    _ = sdl2.SDL_SetRenderDrawColor(self.renderer, rect.color.r, rect.color.g, rect.color.b, 255);
    var sdl_rect: sdl2.SDL_Rect = undefined;
    sdl_rect.x = rect.x;
    sdl_rect.y = rect.y;
    sdl_rect.w = rect.w;
    sdl_rect.h = rect.h;
    _ = sdl2.SDL_RenderFillRect(self.renderer, &sdl_rect);
    _ = sdl2.SDL_SetRenderDrawColor(self.renderer, 0, 0, 0, 255);
}

pub fn init() error{SDLError}!SDLContext {
    const rc = sdl2.SDL_Init(sdl2.SDL_INIT_EVERYTHING);
    if (rc != 0) {
        return error.SDLError;
    }
    var ctx: SDLContext = .{};
    ctx.window = sdl2.SDL_CreateWindow(
        "zig-pong",
        sdl2.SDL_WINDOWPOS_UNDEFINED,
        sdl2.SDL_WINDOWPOS_UNDEFINED,
        WIDTH,
        HEIGHT,
        0,
    );
    if (ctx.window == null) {
        return error.SDLError;
    }
    ctx.renderer = sdl2.SDL_CreateRenderer(ctx.window, 0, sdl2.SDL_RENDERER_ACCELERATED | sdl2.SDL_RENDERER_PRESENTVSYNC);
    if (ctx.renderer == null) {
        return error.SDLError;
    }
    ctx.is_open = true;
    ctx.last_frame_time_ms = std.time.milliTimestamp();
    return ctx;
}

pub fn deinit(self: *SDLContext) void {
    _ = sdl2.SDL_DestroyRenderer(self.renderer);
    _ = sdl2.SDL_DestroyWindow(self.window);
    _ = sdl2.SDL_Quit();
}

pub fn renderClear(self: *SDLContext) void {
    _ = sdl2.SDL_RenderClear(self.renderer);
}

pub fn renderPresent(self: *SDLContext) void {
    _ = sdl2.SDL_RenderPresent(self.renderer);

    if (self.fps_limit > 0) {
        const this_time: i64 = std.time.milliTimestamp();
        const delta_ms: i64 = this_time - self.last_frame_time_ms;
        const desired: i64 = 1000 / self.fps_limit;
        if (delta_ms < desired) {
            sdl2.SDL_Delay(@intCast(u32, desired - delta_ms));
        }
        self.last_frame_time_ms = this_time;
    }
}

pub fn processEvents(self: *SDLContext) void {
    var event: sdl2.SDL_Event = undefined;
    // reset every time
    self.is_space_pressed = false;
    while (sdl2.SDL_PollEvent(&event) != 0) {
        switch (event.type) {
            sdl2.SDL_KEYDOWN => switch (event.key.keysym.sym) {
                sdl2.SDLK_ESCAPE => self.is_open = false,
                sdl2.SDLK_UP => self.is_up_pressed = true,
                sdl2.SDLK_DOWN => self.is_down_pressed = true,
                sdl2.SDLK_w => self.is_w_pressed = true,
                sdl2.SDLK_s => self.is_s_pressed = true,
                sdl2.SDLK_SPACE => self.is_space_pressed = true,
                else => {},
            },
            sdl2.SDL_KEYUP => switch (event.key.keysym.sym) {
                sdl2.SDLK_UP => self.is_up_pressed = false,
                sdl2.SDLK_DOWN => self.is_down_pressed = false,
                sdl2.SDLK_w => self.is_w_pressed = false,
                sdl2.SDLK_s => self.is_s_pressed = false,
                else => {},
            },
            sdl2.SDL_QUIT => self.is_open = false,
            else => {},
        }
    }
}
