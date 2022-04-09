const std = @import("std");
const Vec2 = @import("game/Vec2.zig");
const SDLContext = @import("game/SDLContext.zig");

pub fn main() anyerror!void {
    var context = try SDLContext.init();
    defer context.deinit();
    std.log.info("Initialized {}!", .{&context});

    context.fps_limit = 50;

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

    var ball_vel: Vec2 = .{
        .x = 0.0,
        .y = 0.0,
    };

    var player_vel: i32 = 7;
    var player1_score: u8 = 0;
    var player2_score: u8 = 0;
    var paused: bool = true;

    var rand = std.rand.DefaultPrng.init(@bitCast(u64, std.time.milliTimestamp())).random();

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
        if (ball.x + ball.w >= SDLContext.WIDTH) {
            // player2 loses
            player1_score += 1;
            std.log.info("player 1 scored a point! player1: {}, player2: {}", .{ player1_score, player2_score });
            paused = true;
            ball.x = SDLContext.WIDTH / 2 - @divTrunc(ball.w, 2);
            ball.y = SDLContext.HEIGHT / 2 - @divTrunc(ball.h, 2);
        }
        if (ball.y + ball.h >= SDLContext.HEIGHT) {
            // bounce
            ball_vel = ball_vel.reflected(Vec2{ .x = 0, .y = -1 });
        }
        if (ball.x < 0) {
            // player1 loses
            player2_score += 1;
            std.log.info("player 2 scored a point! player1: {}, player2: {}", .{ player1_score, player2_score });
            paused = true;
            ball.x = SDLContext.WIDTH / 2 - @divTrunc(ball.w, 2);
            ball.y = SDLContext.HEIGHT / 2 - @divTrunc(ball.h, 2);
        }
        if (ball.y < 0) {
            // bounce
            ball_vel = ball_vel.reflected(Vec2{ .x = 0, .y = 1 });
        }
        // pedal collision
        // player 1
        if (ball.collidesWith(&player1)) {
            if (ball_vel.x < 0) {
                ball_vel = ball_vel.reflected(Vec2{ .x = 1, .y = 0 });
            }
        }
        // player 2
        if (ball.collidesWith(&player2)) {
            if (ball_vel.x > 0) {
                ball_vel = ball_vel.reflected(Vec2{ .x = -1, .y = 0 });
            }
        }
        if (paused and context.is_space_pressed) {
            ball_vel.x = rand.float(f32) - 0.5;
            ball_vel.y = (rand.float(f32) - 0.5) * 0.3;
            ball_vel = ball_vel.normalized().mult(6);
            paused = false;
        }
        if (!paused) {
            ball.x = @floatToInt(i32, @intToFloat(f32, ball.x) + ball_vel.x);
            ball.y = @floatToInt(i32, @intToFloat(f32, ball.y) + ball_vel.y);
        }
        context.drawRect(&player1);
        context.drawRect(&player2);
        context.drawRect(&ball);
        context.renderPresent();
    }
}
