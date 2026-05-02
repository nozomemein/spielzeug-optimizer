const std = @import("std");
const UnionFind = @import("union_find.zig").UnionFind(InsnId);

// Function which holds array of blocks
const Function = struct {
    allocator: std.mem.Allocator,
    blocks: std.ArrayList(BasicBlock),
    entry: BlockId,
    insns: std.ArrayList(Insn),
    union_find: UnionFind,

    fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .blocks = .empty,
            .entry = 0,
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

    fn set_terminator(self: *@This(), block_id: BlockId, term: Terminator) !void {
        if (block_id >= self.blocks.items.len) {
            return error.BlockNotFound;
        }
        self.blocks.items[block_id].set_terminator(term);
    }

    fn make_equal_to(self: *@This(), insn: InsnId, replacement: InsnId) !void {
        try self.union_find.make_equal_to(insn, replacement, self.allocator);
    }

    fn resolve_id(self: *const @This(), insn_id: InsnId) InsnId {
        return self.union_find.find_const(insn_id);
    }

    // Resolve this instruction and its operands through union-find.
    fn find_insn(self: *const @This(), insn_id: InsnId) Insn {
        const found_id = self.resolve_id(insn_id);
        const insn = self.insns.items[found_id];

        return switch (insn) {
            .add => |p| .{ .add = .{ .lhs = self.resolve_id(p.lhs), .rhs = self.resolve_id(p.rhs) } },
            .sub => |p| .{ .sub = .{ .lhs = self.resolve_id(p.lhs), .rhs = self.resolve_id(p.rhs) } },
            .mul => |p| .{ .mul = .{ .lhs = self.resolve_id(p.lhs), .rhs = self.resolve_id(p.rhs) } },
            .div => |p| .{ .div = .{ .lhs = self.resolve_id(p.lhs), .rhs = self.resolve_id(p.rhs) } },
            .copy => |p| .{ .copy = .{ .value = self.resolve_id(p.value) } },
            else => insn,
        };
    }

    fn dump_ir(self: *const @This(), writer: *std.Io.Writer) !void {
        const order = try self.rpo();
        for (order.items) |block_id| {
            const block = self.blocks.items[block_id];
            try writer.print("bb{d}()\n", .{block_id});
            for (block.insns.items) |insn_id| {
                const found_id = self.resolve_id(insn_id);
                // const raw_insn = self.insns.items[insn_id];
                if (found_id != insn_id) continue; // logically delete from the dump output
                const insn = self.find_insn(insn_id);
                try dump_insn(insn_id, insn, writer);
            }
            try self.dump_terminator(block.term, writer);
        }
    }

    fn dump_insn(insn_id: InsnId, insn: Insn, writer: *std.Io.Writer) !void {
        switch (insn) {
            .const_ => |payload| {
                try writer.print("  v{d} = Const Value({d})\n", .{ insn_id, payload.value });
            },
            .add => |payload| {
                try writer.print("  v{d} = Add v{d}, v{d}\n", .{ insn_id, payload.lhs, payload.rhs });
            },
            .sub => |payload| {
                try writer.print("  v{d} = Sub v{d}, v{d}\n", .{ insn_id, payload.lhs, payload.rhs });
            },
            .mul => |payload| {
                try writer.print("  v{d} = Mul v{d}, v{d}\n", .{ insn_id, payload.lhs, payload.rhs });
            },
            .div => |payload| {
                try writer.print("  v{d} = Div v{d}, v{d}\n", .{ insn_id, payload.lhs, payload.rhs });
            },
            else => {
                try writer.print("  v{d} = {}\n", .{ insn_id, insn });
            },
        }
    }

    fn dump_terminator(self: *const @This(), term: Terminator, writer: *std.Io.Writer) !void {
        switch (term) {
            .ret => |p| {
                const value = self.resolve_id(p.value);
                try writer.print("  Return v{d}\n", .{value});
            },
            .jump => |p| {
                try writer.print("  Jump bb{d}\n", .{p.target});
            },
            .branch => |p| {
                const cond = self.resolve_id(p.cond);
                try writer.print("  Branch v{d}, bb{d}, bb{d}\n", .{ cond, p.then_block, p.else_block });
            },
            else => {},
        }
    }

    fn rpo(self: *const @This()) !std.ArrayList(BlockId) {
        var visited = try std.DynamicBitSet.initEmpty(self.allocator, self.blocks.items.len);

        var order: std.ArrayList(BlockId) = .empty;

        try self.dfs_postorder(self.entry, &visited, &order);

        std.mem.reverse(BlockId, order.items);
        return order;
    }

    fn dfs_postorder(
        self: *const @This(),
        block_id: BlockId,
        visited: *std.DynamicBitSet,
        order: *std.ArrayList(BlockId),
    ) !void {
        if (visited.isSet(block_id)) return;

        visited.set(block_id);

        const block = self.blocks.items[block_id];

        switch (block.term) {
            .none => {},
            .ret => {},
            .jump => |p| {
                try self.dfs_postorder(p.target, visited, order);
            },
            .branch => |p| {
                try self.dfs_postorder(p.else_block, visited, order);
                try self.dfs_postorder(p.then_block, visited, order);
            },
        }

        try order.append(self.allocator, block_id);
    }

    // TODO Support GVN
    fn run_lvn(self: *@This()) !void {
        for ((try self.rpo()).items) |block_id| {
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

    // fn has_output(self: @This()) bool {
    //     return switch (self) {
    //         .ret => false,
    //         else => true,
    //     };
    // }
};

const Terminator = union(enum) {
    none,
    jump: struct { target: BlockId },
    ret: struct { value: InsnId },
    branch: struct {
        cond: InsnId,
        then_block: BlockId,
        else_block: BlockId,
    },
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
    term: Terminator,

    fn init() @This() {
        return .{
            .insns = .empty,
            .term = .none,
        };
    }

    fn push_insn(self: *@This(), insn: InsnId, allocator: std.mem.Allocator) !void {
        try self.insns.append(allocator, insn);
    }

    fn set_terminator(self: *@This(), term: Terminator) void {
        self.term = term;
    }

    // Optional if we want to release manually
    // fn deinit(self: *BasicBlock) void {
    //   self.insns.deinit;
    // }
};

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();

    // Preparing for stdout
    var buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &buffer);
    const stdout = &stdout_writer.interface;

    var function = Function.init(arena);
    const entry = try function.create_block();
    function.entry = entry;
    const val1 = try function.push_insn(entry, .{
        .const_ = .{ .value = 10 },
    });
    const val2 = try function.push_insn(entry, .{
        .const_ = .{ .value = 5 },
    });
    _ = try function.push_insn(entry, .{
        .add = .{ .lhs = val1, .rhs = val2 },
    });
    _ = try function.push_insn(entry, .{
        .add = .{ .lhs = val1, .rhs = val2 },
    });

    const jump_target = try function.create_block();
    try function.set_terminator(entry, .{
        .jump = .{ .target = jump_target },
    });

    const val3 = try function.push_insn(jump_target, .{
        .const_ = .{ .value = 15 },
    });
    try function.set_terminator(jump_target, .{
        .ret = .{ .value = val3 },
    });

    try function.dump_ir(stdout);
    try stdout.flush();
}

test "local value numbering" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

    var function = Function.init(arena_state.allocator());
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
    try function.set_terminator(bb, .{
        .ret = .{ .value = add2 },
    });

    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();

    try function.dump_ir(&out.writer);
    try std.testing.expectEqualStrings(
        \\bb0()
        \\  v0 = Const Value(10)
        \\  v1 = Const Value(5)
        \\  v2 = Add v0, v1
        \\  v3 = Add v0, v1
        \\  Return v3
        \\
    ,
        out.writer.buffered(),
    );
    out.clearRetainingCapacity();
    try function.run_lvn();
    try function.dump_ir(&out.writer);

    try std.testing.expectEqualStrings(
        \\bb0()
        \\  v0 = Const Value(10)
        \\  v1 = Const Value(5)
        \\  v2 = Add v0, v1
        \\  Return v2
        \\
    ,
        out.writer.buffered(),
    );
}

test "RPO" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

    var function = Function.init(arena_state.allocator());
    const entry = try function.create_block();
    const bb1 = try function.create_block();
    const bb2 = try function.create_block();
    const bb3 = try function.create_block();
    const cond = try function.push_insn(entry, .{
        .const_ = .{ .value = 1 },
    });
    try function.set_terminator(entry, .{
        .branch = .{ .cond = cond, .then_block = bb1, .else_block = bb2 },
    });
    try function.set_terminator(bb1, .{
        .jump = .{ .target = bb3 },
    });
    try function.set_terminator(bb2, .{
        .jump = .{ .target = bb3 },
    });
    const bb3val = try function.push_insn(bb3, .{
        .const_ = .{ .value = 5 },
    });
    try function.set_terminator(bb3, .{
        .ret = .{ .value = bb3val },
    });

    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();

    try function.dump_ir(&out.writer);
    try std.testing.expectEqualStrings(
        \\bb0()
        \\  v0 = Const Value(1)
        \\  Branch v0, bb1, bb2
        \\bb1()
        \\  Jump bb3
        \\bb2()
        \\  Jump bb3
        \\bb3()
        \\  v1 = Const Value(5)
        \\  Return v1
        \\
    ,
        out.writer.buffered(),
    );
    out.clearRetainingCapacity();
}
