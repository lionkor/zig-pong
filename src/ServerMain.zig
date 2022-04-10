const std = @import("std");
const NetServer = @import("network/NetServer.zig");
const Packet = @import("network/Packet.zig");
const network = @import("network/zig-network/network.zig");

fn clientHandshake(client: *NetServer.Client, is_first: bool) !void {
    if (is_first) {
        try client.writePacket(Packet.makeReliable(.Side, [1]u8{'L'}));
    } else {
        try client.writePacket(Packet.makeReliable(.Side, [1]u8{'R'}));
    }
}

fn clientSendThread(client: *NetServer.Client) !void {
    while (true) {
        if (client.getNextSendPacket()) |packet| {
            try client.writePacket(packet);
        }
    }
}

fn clientTcpReceiveThread(client: *NetServer.Client, otherClient: *NetServer.Client) !void {
    while (true) {
        var packet: Packet = try client.readPacketTcp();
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

    var udp: network.Socket = try network.Socket.create(.ipv6, .udp);
    try udp.bindToPort(port);

    var server = NetServer.init();
    defer server.deinit();
    try server.start(port);

    std.log.info("starting zig-pong server on port {}", .{port});

    std.log.info("waiting for first client to connect...", .{});

    var client1 = try server.accept(allocator);
    try clientHandshake(&client1, true);

    std.log.info("client 1 connected: {}, waiting for client 2...", .{client1.tcp.address});

    var client2 = try server.accept(allocator);
    try clientHandshake(&client2, false);

    std.log.info("client 2 connected: {}", .{client2.tcp.address});

    var client1_recv_thread = try std.Thread.spawn(.{}, clientTcpReceiveThread, .{ &client1, &client2 });
    var client1_send_thread = try std.Thread.spawn(.{}, clientSendThread, .{&client1});
    var client2_recv_thread = try std.Thread.spawn(.{}, clientTcpReceiveThread, .{ &client2, &client1 });
    var client2_send_thread = try std.Thread.spawn(.{}, clientSendThread, .{&client2});

    while (true) {
        var packet: Packet = .{};
        var recv = try udp.receiveFrom(&packet.buf);
        if (packet.is(.Side)) {
            if (packet.get([1]u8)[0] == 'L' and client1.end_point == null) {
                client1.end_point = recv.sender;
            } else if (packet.get([1]u8)[0] == 'R' and client2.end_point == null) {
                client2.end_point = recv.sender;
            }
        } else if (client1.end_point != null and client2.end_point != null) {
            if (client1.end_point.?.address.eql(recv.sender.address) and client1.end_point.?.port == recv.sender.port) {
                const n = try udp.sendTo(client2.end_point.?, &packet.buf);
                if (n != packet.buf.len) {
                    std.log.err("expected {} bytes to be sent, instead only sent {}", .{ packet.buf.len, n });
                }
            } else if (client2.end_point.?.address.eql(recv.sender.address) and client2.end_point.?.port == recv.sender.port) {
                const n = try udp.sendTo(client1.end_point.?, &packet.buf);
                if (n != packet.buf.len) {
                    std.log.err("expected {} bytes to be sent, instead only sent {}", .{ packet.buf.len, n });
                }
            }
        }
    }
    client1_recv_thread.join();
    client1_send_thread.join();
    client2_recv_thread.join();
    client2_send_thread.join();
}
