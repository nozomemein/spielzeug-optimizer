const std = @import("std");
const UnionFind = @import("union_find.zig").UnionFind(InsnId);

// Function which holds array of blocks
pub const Function = struct {
    allocator: std.mem.Allocator,
    blocks: std.ArrayList(BasicBlock),
    entry: BlockId,
    insns: std.ArrayList(Insn),
    union_find: UnionFind,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .allocator = allocator,
            .blocks = .empty,
            .entry = 0,
            .insns = .empty,
            .union_find = UnionFind.init(),
        };
    }

    pub fn deinit(self: *@This()) void {
        const allocator = self.allocator;
        for (self.blocks.items) |*block| {
            block.deinit(allocator);
        }
        self.union_find.deinit(allocator);
        self.insns.deinit(allocator);
        self.blocks.deinit(allocator);
    }

    pub fn createBlock(self: *@This()) !BlockId {
        const block_id = self.blocks.items.len;
        try self.pushBlock(BasicBlock.init());
        return block_id;
    }

    fn pushBlock(self: *@This(), block: BasicBlock) !void {
        try self.blocks.append(self.allocator, block);
    }

    pub fn pushInsn(self: *@This(), block_id: BlockId, insn: Insn) !InsnId {
        const insn_id = self.insns.items.len;
        try self.insns.append(self.allocator, insn);
        if (block_id >= self.blocks.items.len) {
            return error.BlockNotFound;
        }
        try self.blocks.items[block_id].pushInsn(insn_id, self.allocator);
        return insn_id;
    }

    pub fn setTerminator(self: *@This(), block_id: BlockId, term: Terminator) !void {
        if (block_id >= self.blocks.items.len) {
            return error.BlockNotFound;
        }
        self.blocks.items[block_id].setTerminator(term);
    }

    pub fn makeEqualTo(self: *@This(), insn: InsnId, replacement: InsnId) !void {
        try self.union_find.makeEqualTo(insn, replacement, self.allocator);
    }

    fn resolveId(self: *const @This(), insn_id: InsnId) InsnId {
        return self.union_find.findConst(insn_id);
    }

    // Resolve this instruction and its operands through union-find.
    pub fn findInsn(self: *const @This(), insn_id: InsnId) Insn {
        const found_id = self.resolveId(insn_id);
        const insn = self.insns.items[found_id];

        return switch (insn) {
            .add => |p| .{ .add = .{ .lhs = self.resolveId(p.lhs), .rhs = self.resolveId(p.rhs) } },
            .sub => |p| .{ .sub = .{ .lhs = self.resolveId(p.lhs), .rhs = self.resolveId(p.rhs) } },
            .mul => |p| .{ .mul = .{ .lhs = self.resolveId(p.lhs), .rhs = self.resolveId(p.rhs) } },
            .div => |p| .{ .div = .{ .lhs = self.resolveId(p.lhs), .rhs = self.resolveId(p.rhs) } },
            .copy => |p| .{ .copy = .{ .value = self.resolveId(p.value) } },
            else => insn,
        };
    }

    pub fn dumpIr(self: *const @This(), writer: *std.Io.Writer) !void {
        const order = try self.rpo();
        for (order.items) |block_id| {
            const block = self.blocks.items[block_id];
            try writer.print("bb{d}()\n", .{block_id});
            for (block.insns.items) |insn_id| {
                const insn = self.findInsn(insn_id);
                try dumpInsn(insn_id, insn, writer);
            }
            try self.dumpTerminator(block.term, writer);
        }
    }

    fn dumpInsn(insn_id: InsnId, insn: Insn, writer: *std.Io.Writer) !void {
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

    fn dumpTerminator(self: *const @This(), term: Terminator, writer: *std.Io.Writer) !void {
        switch (term) {
            .ret => |p| {
                const value = self.resolveId(p.value);
                try writer.print("  Return v{d}\n", .{value});
            },
            .jump => |p| {
                try writer.print("  Jump bb{d}\n", .{p.target});
            },
            .branch => |p| {
                const cond = self.resolveId(p.cond);
                try writer.print("  Branch v{d}, bb{d}, bb{d}\n", .{ cond, p.then_block, p.else_block });
            },
            else => {},
        }
    }

    pub fn rpo(self: *const @This()) !std.ArrayList(BlockId) {
        var visited = try std.DynamicBitSet.initEmpty(self.allocator, self.blocks.items.len);

        var order: std.ArrayList(BlockId) = .empty;

        try self.dfsPostorder(self.entry, &visited, &order);

        std.mem.reverse(BlockId, order.items);
        return order;
    }

    fn dfsPostorder(
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
                try self.dfsPostorder(p.target, visited, order);
            },
            .branch => |p| {
                try self.dfsPostorder(p.else_block, visited, order);
                try self.dfsPostorder(p.then_block, visited, order);
            },
        }

        try order.append(self.allocator, block_id);
    }
};

// SSA ID
pub const InsnId = usize; // type alias

// Insn (minimal)
pub const Insn = union(enum) {
    const_: struct { value: i64 },
    add: struct { lhs: InsnId, rhs: InsnId },
    sub: struct { lhs: InsnId, rhs: InsnId },
    mul: struct { lhs: InsnId, rhs: InsnId },
    div: struct { lhs: InsnId, rhs: InsnId },
    copy: struct { value: InsnId },

    // fn hasOutput(self: @This()) bool {
    //     return switch (self) {
    //         .ret => false,
    //         else => true,
    //     };
    // }
};

pub const Terminator = union(enum) {
    none,
    jump: struct { target: BlockId },
    ret: struct { value: InsnId },
    branch: struct {
        cond: InsnId,
        then_block: BlockId,
        else_block: BlockId,
    },
};

// Basic Block ID
pub const BlockId = usize; // type alias
// just BB
pub const BasicBlock = struct {
    insns: std.ArrayList(InsnId),
    term: Terminator,

    fn init() @This() {
        return .{
            .insns = .empty,
            .term = .none,
        };
    }

    fn pushInsn(self: *@This(), insn: InsnId, allocator: std.mem.Allocator) !void {
        try self.insns.append(allocator, insn);
    }

    fn setTerminator(self: *@This(), term: Terminator) void {
        self.term = term;
    }

    fn deinit(self: *@This()) void {
        self.insns.deinit;
    }
};
