const std = @import("std");
const Vec2 = @import("game/Vec2.zig");
const SDLContext = @import("game/SDLContext.zig");
const NetClient = @import("game/NetClient.zig");
const Packet = @import("Packet.zig");

const Pos = struct {
    x: i32,
    y: i32,
};

var other_last_pos: i32 = 0;
var ball_pos: Pos = .{ .x = -1, .y = -1 };
var remote_ball_vel: Vec2 = .{ .x = 0, .y = 0 };

fn readThreadMain(net: *NetClient) !void {
    while (true) {
        var other_packet = try net.readPacket();
        if (other_packet.is(.PlayerPos)) {
            other_last_pos = other_packet.get(i32);
        } else if (other_packet.is(.BallPos)) {
            ball_pos = other_packet.get(Pos);
        } else if (other_packet.is(.BallVel)) {
            remote_ball_vel = other_packet.get(Vec2);
        }
    }
}

pub fn main() anyerror!void {
    var alloc = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    var allocator = alloc.allocator();

    var args: [][:0]u8 = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len != 3) {
        std.log.err("invalid usage.\nusage: {s} <host> <port>", .{args[0]});
        std.process.exit(1);
    }
    var port = try std.fmt.parseUnsigned(u16, args[2], 10);

    var net = NetClient{ .conn = try std.net.tcpConnectToHost(allocator, args[1], port) };
    var side_packet = try net.readPacket();
    if (!side_packet.is(.Side)) {
        std.log.err("invalid packet, expected side packet!", .{});
        std.process.exit(1);
    }
    const side = side_packet.get([1]u8)[0];
    const host = side == 'L'; // left player is physics host
    std.log.info("server told us that we're side '{c}'", .{side});

    var context = try SDLContext.init();
    defer context.deinit();
    std.log.info("Initialized {}!", .{&context});

    context.fps_limit = 40;

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

    _ = host;

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

    var this_player: *SDLContext.Rect = undefined;
    var other_player: *SDLContext.Rect = undefined;
    if (side == 'L') {
        this_player = &player1;
        other_player = &player2;
    } else {
        other_player = &player1;
        this_player = &player2;
    }

    other_last_pos = other_player.y;

    this_player.color = .{
        .r = 0x00,
        .g = 0x00,
        .b = 0xff,
    };
    other_player.color = .{
        .r = 0xff,
        .g = 0x00,
        .b = 0x00,
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

    var thread = try std.Thread.spawn(.{}, readThreadMain, .{&net});

    var last_ball_update = std.time.milliTimestamp();

    while (context.is_open) {
        context.processEvents();
        context.renderClear();
        if (context.is_down_pressed) {
            this_player.y = std.math.min(this_player.y + player_vel, SDLContext.HEIGHT - this_player.h);
            try net.writePacket(Packet.make(.PlayerPos, this_player.y));
        }
        if (context.is_up_pressed) {
            this_player.y = std.math.max(this_player.y - player_vel, 0);
            try net.writePacket(Packet.make(.PlayerPos, this_player.y));
        }

        other_player.y = other_last_pos;

        if (host) {
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
                try net.writePacket(Packet.make(.BallVel, ball_vel));
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
                try net.writePacket(Packet.make(.BallVel, ball_vel));
            }
            // pedal collision
            // player 1
            if (ball.collidesWith(&player1)) {
                if (ball_vel.x < 0) {
                    ball_vel = ball_vel.reflected(Vec2{ .x = 1, .y = 0 });
                }
                try net.writePacket(Packet.make(.BallVel, ball_vel));
            }
            // player 2
            if (ball.collidesWith(&player2)) {
                if (ball_vel.x > 0) {
                    ball_vel = ball_vel.reflected(Vec2{ .x = -1, .y = 0 });
                }
                try net.writePacket(Packet.make(.BallVel, ball_vel));
            }
            if (paused and context.is_space_pressed) {
                ball_vel.x = rand.float(f32) - 0.5;
                ball_vel.y = (rand.float(f32) - 0.5) * 0.3;
                ball_vel = ball_vel.normalized().mult(6);
                paused = false;
                try net.writePacket(Packet.make(.BallVel, ball_vel));
                try net.writePacket(Packet.make(.BallPos, Pos{ .x = ball.x, .y = ball.y }));
            }
            if (!paused) {
                ball.x = @floatToInt(i32, @intToFloat(f32, ball.x) + ball_vel.x);
                ball.y = @floatToInt(i32, @intToFloat(f32, ball.y) + ball_vel.y);
            } else {
                try net.writePacket(Packet.make(.BallVel, .{ .x = 0, .y = 0 }));
            }
            if (std.time.milliTimestamp() - last_ball_update > 100) {
                last_ball_update = std.time.milliTimestamp();
                try net.writePacket(Packet.make(.BallPos, Pos{ .x = ball.x, .y = ball.y }));
            }
        } else {
            ball.x = @floatToInt(i32, @intToFloat(f32, ball.x) + remote_ball_vel.x);
            ball.y = @floatToInt(i32, @intToFloat(f32, ball.y) + remote_ball_vel.y);
            if (ball_pos.x != -1 and ball_pos.y != -1) {
                ball.x = ball_pos.x;
                ball.y = ball_pos.y;
            }
        }
        context.drawRect(&player1);
        context.drawRect(&player2);
        context.drawRect(&ball);
        context.renderPresent();
    }

    thread.join();
}
