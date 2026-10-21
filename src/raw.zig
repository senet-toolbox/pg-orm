const std = @import("std");
const pg = @import("pg");
const sql = @import("sql.zig");
const result = @import("result.zig");
const query_mod = @import("query.zig");
const BoundedArray = @import("BoundedArray.zig").BoundedArray;
const meta = @import("meta.zig");

/// Raw SQL query builder with typed results
pub fn RawBuilder(comptime T: type) type {
    const Meta = meta.ModelMeta(T);

    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        sql_str: []const u8,
        params: BoundedArray(sql.Value, sql.MAX_PARAMS),
        /// The field each result column fills, in order.
        result_fields: []const []const u8,

        pub fn init(allocator: std.mem.Allocator, sql_string: []const u8, values: anytype) Self {
            var self = Self{
                .allocator = allocator,
                .sql_str = sql_string,
                .params = BoundedArray(sql.Value, sql.MAX_PARAMS){},
                .result_fields = Meta.all_field_names,
            };

            // Store params
            inline for (std.meta.fields(@TypeOf(values))) |field| {
                self.params.append(sql.Value.from(@field(values, field.name))) catch {};
            }

            return self;
        }

        /// Nothing to free; kept so raw builders are used like the others.
        pub fn deinit(self: *Self) void {
            _ = self;
        }

        /// Names the fields the result's columns fill, in order: field enum
        /// literals (`.{ .id, .name }`), the same shape as the typed
        /// builders. Without it, the columns fill every field in
        /// declaration order.
        pub fn columns(self: *Self, comptime field_enums: anytype) *Self {
            self.result_fields = comptime Meta.fieldNamesOf(field_enums);
            return self;
        }

        /// Fetch all matching rows
        pub fn fetchAll(self: *Self, pool: *pg.Pool) !result.QueryResult(T) {
            var query_result = result.QueryResult(T).init(self.allocator);
            errdefer query_result.deinit();

            var pg_result = try query_mod.executeRawQuery(pool, self.sql_str, self.params.slice());
            defer pg_result.deinit();

            const alloc = query_result.allocator();
            var items: std.array_list.Managed(T) = .init(alloc);

            while (try pg_result.next()) |row| {
                const mapped = try result.mapRow(T, row, alloc, self.result_fields);
                try items.append(mapped);
            }

            query_result.items = try items.toOwnedSlice();
            return query_result;
        }

        /// Fetch a single row
        pub fn fetchOne(self: *Self, pool: *pg.Pool) !result.SingleResult(T) {
            var single_result = result.SingleResult(T).init(self.allocator);
            errdefer single_result.deinit();

            var pg_result = try query_mod.executeRawQuery(pool, self.sql_str, self.params.slice());
            defer pg_result.deinit();

            const alloc = single_result.allocator();

            if (try pg_result.next()) |row| {
                single_result.value = try result.mapRow(T, row, alloc, self.result_fields);

                if (try pg_result.next()) |_| {
                    return error.MultipleRowsFound;
                }
            }

            return single_result;
        }
    };
}

/// Execute raw SQL without typed results (for DDL, etc.)
pub fn rawExec(pool: *pg.Pool, sql_str: []const u8, values: anytype) !?usize {
    var params = BoundedArray(sql.Value, sql.MAX_PARAMS){};

    inline for (std.meta.fields(@TypeOf(values))) |field| {
        try params.append(sql.Value.from(@field(values, field.name)));
    }

    return try query_mod.executeRawExec(pool, sql_str, params.slice());
}

/// Execute raw SQL and get pg.Result directly. Caller owns and must deinit.
pub fn rawQuery(pool: *pg.Pool, sql_str: []const u8, values: anytype) !*pg.Result {
    var params = BoundedArray(sql.Value, sql.MAX_PARAMS){};

    inline for (std.meta.fields(@TypeOf(values))) |field| {
        try params.append(sql.Value.from(@field(values, field.name)));
    }

    return try query_mod.executeRawQuery(pool, sql_str, params.slice());
}
