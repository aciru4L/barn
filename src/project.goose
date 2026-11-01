import std;
import os;
import src.manifest;

let DEFAULT_MAIN = "main.goose";
let DEFAULT_TEST = "test/main_test.goose";

struct Project {
    dir: const u8[:], text: const u8[:], manifest: Manifest, dependencies: const Dependency[:],
    overrides: const Override[:], excludes: (const u8[:])[:],
}

fn package_path(dir: const u8[:]) -> u8[>..] { str(dir, "/barn.json") }

fn main_file(p: Project) -> const u8[:] {
    if p.manifest.main.len > 0 { return p.manifest.main; }
    return DEFAULT_MAIN;
}

fn test_file(p: Project) -> const u8[:] {
    if p.manifest.test.len > 0 { return p.manifest.test; }
    return DEFAULT_TEST;
}

fn find_dependency(p: Project, egg: const u8[:]) -> i64 {
    for d, i in p.dependencies {
        if d.name == without_github(egg) || repo_name(d.name) == egg { return i; }
    }
    return -1;
}

fn with_project_text<F>(dir: const u8[:], text: const u8[:]) -> u8[>..] {
    var names: u8[>..] = [];
    var dependencies: Dependency[>..] = [];
    var overrides: Override[>..] = [];
    var excludes: (const u8[:])[>..] = [];
    let m, error = parse_manifest(text, dependencies, overrides, excludes, names);
    guard error.len == 0 else { return str(package_path(dir), ": ", error); }
    F(Project { dir: dir, text: text, manifest: m, dependencies: dependencies[..], overrides: overrides[..],
              excludes: excludes[..] });
    return str("");
}

fn with_project<F>(dir: const u8[:]) -> u8[>..] {
    var text: u8[>..] = [];
    guard read_file(package_path(dir), text) else { return str("no barn.json in ", dir); }
    return with_project_text(dir, text) { F(it); };
}
