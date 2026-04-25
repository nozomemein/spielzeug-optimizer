const std = @import("std");

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
    insns: std.ArrayList(Insn), // FIXME: This should be ArrayList(InsnId)

    pub fn init(id: BlockId) BasicBlock {
        return .{ .insns = .empty, .id = id };
    }

    pub fn push_insn(self: *@This(), insn: Insn, allocator: std.mem.Allocator) !void {
        try self.insns.append(allocator, insn);
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
    insns: std.ArrayList(Insn),

    pub fn init(allocator: std.mem.Allocator) Function {
        return .{ .blocks = .empty, .insns = .empty,  .allocator = allocator };
    }

    pub fn push_block(self: *@This(), block: BasicBlock) !void {
        try self.blocks.append(self.allocator, block);
    }

    pub fn pusn_insn(self: *@This(), block_id: BlockId, insn: Insn) !InsnId {
        const insn_id = self.insns.items.len;
        try self.blocks.items[block_id].push_insn(insn, self.allocator);
        return insn_id;
    }
};

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    var function = Function.init(arena);
    const bb = BasicBlock.init(0);
    try function.push_block(bb);
    try function.pusn_insn(bb.id, .{ .const_ = .{ .value = 10 } });
    try function.pusn_insn(bb.id, .{ .const_ = .{ .value = 5 } });
    try function.pusn_insn(bb.id, .{ .add = .{ .lhs = 1, .rhs = 2 } });

    for (function.blocks.items[0].insns.items) |insn| {
        std.debug.print("{}\n", .{insn});
    }
}
