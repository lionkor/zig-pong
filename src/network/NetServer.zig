const std = @import("std");
const NetServer = @This();
const Packet = @import("Packet.zig");
const network = @import("zig-network/network.zig");

fn packetPrioCompare(context: void, a: Packet, b: Packet) std.math.Order {
    _ = context;
    return std.math.order(a.prio, b.prio);
}

const Client = struct {
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

tcp_server: network.Socket,
udp_server: network.Socket,
clients: std.ArrayList(Client),
clients_mtx: std.Thread.Mutex,
endpoints: std.ArrayList(Client),
endpoints_mtx: std.Thread.Mutex,
allocator: std.mem.Allocator,

fn addClient(self: *NetServer, client: Client) !void {
    self.clients_mtx.lock();
    defer self.clients_mtx.unlock();
    try self.clients.append(client);
}

pub fn init(allocator: std.mem.Allocator, tcp_port: u16, udp_port: u16) NetServer {
    network.init() catch {
        std.log.err("failed to init network, may not function properly", .{});
    };
    var server = NetServer{
        .tcp_server = network.Socket.create(.ipv6, .tcp),
        .udp_server = network.Socket.create(.ipv6, .udp),
        .clients = std.ArrayList(Client).init(allocator),
    };
    // TCP init: bind(), listen()
    try server.tcp_server.bindToPort(tcp_port);
    try server.tcp_server.listen();
    // UDP init: bind()
    try server.udp_server.bindToPort(udp_port);
    return server;
}

pub fn deinit(self: *NetServer) void {
    self.clients.deinit();
    network.deinit();
    self.tcp_server.deinit();
    self.* = undefined;
}

// blocking
pub fn start(self: *NetServer) void {
    while (true) {
        var client = self.accept();
        self.clients_mtx.lock();
        defer self.clients_mtx.unlock();
        self.clients.append(client);
    }
}

fn accept(
    self: *NetServer,
) !Client {
    return Client{
        .tcp = try self.tcp_server.accept(),
        .send_queue = std.PriorityQueue(Packet, void, packetPrioCompare).init(allocator, void{}),
        .send_queue_mtx = .{},
        .send_queue_cnd = .{},
    };
}

fn isEndpointKnown(self:*NetServer) void{
    return self.endpoints
}

fn udpSendThread(server: *NetServer) void {}

fn udpRecvThread(server: *NetServer) void {
    while (true) {
        var packet: Packet = .{};
        var recv = udp.receiveFrom(&packet.buf) catch unreachable;
    }
}
