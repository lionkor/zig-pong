const std = @import("std");
const NetServer = @This();
const Packet = @import("Packet.zig");
const network = @import("zig-network/network.zig");

fn packetPrioCompare(context: void, a: Packet, b: Packet) std.math.Order {
    _ = context;
    return std.math.order(a.prio, b.prio);
}

pub const Client = struct {
    tcp: std.net.StreamServer.Connection,
    send_queue: std.PriorityQueue(Packet, void, packetPrioCompare),
    send_queue_mtx: std.Thread.Mutex,
    send_queue_cnd: std.Thread.Condition,

    end_point: ?network.EndPoint = null,

    pub fn writePacket(self: *Client, packet: Packet) anyerror!void {
        if (!packet.reliable) unreachable;
        const n = try self.tcp.stream.write(&packet.buf);
        if (n != packet.buf.len) {
            return error.WriteError;
        }
    }

    pub fn readPacketTcp(self: *Client) anyerror!Packet {
        var packet: Packet = .{};
        const n = try self.tcp.stream.read(&packet.buf);
        if (n != packet.buf.len) {
            return error.ReadError;
        }
        return packet;
    }

    /// push packet to be sent, threadsafe
    pub fn pushSendPacket(self: *Client, packet: Packet) !void {
        self.send_queue_mtx.lock();
        defer self.send_queue_mtx.unlock();
        defer self.send_queue_cnd.signal();
        try self.send_queue.add(packet);
    }

    pub fn waitAndGetNextSendPacket(self: *Client) ?Packet {
        self.send_queue_mtx.lock();
        defer self.send_queue_mtx.unlock();
        self.send_queue_cnd.wait(&self.send_queue_mtx);
        var node = self.send_queue.removeOrNull();
        if (node == null) {
            return null;
        } else {
            return node.?;
        }
    }

    pub fn getNextSendPacket(self: *Client) ?Packet {
        self.send_queue_mtx.lock();
        defer self.send_queue_mtx.unlock();
        var node = self.send_queue.removeOrNull();
        if (node == null) {
            return null;
        } else {
            return node.?;
        }
    }
};

tcp_server: std.net.StreamServer,

pub fn init() NetServer {
    network.init() catch {
        std.log.err("failed to init network, may not function properly", .{});
    };
    return NetServer{
        .tcp_server = std.net.StreamServer.init(std.net.StreamServer.Options{
            .kernel_backlog = 2,
            .reuse_address = true,
        }),
    };
}

pub fn deinit(self: *NetServer) void {
    network.deinit();
    self.tcp_server.deinit();
    self.* = undefined;
}

pub fn start(self: *NetServer, port: u16) !void {
    var addr = std.net.Address.initIp4([4]u8{ 0, 0, 0, 0 }, port);
    try self.tcp_server.listen(addr);
}

pub fn accept(self: *NetServer, allocator: std.mem.Allocator) !Client {
    return Client{
        .tcp = try self.tcp_server.accept(),
        .send_queue = std.PriorityQueue(Packet, void, packetPrioCompare).init(allocator, void{}),
        .send_queue_mtx = .{},
        .send_queue_cnd = .{},
    };
}
