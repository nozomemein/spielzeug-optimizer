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

    pub fn create_block(self: *@This()) !BlockId {
        const block_id = self.blocks.items.len;
        try self.push_block(BasicBlock.init());
        return block_id;
    }

    fn push_block(self: *@This(), block: BasicBlock) !void {
        try self.blocks.append(self.allocator, block);
    }

    pub fn push_insn(self: *@This(), block_id: BlockId, insn: Insn) !InsnId {
        const insn_id = self.insns.items.len;
        try self.insns.append(self.allocator, insn);
        if (block_id >= self.blocks.items.len) {
            return error.BlockNotFound;
        }
        try self.blocks.items[block_id].push_insn(insn_id, self.allocator);
        return insn_id;
    }

    pub fn set_terminator(self: *@This(), block_id: BlockId, term: Terminator) !void {
        if (block_id >= self.blocks.items.len) {
            return error.BlockNotFound;
        }
        self.blocks.items[block_id].set_terminator(term);
    }

    pub fn make_equal_to(self: *@This(), insn: InsnId, replacement: InsnId) !void {
        try self.union_find.make_equal_to(insn, replacement, self.allocator);
    }

    fn resolve_id(self: *const @This(), insn_id: InsnId) InsnId {
        return self.union_find.find_const(insn_id);
    }

    // Resolve this instruction and its operands through union-find.
    pub fn find_insn(self: *const @This(), insn_id: InsnId) Insn {
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

    pub fn dump_ir(self: *const @This(), writer: *std.Io.Writer) !void {
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

    pub fn rpo(self: *const @This()) !std.ArrayList(BlockId) {
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

    // fn has_output(self: @This()) bool {
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
