const std = @import("std");

const sdl2 = @cImport(@cInclude("SDL2/SDL.h"));

const SDLContext = struct {
    renderer: ?*sdl2.SDL_Renderer = null,
    window: ?*sdl2.SDL_Window = null,
    is_open: bool = false,
    is_w_pressed: bool = false,
    is_s_pressed: bool = false,
    is_up_pressed: bool = false,
    is_down_pressed: bool = false,

    const Rect = struct {
        x: i32,
        y: i32,
        w: i32,
        h: i32,
        color: Color,
    };

    const WIDTH: i32 = 800;
    const HEIGHT: i32 = 600;

    const Color = struct {
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

    fn drawRect(self: *SDLContext, rect: *Rect) void {
        _ = sdl2.SDL_SetRenderDrawColor(self.renderer, rect.color.r, rect.color.g, rect.color.b, 255);
        var sdl_rect: sdl2.SDL_Rect = undefined;
        sdl_rect.x = rect.x;
        sdl_rect.y = rect.y;
        sdl_rect.w = rect.w;
        sdl_rect.h = rect.h;
        _ = sdl2.SDL_RenderFillRect(self.renderer, &sdl_rect);
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
                sdl2.SDL_KEYDOWN => switch (event.key.keysym.sym) {
                    sdl2.SDLK_ESCAPE => self.is_open = false,
                    sdl2.SDLK_UP => self.is_up_pressed = true,
                    sdl2.SDLK_DOWN => self.is_down_pressed = true,
                    sdl2.SDLK_w => self.is_w_pressed = true,
                    sdl2.SDLK_s => self.is_s_pressed = true,
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
};

pub fn main() anyerror!void {
    var context = try SDLContext.init();
    defer context.deinit();
    std.log.info("Initialized {}!", .{&context});

    var player1: SDLContext.Rect = .{
        .x = 15,
        .y = SDLContext.HEIGHT / 2 - 30,
        .w = 10,
        .h = 60,
        .color = .{
            .r = 0x00,
            .g = 0x00,
            .b = 0xff,
        },
    };

    var player2: SDLContext.Rect = .{
        .x = SDLContext.WIDTH - 15 - 10,
        .y = SDLContext.HEIGHT / 2 - 30,
        .w = 10,
        .h = 60,
        .color = .{
            .r = 0xff,
            .g = 0x00,
            .b = 0x00,
        },
    };

    var ball: SDLContext.Rect = .{
        .x = SDLContext.WIDTH / 2 - 5,
        .y = SDLContext.HEIGHT / 2 - 5,
        .w = 10,
        .h = 10,
        .color = .{
            .r = 0xff,
            .g = 0xff,
            .b = 0xff,
        },
    };

    var player_vel: i32 = 10;

    std.log.info("color as u32: {x:0>8}", .{player1.color.toU32()});

    while (context.is_open) {
        context.processEvents();
        context.renderClear();
        if (context.is_s_pressed) {
            player1.y = std.math.min(player1.y + player_vel, SDLContext.HEIGHT - player1.h);
        }
        if (context.is_w_pressed) {
            player1.y = std.math.max(player1.y - player_vel, 0);
        }
        if (context.is_down_pressed) {
            player2.y = std.math.min(player2.y + player_vel, SDLContext.HEIGHT - player2.h);
        }
        if (context.is_up_pressed) {
            player2.y = std.math.max(player2.y - player_vel, 0);
        }
        context.drawRect(&player1);
        context.drawRect(&player2);
        context.drawRect(&ball);
        context.renderPresent();
    }
}

test "basic test" {
    try std.testing.expectEqual(10, 3 + 7);
}
