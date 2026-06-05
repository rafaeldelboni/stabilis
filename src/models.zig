pub const DateTime = struct {
    sec: u6, // [0, 60]
    min: u6, // [0, 59]
    hour: u5, // [0, 23]
    day: u5, // [1, 31]
    month: u4, // [1, 12]
    year: i16, // C.E.
};

pub const MapEntry = struct {
    key: []const u8,
    value: YamlNode,
};

pub const YamlNode = union(enum) {
    string: []const u8,
    boolean: bool,
    list: []const YamlNode,
    map: []const MapEntry,
    datetime: DateTime,
    null,
};

pub const ImageSpec = struct {
    file: []const u8,
    caption: ?[]const u8,
};

pub const Frontmatter = struct {
    title: ?[]const u8 = null,
    author: ?[]const u8 = null,
    date: ?[]const u8 = null,
    slug: ?[]const u8 = null,
    description: ?[]const u8 = null,
    draft: bool = false,
    cover: ?[]const u8 = null,
    tags: []const []const u8 = &.{},
    menus: []const []const u8 = &.{},
    images: []const ImageSpec = &.{},
};

pub const ContentEntry = struct { frontmatter: Frontmatter, source: []const u8 };

const Page = struct {
    kind: PageKind,
    frontmatter: Frontmatter,
    body_html: []const u8, // rendered markdown → HTML
    url: []const u8, // e.g. "/posts/hello-world/"
    source_path: []const u8, // relative, e.g. "content/posts/hello-world.md"
};

const PageKind = union(enum) {
    home,
    post,
    page,
    gallery,
    section_list,
};

const Site = struct {
    config: SiteConfig,
    pages: []const Page,
    posts: []const Page,
    menu_main: []const MenuItem,
    menu_footer: []const MenuItem,
};

const SiteConfig = struct {
    title: []const u8,
    base_url: []const u8,
};

const MenuItem = struct {
    name: []const u8,
    url: []const u8,
};
