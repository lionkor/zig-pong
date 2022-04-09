const std = @import("std");
const Packet = @This();

buf: [16]u8 = undefined,

pub const Type = enum(u16) {
    Side = 1,
    BallPos,
    BallVel,
    PlayerPos,
};

fn assert(ok: bool) void {
    if (!ok) unreachable; // assertion failure
}

pub fn make(packet_type: Type, data: anytype) Packet {
    var packet: Packet = .{};
    comptime {
        assert(@sizeOf(@TypeOf(data)) + @sizeOf(Type) <= packet.buf.len);
    }
    std.mem.set(u8, &packet.buf, 0);
    std.mem.copy(u8, &packet.buf, std.mem.asBytes(&packet_type));
    std.mem.copy(u8, packet.buf[@sizeOf(Type)..], std.mem.asBytes(&data));
    return packet;
}

pub fn get(self: *Packet, comptime T: type) T {
    return std.mem.bytesToValue(T, self.buf[@sizeOf(Type) .. @sizeOf(Type) + @sizeOf(T)]);
}

pub fn is(self: *Packet, packet_type: Type) bool {
    return self.getType() == packet_type;
}

pub fn getType(self: *Packet) Type {
    return std.mem.bytesToValue(Type, self.buf[0..@sizeOf(Type)]);
}
