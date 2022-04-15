const std = @import("std");

// this ECS sets the following parameters:
// - each entity may only have one of each type of component.
//   if more than one is needed, an aggregate component should be
//   implemented. Example: "I need multiple `ScriptComponent`s!"
//   Solution: one "ScriptArrayComponent", or similar
// - the amount of unique component types is not limited by this
//   implementation

fn EntityImpl(comptime CompTypeT: type) type {
    return struct {
        const Self = @This();
        // indices into ECS.comps[comptype][]
        const CompCollection = std.AutoHashMap(CompTypeT, usize);

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

        pub fn addOrReplaceComponent(self: *Self, comptype: CompTypeT, index: usize) !void {
            var res = try self.comps.getOrPut(comptype);
            if (res.found_existing) {
                std.log.warn("replacing component type {} on {}!", .{ comptype, self.id });
            }
            res.value_ptr.* = index;
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

        pub fn getComponent(self: *Self, entity_id: EntityId, comptype: CompTypeT) ?*CompT {
            if (!self.isAnyLocked()) unreachable;
            var entity: *Entity = &(self.entities.items[entity_id.index]);
            var comps = self.comps.get(comptype);
            var comp_id = entity.comps.get(comptype);
            if (comps != null and comp_id != null) {
                return &comps.?.items[comp_id.?];
            }
            return null;
        }

        pub fn isValidEntity(self: *Self, entity_id: EntityId) bool {
            return entity_id.index > self.entities.items.len;
        }

        pub fn getAllComponentsOfType(self: *Self, comptype: CompTypeT) []CompT {
            const maybe_comps = self.comps.get(comptype);
            if (maybe_comps) |comps| {
                return comps.items;
            } else {
                return &[_]CompT{};
            }
        }

        pub fn forEachComponent(self: *Self, comptype: CompTypeT, func: fn (*CompT) void) void {
            if (!self.isUniqueLocked()) unreachable;
            for (self.comps.get(comptype)) |comp| {
                func(&comp);
            }
        }

        pub fn forEachComponentReadonly(self: *const Self, comptype: CompTypeT, func: fn (*const CompT) void) void {
            if (!self.isAnyLocked()) unreachable;
            for (self.comps.get(comptype)) |comp| {
                func(&comp);
            }
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
        pub fn addOrReplaceComponent(self: *Self, entity_id: EntityId, comptype: CompTypeT, comp: CompT) anyerror!*CompT {
            if (!self.isUniqueLocked()) unreachable;
            // find the entity first, then make the component, then add it to the entity
            if (self.isValidEntity(entity_id)) {
                return error.EntityNotFound;
            }
            var entity: *Entity = &self.entities.items[entity_id.index];
            var array = try self.comps.getOrPut(comptype);
            if (!array.found_existing) {
                array.value_ptr.* = CompArray.init(self.allocator);
            }
            var new_comp = try array.value_ptr.addOne();
            new_comp.* = comp;
            try entity.addOrReplaceComponent(comptype, array.value_ptr.*.items.len - 1);
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
