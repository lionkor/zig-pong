const std = @import("std");

const sdl2 = @cImport(@cInclude("SDL2/SDL.h"));

const SDLContext = struct {
    renderer: ?*sdl2.SDL_Renderer = null,
    window: ?*sdl2.SDL_Window = null,
    is_open: bool = false,

    const Rect = struct {
        x: i32,
        y: i32,
        w: i32,
        h: i32,
        color: Color,
    };

    const WIDTH: usize = 800;
    const HEIGHT: usize = 600;

    const Color = struct {
        r: u8,
        g: u8,
        b: u8,
    };

    fn drawRect(self: *SDLContext, rect: *Rect) void {
        _ = sdl2.SDL_SetRenderDrawColor(self.renderer, rect.color.r, rect.color.g, rect.color.b, 255);
        var sdl_rect: sdl2.SDL_Rect = undefined;
        sdl_rect.x = rect.x;
        sdl_rect.y = rect.y;
        sdl_rect.w = rect.w;
        sdl_rect.h = rect.h;
        _ = sdl2.SDL_RenderDrawRect(self.renderer, &sdl_rect);
        _ = sdl2.SDL_SetRenderDrawColor(self.renderer, 0, 0, 0, 255);
    }

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
        return ctx;
    }

    fn deinit(self: *SDLContext) void {
        _ = sdl2.SDL_DestroyRenderer(self.renderer);
        _ = sdl2.SDL_DestroyWindow(self.window);
        _ = sdl2.SDL_Quit();
    }

    fn renderClear(self: *SDLContext) void {
        _ = sdl2.SDL_RenderClear(self.renderer);
    }

    fn renderPresent(self: *SDLContext) void {
        _ = sdl2.SDL_RenderPresent(self.renderer);
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

    var player1: SDLContext.Rect = .{
        .x = 15,
        .y = SDLContext.HEIGHT / 2 - 20,
        .w = 10,
        .h = 40,
        .color = .{
            .r = 255,
            .g = 0,
            .b = 0,
        },
    };

    while (context.is_open) {
        context.processEvents();
        context.renderClear();
        context.drawRect(&player1);
        context.renderPresent();
    }
}

test "basic test" {
    try std.testing.expectEqual(10, 3 + 7);
}
