const std = @import("std");
const Packet = @This();

buf: [16]u8 = undefined,
// priority of this packet, higher is higher priority, 0 is lowest / default
prio: u8 = 0,
reliable: bool = true,

pub const Type = enum(u16) {
    Side = 1,
    BallPos,
    BallVel,
    PlayerPos,
};

fn assert(ok: bool) void {
    if (!ok) unreachable; // assertion failure
}

pub inline fn makeReliable(packet_type: Type, data: anytype) Packet {
    return make(packet_type, data, 0, true);
}

pub inline fn makeUnreliable(packet_type: Type, data: anytype) Packet {
    return make(packet_type, data, 0, false);
}

pub inline fn makeReliableWithPriority(packet_type: Type, data: anytype, prio: u8) Packet {
    return make(packet_type, data, prio, true);
}

pub inline fn makeUnreliableWithPriority(packet_type: Type, data: anytype, prio: u8) Packet {
    return make(packet_type, data, prio, false);
}

pub fn make(packet_type: Type, data: anytype, prio: u8, reliable: bool) Packet {
    var packet: Packet = .{
        .prio = prio,
        .reliable = reliable,
    };
    comptime {
        assert(@sizeOf(@TypeOf(data)) + @sizeOf(Type) <= packet.buf.len);
    }
    std.mem.set(u8, &packet.buf, 0);
    std.mem.copy(u8, &packet.buf, std.mem.asBytes(&packet_type));
    std.mem.copy(u8, packet.buf[@sizeOf(Type)..], std.mem.asBytes(&data));
    return packet;
}

pub fn get(self: *const Packet, comptime T: type) T {
    return std.mem.bytesToValue(T, self.buf[@sizeOf(Type) .. @sizeOf(Type) + @sizeOf(T)]);
}

pub fn is(self: *const Packet, packet_type: Type) bool {
    return self.getType() == packet_type;
}

pub fn getType(self: *const Packet) Type {
    return std.mem.bytesToValue(Type, self.buf[0..@sizeOf(Type)]);
}
