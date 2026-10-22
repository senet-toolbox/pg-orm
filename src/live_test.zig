//! Against a real Postgres. Runs when `PG_DB` names a database the test may
//! create a table in (`PG_HOST`, `PG_PORT`, `PG_USER` and `PG_PASSWORD` are
//! read as `Connection.Config.fromEnv` reads them), and is skipped,
//! saying so, otherwise:
//!
//!   PG_PORT=5432 PG_DB=pg_orm_test zig build test
//!
//! The table is created and dropped here.

const std = @import("std");
const testing = std.testing;
const Connection = @import("Connection.zig");
const pg_orm = @import("orm.zig");

/// `power` is stored as `power_level`, so rows map by position, not by
/// column name.
const Hero = struct {
    id: i32,
    name: []const u8,
    power: i32,

    pub const orm = .{
        .table = "pg_orm_live_heroes",
        .columns = .{ .power = "power_level" },
    };
};

fn lookup(env: *const std.process.Environ.Map, key: []const u8) ?[]const u8 {
    return env.get(key);
}

fn connect(env: *const std.process.Environ.Map) !Connection {
    if (env.get("PG_DB") == null) {
        std.debug.print("live tests skipped: set PG_DB (and PG_HOST, PG_PORT, PG_USER, PG_PASSWORD) to run them\n", .{});
        return error.SkipZigTest;
    }
    return Connection.init(testing.io, testing.allocator, Connection.Config.fromEnv(env, lookup));
}

test "rows come back filled, renamed columns included" {
    var env = try testing.environ.createMap(testing.allocator);
    defer env.deinit();
    var conn = try connect(&env);
    defer conn.deinit();
    const pool = conn.pool();

    _ = try pool.exec("DROP TABLE IF EXISTS pg_orm_live_heroes", .{});
    _ = try pool.exec("CREATE TABLE pg_orm_live_heroes (id serial PRIMARY KEY, name text NOT NULL, power_level int NOT NULL)", .{});
    defer _ = pool.exec("DROP TABLE pg_orm_live_heroes", .{}) catch {};

    // INSERT ... RETURNING mapped none of the returned columns back.
    {
        var ib = pg_orm.insertWith(Hero, testing.allocator);
        defer ib.deinit();
        var inserted = try ib.values(.{ .name = "Goku", .power = 9001 }).returningAll().exec(pool);
        defer inserted.deinit();
        try testing.expectEqual(1, inserted.rows.items.len);
        try testing.expectEqualStrings("Goku", inserted.rows.items[0].name);
        try testing.expectEqual(9001, inserted.rows.items[0].power);
    }
    {
        var ib = pg_orm.insertWith(Hero, testing.allocator);
        defer ib.deinit();
        var inserted = try ib.values(.{ .name = "Vegeta", .power = 8000 }).returning(.{ .power, .id }).exec(pool);
        defer inserted.deinit();
        try testing.expectEqual(8000, inserted.rows.items[0].power);
        try testing.expectEqual(2, inserted.rows.items[0].id);
    }

    // A SELECT of every column, without `.select`, mapped nothing either.
    {
        var qb = pg_orm.queryWith(Hero, testing.allocator);
        defer qb.deinit();
        var heroes = try qb.where(.power, .gt, 8500).fetchAll(pool);
        defer heroes.deinit();
        try testing.expectEqual(1, heroes.items.len);
        try testing.expectEqual(1, heroes.items[0].id);
        try testing.expectEqualStrings("Goku", heroes.items[0].name);
        try testing.expectEqual(9001, heroes.items[0].power);
    }

    // `.select` matched column names against field names, so `power`
    // (column `power_level`) was never filled.
    {
        var qb = pg_orm.queryWith(Hero, testing.allocator);
        defer qb.deinit();
        var vegeta = try qb.select(.{ .power, .name }).where(.id, .eq, 2).fetchOne(pool);
        defer vegeta.deinit();
        const hero = try vegeta.unwrap();
        try testing.expectEqual(8000, hero.power);
        try testing.expectEqualStrings("Vegeta", hero.name);
    }

    {
        var raw = pg_orm.rawWith(Hero, testing.allocator, "SELECT power_level, id FROM pg_orm_live_heroes WHERE name = $1", .{"Goku"});
        defer raw.deinit();
        var goku = try raw.columns(.{ .power, .id }).fetchOne(pool);
        defer goku.deinit();
        const hero = try goku.unwrap();
        try testing.expectEqual(9001, hero.power);
        try testing.expectEqual(1, hero.id);
    }
}

// Builder queries kept their pooled connection, so a pool ran dry after as
// many queries as it had connections.
test "builder queries give their connection back to the pool" {
    var env = try testing.environ.createMap(testing.allocator);
    defer env.deinit();
    if (env.get("PG_DB") == null) return error.SkipZigTest;
    var config = Connection.Config.fromEnv(&env, lookup);
    config.pool_size = 2;
    var conn = try Connection.init(testing.io, testing.allocator, config);
    defer conn.deinit();
    const pool = conn.pool();

    for (0..5) |i| {
        var raw = pg_orm.rawWith(Hero, testing.allocator, "SELECT $1::int AS power_level, 1 AS id", .{@as(i32, @intCast(i))});
        defer raw.deinit();
        var hero = try raw.columns(.{ .power, .id }).fetchOne(pool);
        defer hero.deinit();
        try testing.expectEqual(@as(i32, @intCast(i)), (try hero.unwrap()).power);
    }
}

const Parent = struct {
    id: [16]u8,
    pub const orm = .{
        .table = "pg_orm_live_parents",
        .primary_key = .id,
        .schema = .{ .id = .{ .default = pg_orm.schema.defaults.gen_random_uuid } },
    };
};

const Child = struct {
    id: i32,
    parent_id: [16]u8,
    seen_at: i64,
    pub const orm = .{
        .table = "pg_orm_live_children",
        .primary_key = .id,
        .schema = .{
            .id = .{ .type = .serial },
            .parent_id = .{ .not_null = true, .references = "pg_orm_live_parents(id)", .on_delete = .cascade },
            .seen_at = .{ .type = .timestamptz, .not_null = true },
        },
        .indexes = .{.{ .name = "idx_pg_orm_live_children_seen_at", .columns = .{.seen_at}, .descending = true }},
    };
};

test "the DDL's foreign keys cascade, and its indexes exist" {
    var env = try testing.environ.createMap(testing.allocator);
    defer env.deinit();
    var conn = try connect(&env);
    defer conn.deinit();
    const pool = conn.pool();

    _ = try pool.exec("DROP TABLE IF EXISTS pg_orm_live_children, pg_orm_live_parents", .{});
    _ = try pool.exec(comptime pg_orm.schema.createTableSql(Parent), .{});
    _ = try pool.exec(comptime pg_orm.schema.createTableSql(Child), .{});
    defer _ = pool.exec("DROP TABLE pg_orm_live_children, pg_orm_live_parents", .{}) catch {};
    inline for (comptime pg_orm.schema.createIndexesSql(Child)) |ddl| _ = try pool.exec(ddl, .{});

    _ = try pool.exec("INSERT INTO pg_orm_live_parents DEFAULT VALUES", .{});
    _ = try pool.exec("INSERT INTO pg_orm_live_children (parent_id, seen_at) SELECT id, now() FROM pg_orm_live_parents", .{});
    _ = try pool.exec("DELETE FROM pg_orm_live_parents", .{});
    var left = (try pool.row("SELECT count(*) FROM pg_orm_live_children", .{})).?;
    defer left.deinit() catch {};
    try testing.expectEqual(0, try left.get(i64, 0));

    var index = (try pool.row("SELECT indexdef FROM pg_indexes WHERE indexname = 'idx_pg_orm_live_children_seen_at'", .{})).?;
    defer index.deinit() catch {};
    try testing.expectEqualStrings(
        "CREATE INDEX idx_pg_orm_live_children_seen_at ON public.pg_orm_live_children USING btree (seen_at DESC)",
        try index.get([]const u8, 0),
    );
}
