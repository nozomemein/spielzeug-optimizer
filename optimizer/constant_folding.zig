const std = @import("std");
const ir = @import("../ir.zig");

const Function = ir.Function;

pub const ConstantFolding = struct {
    function: *Function,

    pub fn init(function: *Function) @This() {
        return .{ .function = function };
    }

    pub fn run(self: *const @This()) !void {
        var order = try self.function.rpo();
        defer order.deinit(self.function.allocator);

        for (order.items) |block_id| {
            var new_insns: std.ArrayList(ir.InsnId) = .empty;
            errdefer new_insns.deinit(self.function.allocator);
            var old_insns = self.function.blocks.items[block_id].insns;

            for (old_insns.items) |insn_id| {
                const insn = self.function.findInsn(insn_id);

                switch (insn) {
                    .add => |p| {
                        if (try self.foldBin(insn_id, p.lhs, p.rhs, insn)) |folded_id| {
                            try new_insns.append(self.function.allocator, folded_id);
                            continue;
                        }
                    },
                    .sub => |p| {
                        if (try self.foldBin(insn_id, p.lhs, p.rhs, insn)) |folded_id| {
                            try new_insns.append(self.function.allocator, folded_id);
                            continue;
                        }
                    },
                    .div => |p| {
                        if (try self.foldBin(insn_id, p.lhs, p.rhs, insn)) |folded_id| {
                            try new_insns.append(self.function.allocator, folded_id);
                            continue;
                        }
                    },
                    .mul => |p| {
                        if (try self.foldBin(insn_id, p.lhs, p.rhs, insn)) |folded_id| {
                            try new_insns.append(self.function.allocator, folded_id);
                            continue;
                        }
                    },
                    else => {},
                }
                try new_insns.append(self.function.allocator, insn_id);
            }
            self.function.blocks.items[block_id].insns = new_insns;
            old_insns.deinit(self.function.allocator);
        }
    }
    fn constValue(self: *const @This(), insn_id: ir.InsnId) ?i64 {
        return switch (self.function.findInsn(insn_id)) {
            .constant => |p| p.value,
            else => null,
        };
    }

    fn foldBin(
        self: *const @This(),
        insn_id: ir.InsnId,
        lhs: ir.InsnId,
        rhs: ir.InsnId,
        op: ir.Insn,
    ) !?ir.InsnId {
        if (!op.isBinOp()) return error.NotBinOp;

        const lhsval = self.constValue(lhs) orelse return null;
        const rhsval = self.constValue(rhs) orelse return null;

        const value = switch (op) {
            .add => lhsval + rhsval,
            .sub => lhsval - rhsval,
            .mul => lhsval * rhsval,
            .div => if (rhsval == 0) return null else @divTrunc(lhsval, rhsval),
            else => unreachable,
        };

        const replacement_id = try self.function.newInsn(.{
            .constant = .{ .value = value },
        });

        try self.function.makeEqualTo(insn_id, replacement_id);
        return replacement_id;
    }
};
