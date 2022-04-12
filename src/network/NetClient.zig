const std = @import("std");
const network = @import("zig-network/network.zig");

pub fn NetClient(comptime PacketT: type) type {
    return struct {
        const Self = @This();
        tcp: std.net.Stream,
        udp: network.Socket,
        read_thread: std.Thread,
        udp_read_thread: std.Thread,
        write_thread: std.Thread,
        queues: InternalQueues,
        shutdown: bool = false,

        fn packetPrioCompare(context: void, a: PacketT, b: PacketT) std.math.Order {
            _ = context;
            return std.math.order(a.prio, b.prio);
        }

        fn assert(ok: bool) void {
            if (!ok) unreachable; // assertion failure
        }

        const InternalQueues = struct {
            write_queue: std.PriorityQueue(PacketT, void, packetPrioCompare),
            write_queue_cnd: std.Thread.Condition,
            write_queue_mtx: std.Thread.Mutex,
            read_queue: std.TailQueue(PacketT),
            read_queue_mtx: std.Thread.Mutex,
            allocator: std.mem.Allocator,

            fn init(allocator: std.mem.Allocator) InternalQueues {
                return .{
                    .allocator = allocator,
                    .write_queue = std.PriorityQueue(PacketT, void, packetPrioCompare).init(allocator, void{}),
                    .write_queue_cnd = .{},
                    .write_queue_mtx = .{},
                    .read_queue = .{},
                    .read_queue_mtx = .{},
                };
            }

            fn enqueueWrite(self: *InternalQueues, packet: PacketT) !void {
                self.write_queue_mtx.lock();
                defer self.write_queue_mtx.unlock();
                defer self.write_queue_cnd.signal();
                try self.write_queue.add(packet);
            }

            fn dequeueWriteUnsafe(self: *InternalQueues) ?PacketT {
                return self.write_queue.removeOrNull();
            }

            fn enqueueRead(self: *InternalQueues, packet: PacketT) !void {
                self.read_queue_mtx.lock();
                defer self.read_queue_mtx.unlock();
                var node = try self.allocator.create(std.TailQueue(PacketT).Node);
                node.data = packet;
                self.read_queue.append(node);
            }

            fn dequeueRead(self: *InternalQueues) ?PacketT {
                self.read_queue_mtx.lock();
                defer self.read_queue_mtx.unlock();
                var node = self.read_queue.popFirst();
                if (node == null) {
                    return null;
                } else {
                    var packet = node.?.data;
                    self.allocator.destroy(node.?);
                    return packet;
                }
            }
        };

        pub fn init(allocator: std.mem.Allocator, addr: []const u8, port: u16) !Self {
            var client: Self = .{
                .tcp = try std.net.tcpConnectToHost(allocator, addr, port),
                .udp = try network.connectToHost(allocator, addr, port, .udp),
                .read_thread = undefined,
                .udp_read_thread = undefined,
                .write_thread = undefined,
                .queues = InternalQueues.init(allocator),
            };

            return client;
        }

        pub fn startThreads(self: *Self) !void {
            self.read_thread = try std.Thread.spawn(.{}, readThreadMain, .{self});
            self.udp_read_thread = try std.Thread.spawn(.{}, readUdpThreadMain, .{self});
            self.write_thread = try std.Thread.spawn(.{}, writeThreadMain, .{self});
        }

        pub fn writePacket(self: *Self, packet: PacketT) !void {
            try self.queues.enqueueWrite(packet);
        }

        // pops a read packet from an internal queue, will return immediately
        pub fn getReadPacket(self: *Self) ?PacketT {
            return self.queues.dequeueRead();
        }

        fn readThreadMain(client: *Self) !void {
            while (!client.shutdown) {
                var packet: PacketT = .{};
                const n = try client.tcp.read(&packet.buf);
                if (n != packet.buf.len) {
                    return error.ReadError;
                }
                try client.queues.enqueueRead(packet);
            }
        }

        fn readUdpThreadMain(client: *Self) !void {
            while (!client.shutdown) {
                var packet: PacketT = .{};
                const n = try client.udp.reader().read(&packet.buf);
                if (n != packet.buf.len) {
                    return error.ReadError;
                }
                try client.queues.enqueueRead(packet);
            }
        }

        fn writeThreadMain(client: *Self) !void {
            while (!client.shutdown) {
                client.queues.write_queue_mtx.lock();
                var maybe_packet: ?PacketT = null;
                while (maybe_packet == null) {
                    if (client.queues.dequeueWriteUnsafe()) |the_packet| {
                        maybe_packet = the_packet;
                    } else {
                        client.queues.write_queue_cnd.wait(&client.queues.write_queue_mtx);
                    }
                }
                client.queues.write_queue_mtx.unlock();
                var packet = maybe_packet.?;
                if (packet.reliable) {
                    const n = try client.tcp.writer().write(&packet.buf);
                    if (n != packet.buf.len) {
                        std.log.err("failed to send expected number of bytes via tcp", .{});
                    }
                } else {
                    const n = try client.udp.writer().write(&packet.buf);
                    if (n != packet.buf.len) {
                        std.log.err("failed to send expected number of bytes via udp", .{});
                    }
                }
            }
        }
    };
}
