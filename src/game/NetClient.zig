const std = @import("std");
const NetClient = @This();
const Packet = @import("../Packet.zig");

conn: std.net.Stream,

pub fn writePacket(self: *NetClient, packet: Packet) anyerror!void {
    const n = try self.conn.write(&packet.buf);
    if (n != packet.buf.len) {
        return error.WriteError;
    }
    //std.log.debug("sent: {}", .{packet});
}

pub fn readPacket(self: *NetClient) anyerror!Packet {
    var packet: Packet = .{};
    const n = try self.conn.read(&packet.buf);
    if (n != packet.buf.len) {
        return error.ReadError;
    }
    //std.log.debug("received: {}", .{packet});
    return packet;
}
