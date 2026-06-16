# stabilis

A static site generator written in Zig, built to learn the language while converting my blog.

Progress tracked in [TODO.md](TODO.md).

## Installation

```sh
curl -fsSL https://raw.githubusercontent.com/rafaeldelboni/stabilis/main/install.sh | bash
```

Or with options:

```sh
curl -fsSL https://raw.githubusercontent.com/rafaeldelboni/stabilis/main/install.sh | bash -s -- --dir ~/.local/bin
curl -fsSL https://raw.githubusercontent.com/rafaeldelboni/stabilis/main/install.sh | bash -s -- --version v0.1.0
```

## Usage

```sh
zig build run -- [output_dir] [input_dir]   # run with args
zig build run -- public example             # explicit dirs
zig build run                               # defaults to public/ and example/
./zig-out/bin/stabilis public example       # run compiled binary
```

| Argument     | Default   | Description              |
|--------------|-----------|--------------------------|
| `output_dir` | `public`  | Directory for built site |
| `input_dir`  | `example` | Source content directory |

## Contributing

```sh
zig fmt src/ build.zig # format code
zig build              # build the project
zig build test         # run tests
zig build check        # check compilation (useful for editor on-save)
zig build run          # run main.zig
```
