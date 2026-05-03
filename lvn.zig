const std = @import("std");
const ir = @import("ir.zig");

const Function = ir.Function;
const InsnId = ir.InsnId;
const Insn = ir.Insn;
const BlockId = ir.BlockId;

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

// TODO Support GVN
pub const LocalValueNumbering = struct {
    function: *Function,

    pub fn init(function: *Function) @This() {
        return .{ .function = function };
    }

    pub fn run(self: *const @This()) !void {
        for ((try self.function.rpo()).items) |block_id| {
            try self.run_block(block_id);
        }
    }

    fn run_block(self: *@This(), block_id: BlockId) !void {
        var entries: std.ArrayList(LvnEntry) = .empty;
        const block = self.function.blocks.items[block_id];

        for (block.insns.items) |insn_id| {
            const insn = self.function.find_insn(insn_id);

            if (try key_from_insn(self.function, insn)) |key| {
                if (find_existing(entries.items, key)) |entry| {
                    try self.function.make_equal_to(insn_id, entry);
                } else {
                    try entries.append(self.function.allocator, .{ .key = key, .insn_id = insn_id });
                }
            }
        }
    }
};

fn find_existing(entries: []const LvnEntry, key: ExprKey) ?InsnId {
    for (entries) |entry| {
        if (std.meta.eql(entry.key, key)) {
            return entry.insn_id;
        }
    }

    return null;
}

fn key_from_insn(function: *Function, insn: Insn) !?ExprKey {
    return switch (insn) {
        .const_ => |payload| .{
            .const_ = payload.value,
        },
        .add => |payload| try bin_key(function, .add, payload.lhs, payload.rhs),
        .sub => |payload| try bin_key(function, .sub, payload.lhs, payload.rhs),
        .mul => |payload| try bin_key(function, .mul, payload.lhs, payload.rhs),
        .div => |payload| try bin_key(function, .div, payload.lhs, payload.rhs),
        else => null,
    };
}

fn bin_key(function: *Function, op: BinOp, lhs_raw: InsnId, rhs_raw: InsnId) !ExprKey {
    const lhs = try function.union_find.find(lhs_raw, function.allocator);
    const rhs = try function.union_find.find(rhs_raw, function.allocator);

    // TODO: We could canonicalize here
    return .{ .bin = .{ .op = op, .lhs = lhs, .rhs = rhs } };
}
