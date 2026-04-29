const std = @import("std");
const print = std.debug.print;
const UnionFind = @import("union_find.zig").UnionFind(InsnId);

// Function which holds array of blocks
const Function = struct {
    allocator: std.mem.Allocator,
    blocks: std.ArrayList(BasicBlock),
    insns: std.ArrayList(Insn),
    union_find: UnionFind,

    fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .blocks = .empty,
            .insns = .empty,
            .union_find = UnionFind.init(),
        };
    }

    fn create_block(self: *@This()) !BlockId {
        const block_id = self.blocks.items.len;
        try self.push_block(BasicBlock.init());
        return block_id;
    }

    fn push_block(self: *@This(), block: BasicBlock) !void {
        try self.blocks.append(self.allocator, block);
    }

    fn push_insn(self: *@This(), block_id: BlockId, insn: Insn) !InsnId {
        const insn_id = self.insns.items.len;
        try self.insns.append(self.allocator, insn);
        if (block_id >= self.blocks.items.len) {
            return error.BlockNotFound;
        }
        try self.blocks.items[block_id].push_insn(insn_id, self.allocator);
        return insn_id;
    }

    fn make_equal_to(self: *@This(), insn: InsnId, replacement: InsnId) !void {
        try self.union_find.make_equal_to(insn, replacement, self.allocator);
    }

    fn resolve_id(self: *const @This(), insn_id: InsnId) InsnId {
        return self.union_find.find_const(insn_id);
    }

    fn find_insn(self: *const @This(), insn_id: InsnId) Insn {
        const found_id = self.resolve_id(insn_id);
        const insn = self.insns.items[found_id];

        return switch (insn) {
            .add => |p| .{ .add = .{ .lhs = self.resolve_id(p.lhs), .rhs = self.resolve_id(p.rhs) } },
            .sub => |p| .{ .sub = .{ .lhs = self.resolve_id(p.lhs), .rhs = self.resolve_id(p.rhs) } },
            .mul => |p| .{ .mul = .{ .lhs = self.resolve_id(p.lhs), .rhs = self.resolve_id(p.rhs) } },
            .div => |p| .{ .div = .{ .lhs = self.resolve_id(p.lhs), .rhs = self.resolve_id(p.rhs) } },
            .ret => |p| .{ .ret = .{ .value = self.resolve_id(p.value) } },
            .copy => |p| .{ .copy = .{ .value = self.resolve_id(p.value) } },
            else => insn,
        };
    }

    fn dump_ir(self: *const @This()) void {
        for (self.blocks.items, 0..) |block, block_id| {
            std.debug.print("bb{d}()\n", .{block_id});
            for (block.insns.items) |insn_id| {
                const found_id = self.resolve_id(insn_id);
                if (found_id != insn_id) continue; // logically delete from the dump output
                const insn = self.find_insn(insn_id);
                dump_insn(insn_id, insn);
            }
        }
    }

    fn dump_insn(insn_id: InsnId, insn: Insn) void {
        switch (insn) {
            .const_ => |payload| {
                print("  v{d} = Const Value({d})\n", .{ insn_id, payload.value });
            },
            .add => |payload| {
                print("  v{d} = Add v{d}, v{d}\n", .{ insn_id, payload.lhs, payload.rhs });
            },
            .sub => |payload| {
                print("  v{d} = Sub v{d}, v{d}\n", .{ insn_id, payload.lhs, payload.rhs });
            },
            .mul => |payload| {
                print("  v{d} = Mul v{d}, v{d}\n", .{ insn_id, payload.lhs, payload.rhs });
            },
            .div => |payload| {
                print("  v{d} = Div v{d}, v{d}\n", .{ insn_id, payload.lhs, payload.rhs });
            },
            .ret => |payload| {
                print("  Return v{d}\n", .{payload.value});
            },
            else => {
                print("  v{d} = {}\n", .{ insn_id, insn });
            },
        }
    }

    // TODO: Add RPO
    // fn rpo(self: @This()) !void {}

    fn run_lvn(self: *@This()) !void {
        for (self.blocks.items, 0..) |_, block_id| {
            try self.run_lvn_block(block_id);
        }
    }

    fn run_lvn_block(self: *@This(), block_id: BlockId) !void {
        var entries: std.ArrayList(LvnEntry) = .empty;
        const block = self.blocks.items[block_id];

        for (block.insns.items) |insn_id| {
            const insn = self.find_insn(insn_id);

            if (try self.key_from_insn(insn)) |key| {
                if (find_existing(entries.items, key)) |entry| {
                    try self.make_equal_to(insn_id, entry);
                } else {
                    try entries.append(self.allocator, .{ .key = key, .insn_id = insn_id });
                }
            }
        }
    }

    fn find_existing(entries: []const LvnEntry, key: ExprKey) ?InsnId {
        for (entries) |entry| {
            if (std.meta.eql(entry.key, key)) {
                return entry.insn_id;
            }
        }

        return null;
    }

    fn key_from_insn(self: *@This(), insn: Insn) !?ExprKey {
        return switch (insn) {
            .const_ => |payload| .{
                .const_ = payload.value,
            },
            .add => |payload| try self.bin_key(.add, payload.lhs, payload.rhs),
            .sub => |payload| try self.bin_key(.sub, payload.lhs, payload.rhs),
            .mul => |payload| try self.bin_key(.mul, payload.lhs, payload.rhs),
            .div => |payload| try self.bin_key(.div, payload.lhs, payload.rhs),
            else => null,
        };
    }

    fn bin_key(self: *@This(), op: BinOp, lhs_raw: InsnId, rhs_raw: InsnId) !ExprKey {
        const lhs = try self.union_find.find(lhs_raw, self.allocator);
        const rhs = try self.union_find.find(rhs_raw, self.allocator);

        // TODO: We could canonicalize here
        return .{ .bin = .{ .op = op, .lhs = lhs, .rhs = rhs } };
    }
};

// SSA ID
pub const InsnId = usize; // type alias

// Insn (minimal)
const Insn = union(enum) {
    const_: struct { value: i64 },
    add: struct { lhs: InsnId, rhs: InsnId },
    sub: struct { lhs: InsnId, rhs: InsnId },
    mul: struct { lhs: InsnId, rhs: InsnId },
    div: struct { lhs: InsnId, rhs: InsnId },
    copy: struct { value: InsnId },
    ret: struct { value: InsnId },
};

// LVN Part
const BinOp = enum {
    add,
    sub,
    mul,
    div,
};

const ExprKey = union(enum) {
    const_: i64,
    bin: struct {
        op: BinOp,
        lhs: InsnId,
        rhs: InsnId,
    },
};

const LvnEntry = struct {
    key: ExprKey, // TODO: We can use hash value ideally
    insn_id: InsnId,
};

// Basic Block ID
const BlockId = usize; // type alias
// just BB
const BasicBlock = struct {
    insns: std.ArrayList(InsnId),

    fn init() @This() {
        return .{
            .insns = .empty,
        };
    }

    fn push_insn(self: *@This(), insn: InsnId, allocator: std.mem.Allocator) !void {
        try self.insns.append(allocator, insn);
    }

    // Optional if we want to release manually
    // fn deinit(self: *BasicBlock) void {
    //   self.insns.deinit;
    // }
};

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    var function = Function.init(arena);
    const bb = try function.create_block();
    const val1 = try function.push_insn(bb, .{
        .const_ = .{ .value = 10 },
    });
    const val2 = try function.push_insn(bb, .{
        .const_ = .{ .value = 5 },
    });
    _ = try function.push_insn(bb, .{
        .add = .{ .lhs = val1, .rhs = val2 },
    });
    const add2 = try function.push_insn(bb, .{
        .add = .{ .lhs = val1, .rhs = val2 },
    });
    _ = try function.push_insn(bb, .{
        .ret = .{ .value = add2 },
    });

    function.dump_ir();
    try function.run_lvn();
    function.dump_ir();
}
