import std;
import os;
import src.version;
import src.manifest;
import src.terminal;
import src.package_edit;

fn add_ignore_lines(path: const u8[:]) -> bool {
    let wanted: const u8[:][2] = [".barn/", "*.exe"];
    var have: u8[>..] = [];
    if file_exists(path) && !read_file(path, have) { return false; }
    var missing: u8[>..] = [];
    if have.len > 0 && have[have.len - 1] != '\n' { missing.push('\n'); }
    var any = false;
    for line in wanted {
        var present = false;
        each_split(have, '\n') { if trim(it) == line { present = true; } };
        if !present { format(missing, line, "\n"); any = true; }
    }
    guard any else { return true; }
    return append_file(path, missing);
}

fn check_names(name: const u8[:], owner: const u8[:]) -> u8[>..] {
    guard valid_name(name) else { return str("bad egg name '", name, "': use ", NAME_RULE, name_hint(name)); }
    guard owner.len > 0 else { return str("no owner: --owner NAME or BARN_OWNER"); }
    guard valid_owner(owner) else { return str("bad owner '", owner, "': use ", OWNER_RULE); }
    return str("");
}

fn describe_contents(listing: const u8[:]) -> u8[>..], i64 {
    var count = 0;
    var shown: u8[>..] = [];
    each_split(listing, '\n') {
        if it.len > 0 {
            count++;
            if count <= 5 { format(shown, "\n  ", it); }
        }
    };
    if count > 5 { format(shown, "\n  ... and ", count - 5, " more"); }
    return shown, count;
}

fn prepare_existing_folder(target: const u8[:], label: const u8[:], egg: const u8[:], name: const u8[:],
                           yes: bool) -> u8[>..] {
    let entry = str(name, ".goose");
    for file in ["barn.json", "main.goose", "test/main_test.goose", entry[..]] {
        guard !file_exists(str(target, "/", file)) else { return str(file, " already exists in ", label); }
    }
    var listing: u8[>..] = [];
    guard list_dir(target, listing) else { return str("cannot read ", label); }
    let shown, count = describe_contents(listing);
    guard count > 0 && !yes else { return str(""); }
    print(str(label, " is not empty (", count, if count == 1 { " item" } else { " items" }, "):", shown));
    guard confirm(str("Hatch ", egg, " here anyway?")) else { return str("cancelled: nothing was changed"); }
    return str("");
}

fn prepare_folder(target: const u8[:], label: const u8[:], egg: const u8[:], name: const u8[:], yes: bool) -> u8[>..] {
    guard !is_dir(target) else { return prepare_existing_folder(target, label, egg, name, yes); }
    guard !file_exists(target) else { return str("'", target, "' is a file, not a folder"); }
    guard make_dir(target) else { return str("cannot create folder '", target, "'"); }
    return str("");
}

fn write_project_files(target: const u8[:], owner: const u8[:], name: const u8[:], app: bool) -> bool {
    let egg = str(owner, "/", name);
    let first = Version { major: 0, minor: 1, patch: 0 };
    let dependencies: Dependency[>..] = [];
    let overrides: Override[>..] = [];
    let excludes: (const u8[:])[>..] = [];
    let manifest = Manifest { egg: Dependency { name: egg, version: first }, owner: owner, name: name, .. };
    let pkg = package_text(manifest, dependencies[..],
                           overrides[..], excludes[..]);
    let entry = str("namespace ", name, ";\n\n", "fn honk() -> const u8[:] {\n", "    return \"honk from ", name,
                    "\";\n", "}\n");
    let main = str("import ", name, ";\n\n", "fn main() {\n", "    print(", name, "::honk());\n", "}\n");
    let test = str("import ", name, " from \"..\";\n\n", "fn main() {\n",
                   "    guard ", name, "::honk() == \"honk from ", name, "\" else {\n",
                   "        print(\"honk: got '\", ", name, "::honk(), \"'\");\n",
                   "        exit(1);\n", "    }\n", "}\n");
    return write_file(str(target, "/barn.json"), pkg) && write_file(str(target, "/", name, ".goose"), entry) &&
           (!app || write_file(str(target, "/main.goose"), main)) && make_dir(str(target, "/test")) &&
           write_file(str(target, "/test/main_test.goose"), test) && add_ignore_lines(str(target, "/.gitignore"));
}

fn hatch(name: const u8[:], here: bool, owner: const u8[:], yes: bool, app: bool) -> u8[>..] {
    let invalid = check_names(name, owner);
    guard invalid.len == 0 else { return invalid; }
    let target: const u8[:] = if here { "." } else { name };
    let label: const u8[:] = if here { "the current folder" } else { target };
    let egg = str(owner, "/", name);
    let refused = prepare_folder(target, label, egg, name, yes);
    guard refused.len == 0 else { return refused; }
    guard write_project_files(target, owner, name, app) else { return str("cannot write the files in ", label); }
    print("hatched ", egg, ":0.1.0");
    return str("");
}
