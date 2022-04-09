const std = @import("std");
const Server = @This();
const Packet = @import("../Packet.zig");

pub const Client = struct {
    conn: std.net.StreamServer.Connection,
    sendQueue: std.TailQueue(Packet),
    sendQueueMtx: std.Thread.Mutex,

    pub fn writePacket(self: *Client, packet: Packet) anyerror!void {
        const n = try self.conn.stream.write(&packet.buf);
        if (n != packet.buf.len) {
            return error.WriteError;
        }
        std.log.debug("sent: {}", .{packet});
    }

    pub fn readPacket(self: *Client) anyerror!Packet {
        var packet: Packet = .{};
        const n = try self.conn.stream.read(&packet.buf);
        if (n != packet.buf.len) {
            return error.ReadError;
        }
        std.log.debug("received: {}", .{packet});
        return packet;
    }

    /// push packet to be sent, threadsafe
    pub fn pushSendPacket(self: *Client, packet: Packet) void {
        self.sendQueueMtx.lock();
        defer self.sendQueueMtx.unlock();
        self.sendQueue.append(&.{ .data = packet });
    }

    pub fn getNextSendPacket(self: *Client) ?Packet {
        self.sendQueueMtx.lock();
        defer self.sendQueueMtx.unlock();
        var node = self.sendQueue.popFirst();
        if (!node) {
            return null;
        } else {
            return node.?.data;
        }
    }
};

server: std.net.StreamServer,

pub fn init() Server {
    return Server{
        .server = std.net.StreamServer.init(std.net.StreamServer.Options{
            .kernel_backlog = 2,
            .reuse_address = true,
        }),
    };
}

pub fn deinit(self: *Server) void {
    self.server.deinit();
    self.* = undefined;
}

pub fn start(self: *Server, port: u16) !void {
    var addr = std.net.Address.initIp4([4]u8{ 127, 0, 0, 1 }, port);
    try self.server.listen(addr);
}

pub fn accept(self: *Server) !Client {
    return Client{
        .conn = try self.server.accept(),
        .sendQueue = .{},
        .sendQueueMtx = .{},
    };
}
