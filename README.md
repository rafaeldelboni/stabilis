# stabilis

A static site generator written in Zig, built to learn the language while converting my blog.

Progress tracked in [TODO.md](TODO.md).

## Installation

Installs to `/usr/local/bin` by default; prefix with `sudo` or use `--dir ~/.local/bin` to avoid that.

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
stabilis - A static site generator

stabilis <command>

Commands:
  build      Build the site
  new        Scaffold new content
    post       Scaffold new post
    page       Scaffold new page

Global options:
    -S, --source-dir   Source directory [string]
    -h, --help         Show help [boolean]
    -v, --version      Print version [boolean]
```

## Configuration

Stabilis reads a `site.yaml` at the root of your source directory. `title` and `base_url` are required; everything else falls back to built-in defaults shown below.

```yaml
# Required
title: Example Blog
base_url: https://example.com

# Optional menu
menu:
  main:
    - { name: Home, url: / }
    - { name: Posts, url: /posts/ }

# Optional layout overrides (defaults shown)
content_dir: content
templates_dir: templates
static_dir: static
posts_dir: posts
content_ext: .md
index_file_name: _index.md
output_index: index.html
post_url_prefix: /posts
template_home_file_name: home.html
template_post_file_name: post.html
template_page_file_name: page.html
template_post_list_file_name: post-list.html
template_tag_post_list_file_name: tag-post-list.html
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
