const std = @import("std");
const NetServer = @This();
const Packet = @import("../Packet.zig");

pub const Client = struct {
    conn: std.net.StreamServer.Connection,
    sendQueue: std.ArrayList(Packet),
    sendQueueMtx: std.Thread.Mutex,

    pub fn writePacket(self: *Client, packet: Packet) anyerror!void {
        const n = try self.conn.stream.write(&packet.buf);
        if (n != packet.buf.len) {
            return error.WriteError;
        }
        //std.log.debug("sent: {}", .{packet});
    }

    pub fn readPacket(self: *Client) anyerror!Packet {
        var packet: Packet = .{};
        const n = try self.conn.stream.read(&packet.buf);
        if (n != packet.buf.len) {
            return error.ReadError;
        }
        //std.log.debug("received: {}", .{packet});
        return packet;
    }

    /// push packet to be sent, threadsafe
    pub fn pushSendPacket(self: *Client, packet: Packet) !void {
        self.sendQueueMtx.lock();
        defer self.sendQueueMtx.unlock();
        try self.sendQueue.insert(0, packet);
    }

    pub fn getNextSendPacket(self: *Client) ?Packet {
        self.sendQueueMtx.lock();
        defer self.sendQueueMtx.unlock();
        var node = self.sendQueue.popOrNull();
        if (node == null) {
            return null;
        } else {
            return node.?;
        }
    }
};

server: std.net.StreamServer,

pub fn init() NetServer {
    return NetServer{
        .server = std.net.StreamServer.init(std.net.StreamServer.Options{
            .kernel_backlog = 2,
            .reuse_address = true,
        }),
    };
}

pub fn deinit(self: *NetServer) void {
    self.server.deinit();
    self.* = undefined;
}

pub fn start(self: *NetServer, port: u16) !void {
    var addr = std.net.Address.initIp4([4]u8{ 0, 0, 0, 0 }, port);
    try self.server.listen(addr);
}

pub fn accept(self: *NetServer) !Client {
    return Client{
        .conn = try self.server.accept(),
        .sendQueue = std.ArrayList(Packet).init(std.heap.page_allocator),
        .sendQueueMtx = .{},
    };
}
