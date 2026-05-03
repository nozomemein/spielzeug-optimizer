const std = @import("std");

pub fn UnionFind(comptime T: type) type {
    return struct {
        forwarded: std.ArrayList(?T),

        pub fn init() @This() {
            return .{ .forwarded = .empty };
        }

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            self.forwarded.deinit(allocator);
        }

        fn at(self: *const @This(), idx: T) ?T {
            if (idx >= self.forwarded.items.len) return null;
            return self.forwarded.items[idx];
        }

        fn set(
            self: *@This(),
            idx: T,
            target: T,
            allocator: std.mem.Allocator,
        ) !void {
            while (idx >= self.forwarded.items.len) {
                try self.forwarded.append(allocator, null);
            }

            if (idx != target) {
                self.forwarded.items[idx] = target;
            }
        }

        pub fn find(self: *@This(), insn: T, allocator: std.mem.Allocator) !T {
            const result = self.findConst(insn);
            if (result != insn) {
                // path compression
                try self.set(insn, result, allocator);
            }
            return result;
        }

        pub fn findConst(self: *const @This(), insn: T) T {
            var result = insn;
            while (true) {
                const next = self.at(result) orelse return result;
                std.debug.assert(result != next);
                result = next;
            }
        }

        pub fn makeEqualTo(
            self: *@This(),
            insn: T,
            target: T,
            allocator: std.mem.Allocator,
        ) !void {
            const found = try self.find(insn, allocator);
            try self.set(found, target, allocator);
        }
    };
}

test "find returns self" {
    var uf = UnionFind(usize).init();
    defer uf.deinit(std.testing.allocator);

    try std.testing.expectEqual(3, try uf.find(3, std.testing.allocator));
}

test "find transitive targets" {
    var uf = UnionFind(usize).init();
    defer uf.deinit(std.testing.allocator);

    try uf.makeEqualTo(3, 4, std.testing.allocator);
    try uf.makeEqualTo(4, 5, std.testing.allocator);
    try std.testing.expectEqual(5, try uf.find(3, std.testing.allocator));
    try std.testing.expectEqual(5, try uf.find(4, std.testing.allocator));
}

test "find path compression" {
    var uf = UnionFind(usize).init();
    defer uf.deinit(std.testing.allocator);

    try uf.makeEqualTo(3, 4, std.testing.allocator);
    try uf.makeEqualTo(4, 5, std.testing.allocator);
    try std.testing.expectEqual(4, uf.at(3).?);
    try std.testing.expectEqual(5, try uf.find(3, std.testing.allocator));
    try std.testing.expectEqual(5, uf.at(3).?);
}
