const std = @import("std");

pub fn Packet(comptime T: type) type {
    return struct {
        const Self = @This();
        buf: [16]u8 = undefined,
        // priority of this packet, higher is higher priority, 0 is lowest / default
        prio: u8 = 0,
        reliable: bool = true,

        fn assert(ok: bool) void {
            if (!ok) unreachable; // assertion failure
        }

        pub inline fn makeReliable(packet_type: T, data: anytype) Self {
            return make(packet_type, data, 0, true);
        }

        pub inline fn makeUnreliable(packet_type: T, data: anytype) Self {
            return make(packet_type, data, 0, false);
        }

        pub inline fn makeReliableWithPriority(packet_type: T, data: anytype, prio: u8) Self {
            return make(packet_type, data, prio, true);
        }

        pub inline fn makeUnreliableWithPriority(packet_type: T, data: anytype, prio: u8) Self {
            return make(packet_type, data, prio, false);
        }

        pub fn make(packet_type: T, data: anytype, prio: u8, reliable: bool) Self {
            var packet: Self = .{
                .prio = prio,
                .reliable = reliable,
            };
            comptime {
                assert(@sizeOf(@TypeOf(data)) + @sizeOf(T) <= packet.buf.len);
            }
            std.mem.set(u8, &packet.buf, 0);
            std.mem.copy(u8, &packet.buf, std.mem.asBytes(&packet_type));
            std.mem.copy(u8, packet.buf[@sizeOf(T)..], std.mem.asBytes(&data));
            return packet;
        }

        pub fn get(self: *const Self, comptime ValueT: type) ValueT {
            return std.mem.bytesToValue(ValueT, self.buf[@sizeOf(T) .. @sizeOf(T) + @sizeOf(ValueT)]);
        }

        pub fn is(self: *const Self, packet_type: T) bool {
            return self.getType() == packet_type;
        }

        pub fn getType(self: *const Self) T {
            return std.mem.bytesToValue(T, self.buf[0..@sizeOf(T)]);
        }
    };
}
