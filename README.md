# stabilis

A static site generator written in Zig, built to learn the language while converting my blog.

Progress tracked in [TODO.md](TODO.md).

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/rafaeldelboni/stabilis/main/install.sh | bash
```

Or with options:

```bash
curl -fsSL https://raw.githubusercontent.com/rafaeldelboni/stabilis/main/install.sh | bash -s -- --dir ~/.local/bin
curl -fsSL https://raw.githubusercontent.com/rafaeldelboni/stabilis/main/install.sh | bash -s -- --version v0.1.0
```

## Usage

```bash
zig build run -- [command] [options]            # run with args
zig build run -- build -h                       # command with help option
zig build run -- build example -d public        # command with explicit options
zig build run                                   # general commands help
./zig-out/bin/stabilis build example -d public  # run compiled binary
```

### Current supported command
```bash
stabilis build [source]

Build the site

Options:
    -d, --dest         Output directory destination [string]
    -b, --build-drafts Include draft content [boolean]
    -c, --clear-dir    Clear destination directory [boolean]
    -h, --help         Show help [boolean]
```


## Contributing

```bash
zig fmt src/ build.zig # format code
zig build              # build the project
zig build test         # run tests
zig build test -Dtest-filter="<pattern>" --summary all  # run filtered tests
zig build check        # check compilation (useful for editor on-save)
zig build run          # run main.zig
```
