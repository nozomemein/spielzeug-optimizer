const std = @import("std");

// SSA ID
const ValueId = u32; // type alias

// Insn (minimal)
const Insn = union(enum) {
    const_: struct { dst: ValueId, value: i64 },
    add: struct { dst: ValueId, lhs: ValueId, rhs: ValueId },
    sub: struct { dst: ValueId, lhs: ValueId, rhs: ValueId },
    mul: struct { dst: ValueId, lhs: ValueId, rhs: ValueId },
    div: struct { dst: ValueId, lhs: ValueId, rhs: ValueId },
    copy: struct { dst: ValueId, value: ValueId },
    ret: struct { dst: ValueId },
};

// Basic Block ID
const BlockId = u32; // type alias
// just BB
const BasicBlock = struct {
    id: BlockId,
    allocator: std.mem.Allocator,
    insns: std.ArrayList(Insn),

    pub fn init(allocator: std.mem.Allocator, id: BlockId) BasicBlock {
        return .{ .insns = .empty, .allocator = allocator, .id = id };
    }

    pub fn push_insn(self: *@This(), insn: Insn) !void {
        try self.insns.append(self.allocator, insn);
    }

    // Optional if we want to release manually
    // pub fn deinit(self: *BasicBlock) void {
    //   self.insns.deinit;
    // }
};

// Function which holds array of blocks
const Function = struct {
    allocator: std.mem.Allocator,
    blocks: std.ArrayList(BasicBlock),

    pub fn init(allocator: std.mem.Allocator) Function {
        return .{ .blocks = .empty, .allocator = allocator };
    }

    pub fn push_block(self: *@This(), block: BasicBlock) !void {
        try self.blocks.append(self.allocator, block);
    }

    pub fn pusn_insn(self: *@This(), block_id: BlockId, insn: Insn) !void {
        // TODO: handle block id correctly
        // TODO: increment SSA ID
        std.debug.print("block id: {d}", .{block_id});
        try self.blocks.items[0].push_insn(insn);
    }
};

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    var function = Function.init(arena);
    const bb = BasicBlock.init(arena, 1);
    try function.push_block(bb);
    try function.pusn_insn(bb.id, .{ .const_ = .{ .dst = 1, .value = 10 } });
    try function.pusn_insn(bb.id, .{ .const_ = .{ .dst = 2, .value = 5 } });
    try function.pusn_insn(bb.id, .{ .add = .{ .dst = 3, .lhs = 1, .rhs = 2 } });

    for (function.blocks.items[0].insns.items) |insn| {
        std.debug.print("{}\n", .{insn});
    }
}
