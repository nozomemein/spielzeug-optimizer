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
            try self.runBlock(block_id);
        }
    }

    fn runBlock(self: *const @This(), block_id: BlockId) !void {
        var entries: std.ArrayList(LvnEntry) = .empty;
        const block = self.function.blocks.items[block_id];

        for (block.insns.items) |insn_id| {
            const insn = self.function.findInsn(insn_id);

            if (try keyFromInsn(self.function, insn)) |key| {
                if (findExisting(entries.items, key)) |entry| {
                    try self.function.makeEqualTo(insn_id, entry);
                } else {
                    try entries.append(self.function.allocator, .{ .key = key, .insn_id = insn_id });
                }
            }
        }
    }
};

fn findExisting(entries: []const LvnEntry, key: ExprKey) ?InsnId {
    for (entries) |entry| {
        if (std.meta.eql(entry.key, key)) {
            return entry.insn_id;
        }
    }

    return null;
}

fn keyFromInsn(function: *Function, insn: Insn) !?ExprKey {
    return switch (insn) {
        .const_ => |payload| .{
            .const_ = payload.value,
        },
        .add => |payload| try binKey(function, .add, payload.lhs, payload.rhs),
        .sub => |payload| try binKey(function, .sub, payload.lhs, payload.rhs),
        .mul => |payload| try binKey(function, .mul, payload.lhs, payload.rhs),
        .div => |payload| try binKey(function, .div, payload.lhs, payload.rhs),
        else => null,
    };
}

fn binKey(function: *Function, op: BinOp, lhs_raw: InsnId, rhs_raw: InsnId) !ExprKey {
    const lhs = try function.union_find.find(lhs_raw, function.allocator);
    const rhs = try function.union_find.find(rhs_raw, function.allocator);

    // TODO: We could canonicalize here
    return .{ .bin = .{ .op = op, .lhs = lhs, .rhs = rhs } };
}
