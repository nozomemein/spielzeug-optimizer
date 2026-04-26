const std = @import("std");

// Function which holds array of blocks
const Function = struct {
    allocator: std.mem.Allocator,
    blocks: std.ArrayList(BasicBlock),
    insns: std.ArrayList(Insn),

    fn init(allocator: std.mem.Allocator) Function {
        return .{ .blocks = .empty, .insns = .empty, .allocator = allocator };
    }

    fn create_block(self: *@This()) !BlockId {
      const block_id = self.blocks.items.len;
      try self.push_block(BasicBlock.init(block_id));
      return block_id;
    }

    fn push_block(self: *@This(), block: BasicBlock) !void {
        try self.blocks.append(self.allocator, block);
    }

    fn pusn_insn(self: *@This(), block_id: BlockId, insn: Insn) !InsnId {
        const insn_id = self.insns.items.len;
        try self.insns.append(self.allocator, insn);
        try self.blocks.items[block_id].push_insn(insn_id, self.allocator);
        return insn_id;
    }

    fn dump_ir(self: @This()) !void {
        for (self.blocks.items) |block| {
            std.debug.print("bb{d}()\n", .{block.id});
            for (block.insns.items) |insn_id| {
                // TODO: Refine format
                const insn = self.insns.items[insn_id];
                std.debug.print("  v{d} = {}\n", .{insn_id, insn});
            }
        }
    }
};

// SSA ID
const InsnId = usize; // type alias

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
    id: BlockId,
    insns: std.ArrayList(InsnId),

    fn init(id: BlockId) BasicBlock {
        return .{ .insns = .empty, .id = id };
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
    const val1 = try function.pusn_insn(bb, .{ .const_ = .{ .value = 10 } });
    const val2 = try function.pusn_insn(bb, .{ .const_ = .{ .value = 5 } });
    _ = try function.pusn_insn(bb, .{ .add = .{ .lhs = val1, .rhs = val2 } });

    try function.dump_ir();
    // for (function.blocks.items[0].insns.items) |insn| {
    //     std.debug.print("{}\n", .{insn});
    // }
}
