const std = @import("std");
const print = std.debug.print;

// Function which holds array of blocks
const Function = struct {
    allocator: std.mem.Allocator,
    blocks: std.ArrayList(BasicBlock),
    insns: std.ArrayList(Insn),

    fn init(allocator: std.mem.Allocator) @This() {
        return .{ .blocks = .empty, .insns = .empty, .allocator = allocator };
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
        if (block_id >= self.insns.items.len) {
            return error.BlockNotFound;
        }
        try self.blocks.items[block_id].push_insn(insn_id, self.allocator);
        return insn_id;
    }

    fn dump_ir(self: *const @This()) void {
        for (self.blocks.items, 0..) |block, block_id| {
            std.debug.print("bb{d}()\n", .{block_id});
            for (block.insns.items) |insn_id| {
                const insn = self.insns.items[insn_id];
                try dump_insn(insn_id, insn);
            }
        }
    }

    fn dump_insn(insn_id: InsnId, insn: Insn) !void {
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
            else => {
                print("  v{d} = {}\n", .{ insn_id, insn });
            },
        }
    }

    // TODO: Add RPO
    // fn rpo(self: @This()) !void {}

    // fn run_lvn(self: *@This()) !void {
    //     for (self.blocks.items, 0..) |block, block_id| {}
    // }
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
    ret: struct {},
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
    const val1 = try function.push_insn(bb, .{ .const_ = .{ .value = 10 } });
    const val2 = try function.push_insn(bb, .{ .const_ = .{ .value = 5 } });
    _ = try function.push_insn(bb, .{ .add = .{ .lhs = val1, .rhs = val2 } });

    function.dump_ir();
    // function.run_lvn();
    function.dump_ir();
}
