const std = @import("std");

pub fn UnionFind(comptime T: type) type {
    return struct {
        forwarded: std.ArrayList(?T),

        fn init() @This() {
            return .{ .forwarded = .empty };
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
            if (idx >= self.forwarded.items[idx]) {
                try self.forwarded.append(allocator, null);
            }

            if (idx != target) {
                self.forwarded.items[idx] = target;
            }
        }

        fn find(self: *@This(), insn: T, allocator: std.mem.Allocator) !T {
            const result = self.find_const(insn);
            if (result != insn) {
                // path compression
                try self.set(insn, result, allocator);
            }
            return result;
        }

        fn find_const(self: *const @This(), insn: T) T {
            var result = insn;
            while (true) {
                const next = self.at(result) orelse return result;
                std.debug.assert(result != next);
                result = next;
            }
        }

        fn make_equal_to(
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
