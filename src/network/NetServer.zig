const std = @import("std");
const network = @import("zig-network/network.zig");

pub fn NetServer(comptime PacketT: type) type {
    return struct {
        const Self = @This();
        fn packetPrioCompare(context: void, a: PacketT, b: PacketT) std.math.Order {
            _ = context;
            std.log.debug("{} vs {}", .{ a, b });
            return std.math.order(a.prio, b.prio);
        }

        pub const Client = struct {
            tcp: network.Socket,
            send_queue: std.PriorityQueue(PacketT, void, packetPrioCompare),
            send_queue_mtx: std.Thread.Mutex,
            send_queue_cnd: std.Thread.Condition,
            read_thread: std.Thread,
            write_thread: std.Thread,
            dead: bool = false,

            end_point: ?network.EndPoint = null,

            pub fn writePacket(self: *Client, packet: PacketT) anyerror!void {
                if (!packet.reliable) unreachable;
                const n = try self.tcp.writer().write(&packet.buf);
                if (n != packet.buf.len) {
                    return error.WriteError;
                }
            }

            pub fn readPacketTcp(self: *Client) anyerror!PacketT {
                var packet: PacketT = .{};
                const n = try self.tcp.reader().read(&packet.buf);
                if (n != packet.buf.len) {
                    return error.ReadError;
                }
                return packet;
            }

            /// push packet to be sent, threadsafe
            pub fn pushSendPacket(self: *Client, packet: PacketT) !void {
                self.send_queue_mtx.lock();
                defer self.send_queue_mtx.unlock();
                try self.send_queue.add(packet);
                std.log.debug("pushed {}, count is now {}", .{ packet, self.send_queue.count() });
                self.send_queue_cnd.signal();
            }

            pub fn waitAndGetNextSendPacket(self: *Client) ?PacketT {
                self.send_queue_mtx.lock();
                self.send_queue_cnd.wait(&self.send_queue_mtx); // CONTINUE
                defer self.send_queue_mtx.unlock();
                std.log.debug("queue has {}", .{self.send_queue.count()});
                var node = self.send_queue.removeOrNull();
                std.log.debug("popped {}", .{node});
                if (node == null) {
                    return null;
                } else {
                    return node.?;
                }
            }

            pub fn getNextSendPacket(self: *Client) ?PacketT {
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

        const ClientList = std.SinglyLinkedList(Client);

        allocator: std.mem.Allocator,
        tcp_server: network.Socket,
        udp_server: network.Socket,
        udp_thread: std.Thread,
        clients: ClientList,
        endpoints: std.ArrayList(network.EndPoint),
        endpoints_mtx: std.Thread.Mutex = .{},
        clients_mtx: std.Thread.Mutex = .{},
        shutdown: bool = false,

        fn addClient(self: *Self, client: Client) !*Client {
            var node: *ClientList.Node = try self.allocator.create(ClientList.Node);
            node.data = client;
            self.clients_mtx.lock();
            defer self.clients_mtx.unlock();
            self.clients.prepend(node);
            std.log.debug("adding new client {}", .{client.tcp.getRemoteEndPoint()});
            return &node.data;
        }

        fn removeDeadClients(self: *Self) void {
            self.clients_mtx.lock();
            defer self.clients_mtx.unlock();
            var next = self.clients.first;
            while (next != null) {
                var node: *ClientList.Node = next.?;
                next = node.next;
                if (node.data.dead) {
                    self.clients.remove(node);
                }
            }
        }

        pub fn init(allocator: std.mem.Allocator, tcp_port: u16, udp_port: u16) !Self {
            network.init() catch {
                std.log.err("failed to init network, may not function properly", .{});
            };
            var server = Self{
                .allocator = allocator,
                .tcp_server = try network.Socket.create(.ipv6, .tcp),
                .udp_server = try network.Socket.create(.ipv6, .udp),
                .udp_thread = undefined,
                .clients = .{},
                .endpoints = std.ArrayList(network.EndPoint).init(allocator),
            };
            try server.tcp_server.enablePortReuse(true);
            try server.udp_server.enablePortReuse(true);
            // TCP init: bind(), listen()
            try server.tcp_server.bindToPort(tcp_port);
            try server.tcp_server.listen();
            // UDP init: bind()
            try server.udp_server.bindToPort(udp_port);

            return server;
        }

        pub fn deinit(self: *Self) void {
            while (self.clients.len() > 0) {
                var first = self.clients.popFirst();
                self.allocator.destroy(first.?);
            }
            network.deinit();
            self.tcp_server.close();
            self.udp_server.close();
            self.* = undefined;
        }

        // blocking
        pub fn start(self: *Self) !void {
            self.udp_thread = try std.Thread.spawn(.{}, udpThread, .{self});
            while (!self.shutdown) {
                var client = try self.accept();
                var client_ptr: *Client = try self.addClient(client);
                client_ptr.read_thread = try std.Thread.spawn(.{}, tcpReadThread, .{ self, client_ptr });
                client_ptr.write_thread = try std.Thread.spawn(.{}, tcpWriteThread, .{ self, client_ptr });
            }
        }

        fn accept(self: *Self) !Client {
            return Client{
                .tcp = try self.tcp_server.accept(),
                .send_queue = std.PriorityQueue(PacketT, void, packetPrioCompare).init(self.allocator, void{}),
                .send_queue_mtx = .{},
                .send_queue_cnd = .{},
                .read_thread = undefined,
                .write_thread = undefined,
            };
        }

        fn enqueueForAllUnsafe(self: *Self, packet: PacketT, ignore_client: *Client) void {
            var next = self.clients.first;
            while (next != null) {
                var client = &next.?.data;
                const cep: ?network.EndPoint = client.tcp.getRemoteEndPoint() catch null;
                const iep: ?network.EndPoint = ignore_client.tcp.getRemoteEndPoint() catch null;
                if (cep != null and iep != null and
                    cep.?.address.eql(iep.?.address) and
                    cep.?.port == iep.?.port)
                {
                    // not sending to "ignore"
                } else {
                    client.pushSendPacket(packet) catch unreachable;
                    std.log.debug("enqueued {} on {}", .{ packet, client.tcp.getRemoteEndPoint() });
                }
                next = next.?.next;
            }
        }

        fn tcpWriteThread(server: *Self, client: *Client) void {
            std.log.info("write thread for {} started", .{client.tcp.getRemoteEndPoint()});
            while (!client.dead and !server.shutdown) {
                if (client.waitAndGetNextSendPacket()) |first_packet_to_send| {
                    std.log.debug("{} <- packet", .{client.tcp.getRemoteEndPoint()});
                    client.writePacket(first_packet_to_send) catch {
                        std.log.err("failed to send {} to {}", .{ first_packet_to_send, client.tcp.getRemoteEndPoint() });
                        client.dead = true;
                        break;
                    };
                } else {
                    std.log.debug("woken up, but no packet available", .{});
                }
            }
            std.log.info("write thread for {} terminated", .{client.tcp.getRemoteEndPoint()});
            server.removeDeadClients();
        }

        fn tcpReadThread(server: *Self, client: *Client) void {
            std.log.info("read thread for {} started", .{client.tcp.getRemoteEndPoint()});
            while (!client.dead and !server.shutdown) {
                var packet: PacketT = client.readPacketTcp() catch {
                    std.log.err("failed to recv from {}", .{client.tcp.getRemoteEndPoint()});
                    client.dead = true;
                    break;
                };
                std.log.debug("packet -> {}", .{client.tcp.getRemoteEndPoint()});
                server.clients_mtx.lock();
                server.enqueueForAllUnsafe(packet, client);
                server.clients_mtx.unlock();
            }
            std.log.info("read thread for {} terminated", .{client.tcp.getRemoteEndPoint()});
            server.removeDeadClients();
        }

        fn udpThread(server: *Self) !void {
            while (!server.shutdown) {
                var packet: PacketT = .{};
                var recv = try server.udp_server.receiveFrom(&packet.buf);
                server.endpoints_mtx.lock();
                defer server.endpoints_mtx.unlock();
                var found = false;
                for (server.endpoints.items) |ep| {
                    if (ep.address.eql(recv.sender.address) and ep.port == recv.sender.port) {
                        found = true;
                    } else {
                        const n = try server.udp_server.sendTo(ep, &packet.buf);
                        if (n != packet.buf.len) {
                            std.log.err("failed to send {} to {}, sent only {}/{} bytes", .{ packet, ep, n, packet.buf.len });
                        }
                    }
                }
                if (!found) {
                    std.log.debug("added new udp endpoint: {}", .{recv.sender});
                    try server.endpoints.append(recv.sender);
                }
            }
        }
    };
}
