# XLA Protos

`xla/xla_data.proto` is vendored from OpenXLA at commit
`41370d1124c74d7b93a207136a636d8c631cbed9`, matching the Bazel
`third_party/xla/repo.bzl` pin.

Only `xla_data.proto` is checked in for the native Zig build because it has no
direct proto imports. Well-known protobuf protos should come from the Zig
`protobuf` package instead of being duplicated here.
