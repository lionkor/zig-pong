const std = @import("std");

const sdl2 = @cImport(@cInclude("SDL2/SDL.h"));

const SDLContext = struct {
    renderer: ?*sdl2.SDL_Renderer = null,
    window: ?*sdl2.SDL_Window = null,
    is_open: bool = false,

    fn init() error{SDLError}!SDLContext {
        const rc = sdl2.SDL_Init(sdl2.SDL_INIT_EVERYTHING);
        if (rc != 0) {
            return error.SDLError;
        }
        var ctx: SDLContext = .{};
        ctx.window = sdl2.SDL_CreateWindow(
            "zig-pong",
            sdl2.SDL_WINDOWPOS_UNDEFINED,
            sdl2.SDL_WINDOWPOS_UNDEFINED,
            800,
            600,
            0,
        );
        if (ctx.window == null) {
            return error.SDLError;
        }
        ctx.renderer = sdl2.SDL_CreateRenderer(ctx.window, 0, sdl2.SDL_RENDERER_ACCELERATED);
        if (ctx.renderer == null) {
            return error.SDLError;
        }
        ctx.is_open = true;
        return ctx;
    }

    fn deinit(self: *SDLContext) void {
        _ = sdl2.SDL_DestroyRenderer(self.renderer);
        _ = sdl2.SDL_DestroyWindow(self.window);
        _ = sdl2.SDL_Quit();
    }

    fn processEvents(self: *SDLContext) void {
        var event: sdl2.SDL_Event = undefined;
        while (sdl2.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                sdl2.SDL_KEYDOWN => if (event.key.keysym.sym == sdl2.SDLK_ESCAPE) {
                    self.is_open = false;
                },
                sdl2.SDL_QUIT => self.is_open = false,
                else => {},
            }
        }
    }
};

pub fn main() anyerror!void {
    var context = try SDLContext.init();
    defer context.deinit();
    std.log.info("Initialized {}!", .{&context});

    while (context.is_open) {
        context.processEvents();
    }
}

test "basic test" {
    try std.testing.expectEqual(10, 3 + 7);
}
