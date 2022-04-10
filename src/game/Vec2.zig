const std = @import("std");
const Vec2 = @This();

x: f32 = 0.0,
y: f32 = 0.0,

inline fn approxEq(comptime T: type, a: T, b: T) bool {
    return std.math.approxEqRel(f32, a, b, std.math.sqrt(std.math.epsilon(T)));
}

pub inline fn dot(self: *const Vec2, v: Vec2) f32 {
    return self.x * v.x + self.y * v.y;
}

test "Vec2 dot perpendicular" {
    const a: Vec2 = .{ .x = 1, .y = 0 };
    const b: Vec2 = .{ .x = 0, .y = 1 };
    try std.testing.expect(approxEq(f32, a.dot(b), 0));
}

test "Vec2 dot not perpendicular" {
    const a: Vec2 = .{ .x = 1, .y = 0 };
    const b: Vec2 = .{ .x = 1, .y = 2 };
    try std.testing.expect(!approxEq(f32, a.dot(b), 0.0));
}

pub inline fn div(self: *const Vec2, s: f32) Vec2 {
    return Vec2{
        .x = self.x / s,
        .y = self.y / s,
    };
}

test "Vec2 div" {
    const a: Vec2 = .{ .x = 2, .y = 4 };
    var res = a.div(2.0);
    try std.testing.expect(approxEq(f32, res.x, 1));
    try std.testing.expect(approxEq(f32, res.y, 2));
}

test "Vec2 div zero" {
    const a: Vec2 = .{ .x = 1, .y = 1 };
    var res = a.div(0.0);
    try std.testing.expect(std.math.isInf(res.x));
    try std.testing.expect(std.math.isInf(res.y));
}

pub inline fn mult(self: *const Vec2, s: f32) Vec2 {
    return Vec2{
        .x = self.x * s,
        .y = self.y * s,
    };
}

test "Vec2 mult" {
    const a: Vec2 = .{ .x = 5, .y = 5 };
    try std.testing.expect(approxEq(f32, a.mult(2).x, 10.0));
    try std.testing.expect(approxEq(f32, a.mult(2).y, 10.0));
}

pub inline fn sub(self: *const Vec2, v: Vec2) Vec2 {
    return Vec2{
        .x = self.x - v.x,
        .y = self.y - v.y,
    };
}

test "Vec2 sub" {
    const a: Vec2 = .{ .x = 15, .y = 15 };
    try std.testing.expect(a.sub(a).x == 0);
    try std.testing.expect(a.sub(a).y == 0);
}

pub inline fn length(self: *const Vec2) f32 {
    return std.math.sqrt(self.x * self.x + self.y * self.y);
}

test "Vec2 length" {
    const a: Vec2 = .{ .x = 2, .y = 2 };
    try std.testing.expect(approxEq(f32, a.length(), std.math.sqrt(2.0 * 2.0 + 2.0 * 2.0)));
}

test "Vec2 length zero" {
    const a: Vec2 = .{ .x = 0, .y = 0 };
    try std.testing.expect(approxEq(f32, a.length(), 0.0));
}

pub inline fn normalized(self: *const Vec2) Vec2 {
    return self.div(self.length());
}

test "Vec2 normalized" {
    const a: Vec2 = .{ .x = 2, .y = 2 };
    try std.testing.expect(approxEq(f32, a.normalized().x, 1.0 / std.math.sqrt(2.0)));
    try std.testing.expect(approxEq(f32, a.normalized().y, 1.0 / std.math.sqrt(2.0)));
}

/// n must be normalized
pub inline fn reflected(self: *const Vec2, n: Vec2) Vec2 {
    return self.sub(n.mult(self.dot(n)).mult(2.0));
}

test "Vec2 reflected" {
    const a: Vec2 = .{ .x = 2, .y = 1 };
    const n: Vec2 = .{ .x = -1, .y = 0 };
    try std.testing.expect(approxEq(f32, a.reflected(n).x, -2.0));
    try std.testing.expect(approxEq(f32, a.reflected(n).y, 1.0));
}
