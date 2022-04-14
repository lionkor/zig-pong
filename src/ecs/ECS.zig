const std = @import("std");

fn EntityImpl(comptime CompTypeT: type) type {
    return struct {
        const Self = @This();
        // indices into ECS.comps[comptype][]
        const CompList = std.ArrayList(usize);
        const CompCollection = std.AutoHashMap(CompTypeT, CompList);

        // uniquely identifies this entity
        // index into ECS.entities[]
        id: usize,
        // components attached to this entity
        comps: CompCollection,

        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator, id: usize) !Self {
            return Self{
                .allocator = allocator,
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

        pub fn addComponent(self: *Self, comptype: CompTypeT, index: usize) !void {
            var res = try self.comps.getOrPut(comptype);
            if (!res.found_existing) {
                res.value_ptr.* = try CompList.initCapacity(self.allocator, 5); // TODO: Adjust this
            }
            try res.value_ptr.append(index);
        }
    };
}

pub const EntityId = struct {
    index: usize,
};

/// CompTypeT:  type, usually enum, describing which kind of component a component is
/// CompT:      type which implements a component
pub fn ECS(comptime CompTypeT: type, comptime CompT: type) type {
    return struct {
        const Self = @This();
        const Entity = EntityImpl(CompTypeT);
        const CompArray = std.ArrayList(CompT);
        const EntityArray = std.ArrayList(Entity);
        const CompTypeToArrayMap = std.AutoHashMap(CompTypeT, CompArray);

        comps: CompTypeToArrayMap,
        entities: EntityArray,

        mtx: std.Thread.RwLock = .{},
        is_shared_locked: bool = false,
        is_unique_locked: bool = false,

        allocator: std.mem.Allocator,

        pub inline fn lockShared(self: *Self) void {
            if (isAnyLocked(self)) self.deadlockWarn();
            self.mtx.lockShared();
            self.is_shared_locked = true;
            self.is_unique_locked = false;
        }

        pub inline fn unlockShared(self: *Self) void {
            if (!self.is_shared_locked) unreachable;
            self.is_shared_locked = false;
            self.is_unique_locked = false;
            self.mtx.unlockShared();
        }

        inline fn deadlockWarn(self: *Self) void {
            std.log.warn("ECS {p} is already locked (shared:{}, unique:{}), may deadlock", .{ self, self.is_shared_locked, self.is_unique_locked });
        }

        pub inline fn lockUnique(self: *Self) void {
            if (isAnyLocked(self)) self.deadlockWarn();
            self.mtx.lock();
            self.is_shared_locked = false;
            self.is_unique_locked = true;
        }

        pub inline fn unlockUnique(self: *Self) void {
            if (!self.is_unique_locked) unreachable;
            self.is_shared_locked = false;
            self.is_unique_locked = false;
            self.mtx.unlock();
        }

        inline fn isAnyLocked(self: *Self) bool {
            return self.is_shared_locked or self.is_unique_locked;
        }

        inline fn isUniqueLocked(self: *Self) bool {
            return self.is_unique_locked;
        }

        // will return array of pointers which may be invalidated on the next call to any ECS function
        // you need to free this yourself
        pub fn getComponents(self: *Self, entity_id: EntityId, comptype: CompTypeT) !?[]*CompT {
            if (!self.isAnyLocked()) unreachable;
            // count comps for this query
            if (entity_id.index > self.entities.items.len) {
                return error.EntityNotFound;
            }
            var entity: *Entity = &(self.entities.items[entity_id.index]);
            var maybe_comp_ids = entity.comps.get(comptype);
            if (maybe_comp_ids == null) {
                std.log.debug("tried to get components for entity {} with type '{}', but that type does not exist", .{ entity_id, comptype });
                return null;
            }
            var comp_ids = maybe_comp_ids.?.items;
            var maybe_comps = self.comps.get(comptype);
            if (maybe_comps == null) {
                std.log.debug("tried to get components for entity {} with type '{}', but didn't find any for this entity", .{ entity_id, comptype });
                return null;
            }
            std.log.debug("gathering {} components of type '{}' for entity {}", .{ comp_ids.len, comptype, entity_id });
            var comps: []*CompT = try self.allocator.alloc(*CompT, comp_ids.len);
            var i: usize = 0;
            for (comp_ids) |id| {
                comps[i] = &maybe_comps.?.items[id];
                i = i + 1;
            }
            return comps;
        }

        pub fn freeComponentsView(self: *Self, array: []*CompT) void {
            self.allocator.free(array);
        }

        // requires unique lock
        pub fn addEntity(self: *Self) !EntityId {
            if (!self.isUniqueLocked()) unreachable;
            var entity = try self.entities.addOne();
            const index = self.entities.items.len - 1;
            entity.* = try Entity.init(self.allocator, index);
            std.log.debug("entity created: {}", .{entity.id});
            return EntityId{ .index = index };
        }

        // requires unique lock
        // will return pointer which may be invalidated on the next call to any ECS function
        pub fn addComponent(self: *Self, entity_id: EntityId, comptype: CompTypeT, comp: CompT) anyerror!*CompT {
            if (!self.isUniqueLocked()) unreachable;
            // find the entity first, then make the component, then add it to the entity
            if (entity_id.index > self.entities.items.len) {
                return error.EntityNotFound;
            }
            var entity: *Entity = &self.entities.items[entity_id.index];
            var array = try self.comps.getOrPut(comptype);
            if (!array.found_existing) {
                array.value_ptr.* = CompArray.init(self.allocator);
            }
            var new_comp = try array.value_ptr.addOne();
            new_comp.* = comp;
            try entity.addComponent(comptype, array.value_ptr.*.items.len - 1);
            std.log.debug("added component {} of type {} to entity {}", .{ new_comp, comptype, entity.id });
            return new_comp;
        }

        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .allocator = allocator,
                .comps = CompTypeToArrayMap.init(allocator),
                .entities = EntityArray.init(allocator),
            };
        }
    };
}
