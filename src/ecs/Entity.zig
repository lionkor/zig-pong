const std = @import("std");

pub fn Entity(comptime CompTypeT: type, comptime CompT: type, comptime IdT: type) type {
    return struct {
        const Self = @This();
        const CompList = std.ArrayList(CompT);
        const CompCollection = std.AutoHashMap(CompT, CompList);

        // uniquely identifies this entity
        id: IdT,
        // components attached to this entity
        comps: CompCollection,

        allocator: std.mem.Allocator,

        pub fn init(id: IdT, allocator: std.mem.Allocator) !void {
            return CompCollection{
                .id = id,
                .comps = CompCollection.init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            var iter = self.comps.valueIterator();
            while (iter.next()) |item| {
                item.deinit();
            }
            self.comps.deinit();
        }

        pub fn addComponent(self: *Self, comptype: CompTypeT, comp: CompT) !void {
            var res = try self.comps.getOrPut(comptype);
            if (res.found_existing) {
                res.value_ptr.append(comp);
            } else {
                res.value_ptr.* = CompList.initCapacity(self.allocator, 1);
            }
        }

        pub fn getComponents(self: *Self, comptype: CompTypeT) ?[]CompT {
            var entry = self.comps.get(comptype);
            if (entry) {
                return entry.?.items;
            } else {
                return null;
            }
        }
    };
}
