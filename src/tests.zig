//! Test root.
//!
//! Zig collects `test` blocks only from the root file of a test binary,
//! so each file carrying them is named explicitly here.

test {
    _ = @import("clause.zig");
    _ = @import("delete.zig");
    _ = @import("insert.zig");
    _ = @import("meta.zig");
    _ = @import("operators.zig");
    _ = @import("orm.zig");
    _ = @import("query.zig");
    _ = @import("result.zig");
    _ = @import("schema.zig");
    _ = @import("sql.zig");
    _ = @import("update.zig");
}
