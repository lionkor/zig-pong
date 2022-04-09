const std = @import("std");
const NetServer = @import("server/NetServer.zig");
const Packet = @import("Packet.zig");

fn clientHandshake(client: *NetServer.Client, is_first: bool) !void {
    if (is_first) {
        try client.writePacket(Packet.make(.Side, [1]u8{'L'}));
    } else {
        try client.writePacket(Packet.make(.Side, [1]u8{'R'}));
    }
}

const ClientThreadContext = struct {
    client: *NetServer.Client,
    otherClient: *NetServer.Client,
};

fn clientSendThread(client: *NetServer.Client) !void {
    while (true) {
        if (client.getNextSendPacket()) |packet| {
            try client.writePacket(packet);
        }
    }
}

fn clientReceiveThread(client: *NetServer.Client, otherClient: *NetServer.Client) !void {
    while (true) {
        var packet: Packet = try client.readPacket();
        try otherClient.pushSendPacket(packet);
    }
}

pub fn main() anyerror!void {
    var alloc = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    var allocator = alloc.allocator();

    var args: [][:0]u8 = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len != 2) {
        std.log.err("invalid usage.\nusage: {s} <port>", .{args[0]});
        std.process.exit(1);
    }
    var port = try std.fmt.parseUnsigned(u16, args[1], 10);

    var server = NetServer.init();
    defer server.deinit();
    try server.start(port);

    std.log.info("starting zig-pong server on port {}", .{port});

    std.log.info("waiting for first client to connect...", .{});

    var client1 = try server.accept();
    try clientHandshake(&client1, true);

    std.log.info("client 1 connected: {}, waiting for client 2...", .{client1.conn.address});

    var client2 = try server.accept();
    try clientHandshake(&client2, false);

    std.log.info("client 2 connected: {}", .{client2.conn.address});

    var client1_recv_thread = try std.Thread.spawn(.{}, clientReceiveThread, .{ &client1, &client2 });
    var client1_send_thread = try std.Thread.spawn(.{}, clientSendThread, .{&client1});
    var client2_recv_thread = try std.Thread.spawn(.{}, clientReceiveThread, .{ &client2, &client1 });
    var client2_send_thread = try std.Thread.spawn(.{}, clientSendThread, .{&client2});
    client1_recv_thread.join();
    client1_send_thread.join();
    client2_recv_thread.join();
    client2_send_thread.join();
}
