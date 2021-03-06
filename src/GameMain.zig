const std = @import("std");
const Vec2 = @import("game/Vec2.zig");
const SDLContext = @import("game/SDLContext.zig");
const NetClient = @import("network/NetClient.zig").NetClient;
const Packet = @import("network/Packet.zig").Packet;
const PacketType = @import("PacketType.zig").PacketType;
const EntityId = @import("ecs/ECS.zig").EntityId;
const Ecs = @import("ecs/ECS.zig").ECS(CompType, Comp);

const CompType = enum {
    Rect,
};

const CompData = union {
    rect: SDLContext.Rect,
};

const Comp = struct {
    entity_id: EntityId = .{ .index = 0 },
    data: CompData,
};

const Pos = struct {
    x: i32 = 0,
    y: i32 = 0,
};

const GamePacket = Packet(PacketType, 16);
const GameNetClient = NetClient(GamePacket);

const Side = packed struct {
    n: u32,
    side: u8,
};

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

    var ecs = Ecs.init(allocator);

    var net = try GameNetClient.init(allocator, args[1], port);
    try net.startThreads();

    // the side handshake!
    var got_side = false;
    var side: u8 = 0;
    // side handshake protocol:
    // 1. send R
    // 2. wait for a packet
    // 3. either:
    //    3.1 get L, so we start the game as L
    //    3.2 get R, so we send L

    // 1. send R
    try net.writePacket(GamePacket.makeReliable(.Side, @as(u8, 'R')));
    std.log.debug("sent R packet", .{});
    while (!got_side) {
        std.time.sleep(std.time.ns_per_s * 1);
        // 2. wait for a packet
        std.log.debug("waiting for a side packet", .{});
        if (net.getReadPacket()) |packet| {
            if (packet.is(.Side)) {
                // 3.1 got L, so we start the game as L
                if (packet.get(u8) == 'L') {
                    std.log.debug("got L packet", .{});
                    side = 'L';
                    got_side = true;
                } else if (packet.get(u8) == 'R') {
                    try net.writePacket(GamePacket.makeReliable(.Side, @as(u8, 'L')));
                    std.log.debug("sent L packet", .{});
                    side = 'R';
                    got_side = true;
                } else {
                    std.log.warn("got side packet with weird payload: {}", .{packet});
                }
            } else {
                std.log.warn("unexpected packet during handshake: {}", .{packet});
            }
        }
    }

    var host = side == 'L';

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

    ecs.lockUnique();
    var e_player = try ecs.addEntity();
    var comp_player = try ecs.addOrReplaceComponent(
        e_player,
        .Rect,
        .{ .data = CompData{ .rect = this_player.* } },
    );
    comp_player.entity_id = e_player;

    var e_opponent = try ecs.addEntity();
    var comp_opponent = try ecs.addOrReplaceComponent(
        e_opponent,
        .Rect,
        .{ .data = CompData{ .rect = other_player.* } },
    );
    comp_opponent.entity_id = e_opponent;
    ecs.unlockUnique();

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

    var last_ball_pos: Pos = .{};

    const ball_speed = 6;

    try net.writePacket(GamePacket.makeUnreliable(.Ping, @as(u32, 0)));

    while (context.is_open) {
        context.processEvents();
        context.renderClear();

        ecs.lockUnique();
        if (context.is_down_pressed) {
            if (ecs.getComponent(e_player, .Rect)) |comp| {
                comp.data.rect.y = std.math.min(comp.data.rect.y + player_vel, SDLContext.HEIGHT - comp.data.rect.h);
                try net.writePacket(GamePacket.makeUnreliableWithPriority(.PlayerPos, comp.data.rect.y, 1));
            }
        }
        if (context.is_up_pressed) {
            if (ecs.getComponent(e_player, .Rect)) |comp| {
                comp.data.rect.y = std.math.max(comp.data.rect.y - player_vel, 0);
                try net.writePacket(GamePacket.makeUnreliableWithPriority(.PlayerPos, comp.data.rect.y, 1));
            }
        }

        if (host) {
            if (ball.x + ball.w >= SDLContext.WIDTH) {
                // player2 loses
                player1_score += 1;
                std.log.info("player 1 scored a point! player1: {}, player2: {}", .{ player1_score, player2_score });
                paused = true;
                ball.x = SDLContext.WIDTH / 2 - @divTrunc(ball.w, 2);
                ball.y = SDLContext.HEIGHT / 2 - @divTrunc(ball.h, 2);
                ball_vel.x = 0;
                ball_vel.y = 0;
                try net.writePacket(GamePacket.makeUnreliableWithPriority(.BallPos, Pos{ .x = ball.x, .y = ball.y }, 1));
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
                ball_vel.x = 0;
                ball_vel.y = 0;
                try net.writePacket(GamePacket.makeUnreliableWithPriority(.BallPos, Pos{ .x = ball.x, .y = ball.y }, 1));
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
                ball_vel = ball_vel.normalized().mult(ball_speed);
                paused = false;
            }
            if (!paused) {
                ball.x = @floatToInt(i32, @intToFloat(f32, ball.x) + ball_vel.x);
                ball.y = @floatToInt(i32, @intToFloat(f32, ball.y) + ball_vel.y);
            }
            const diff = 5;
            if ((try std.math.absInt(last_ball_pos.x - ball.x)) +
                (try std.math.absInt(last_ball_pos.y - ball.y)) > diff)
            {
                last_ball_pos.x = ball.x;
                last_ball_pos.y = ball.y;
                try net.writePacket(GamePacket.makeUnreliable(.BallPos, Pos{ .x = ball.x, .y = ball.y }));
            }
        }
        while (true) {
            var maybe_packet = net.getReadPacket();
            if (maybe_packet != null) {
                var packet = maybe_packet.?;
                switch (packet.getType()) {
                    .Ping => {},
                    .BallPos => {
                        if (!host) {
                            var pos: Pos = packet.get(Pos);
                            ball.x = pos.x;
                            ball.y = pos.y;
                        }
                    },
                    .PlayerPos => {
                        var pos: i32 = packet.get(i32);
                        if (ecs.getComponent(e_opponent, .Rect)) |comp| {
                            comp.data.rect.y = pos;
                        }
                    },
                    else => std.log.err("unexpected packet type: {}", .{packet}),
                }
            } else {
                break;
            }
        }
        ecs.unlockUnique();

        for (ecs.getAllComponentsOfType(.Rect)) |comp| {
            context.drawRect(&comp.data.rect);
        }

        context.drawRect(&ball);
        context.renderPresent();
    }
}
