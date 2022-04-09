const std = @import("std");
const Server = @import("server/Server.zig");
const Packet = @import("Packet.zig");

fn clientHandshake(client: *Server.Client, is_first: bool) !void {
    if (is_first) {
        try client.writePacket(Packet.make(.Side, [1:0]u8{'L'}));
    } else {
        try client.writePacket(Packet.make(.Side, [1:0]u8{'R'}));
    }
}

const ClientThreadContext = struct {
    client: *Server.Client,
    otherClient: *Server.Client,
};

fn clientThread(client: *Server.Client, otherClient: *Server.Client) !void {
    while (true) {
        var packet: Packet = try client.readPacket();
        std.log.debug("got packet: {}", .{packet});
        otherClient.pushSendPacket(packet);
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

    var server = Server.init();
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

    var client1_thread = try std.Thread.spawn(.{}, clientThread, .{ &client1, &client2 });
    var client2_thread = try std.Thread.spawn(.{}, clientThread, .{ &client2, &client1 });
    client1_thread.join();
    client2_thread.join();
}
