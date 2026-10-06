# pg-orm

A small query builder and ORM for Postgres in Zig, over
[pg.zig](https://github.com/karlseguin/pg.zig).

Split out of [Reverb](https://github.com/vic-Rokx/reverb), which is an HTTP
server and has no business carrying a database layer.

## Requirements

Zig 0.16.0.

## Usage

```sh
zig build test      # 30 tests
zig build example   # needs a reachable Postgres
```

Add it to a project:

```sh
zig fetch --save <url-of-this-repo>
```

```zig
const pg_orm = b.dependency("pg_orm", .{ .target = target, .optimize = optimize });
exe_mod.addImport("pg_orm", pg_orm.module("pg_orm"));
```

## Status

Extracted on 2026-10-06. The tests had never been wired into a build step
before the split, so they had never run; enabling them needed one fix
(`std.io.fixedBufferStream` is gone in 0.16). They pass now.

Coverage is of the query builders — `select`, `insert`, `update`,
`delete`, clauses, operators, schema and metadata. Nothing here talks to
a live database, so the connection and result-decoding paths
(`Connection.zig`, `result.zig`) are still unexercised; `examples/orm_example.zig`
is the only thing that touches a real server.
