const std = @import("std");
const PacketType = @import("PacketType.zig").PacketType;
const Packet = @import("network/Packet.zig").Packet(PacketType, 16);
const NetServer = @import("network/NetServer.zig").NetServer(Packet);
const network = @import("network/zig-network/network.zig");

pub fn main() anyerror!void {
    var alloc = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    var allocator = alloc.allocator();

    var args: [][:0]u8 = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len != 2) {
        std.log.err("invalid usage.\nusage: '{s} <port>'", .{args[0]});
        std.process.exit(1);
    }
    var port = try std.fmt.parseUnsigned(u16, args[1], 10);

    var server = try NetServer.init(allocator, port, port);
    defer server.deinit();

    std.log.debug("listening on {}", .{port});
    try server.start();
}
