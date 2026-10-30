import std;
import os;
import src.manifest;

fn confirm(question: const u8[:]) -> bool {
    write_stdout(str(question, " [y/N] "));
    flush_stdout();
    var answer: u8[>..] = [];
    guard read_line(answer) else { print(""); return false; }
    let a = trim(answer);
    return a == "y" || a == "Y" || a == "yes" || a == "Yes" || a == "YES";
}

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

fn name_suggestion(name: const u8[:]) -> u8[>..] {
    var suggestion: u8[>..] = [];
    for c in name { suggestion.push(if c == '-' { '_' } else if c >= 'A' && c <= 'Z' { c + 32 } else { c }); }
    return suggestion;
}

fn check_names(name: const u8[:], owner: const u8[:]) -> u8[>..] {
    guard valid_name(name) else {
        let suggestion = name_suggestion(name);
        guard valid_name(suggestion) else { return str("bad egg name '", name, "': use ", NAME_RULE); }
        return str("bad egg name '", name, "': use ", NAME_RULE, "; say '", suggestion, "'");
    }
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
    for file in ["barn.pkg", "main.goose"] {
        guard !file_exists(str(target, "/", file)) else { return str(file, " already exists in ", label); }
    }
    let entry = str("src/", name, ".goose");
    guard !file_exists(str(target, "/", entry)) else { return str(entry, " already exists in ", label); }
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

fn write_project_files(target: const u8[:], owner: const u8[:], name: const u8[:]) -> bool {
    let pkg = str("owner = \"", owner, "\";\n", "name = \"", name, "\";\n", "version = \"0.1.0\";\n\n",
                  "dependencies = [\n];\n");
    let entry = str("namespace ", name, ";\n\n", "fn honk() -> const u8[:] {\n", "    return \"honk from ", name,
                    "\";\n", "}\n");
    let main = str("import src.", name, ";\n\n", "fn main() {\n", "    print(", name, "::honk());\n", "}\n");
    return write_file(str(target, "/barn.pkg"), pkg) && make_dir(str(target, "/src")) &&
           write_file(str(target, "/src/", name, ".goose"), entry) && write_file(str(target, "/main.goose"), main) &&
           add_ignore_lines(str(target, "/.gitignore"));
}

fn hatch(name: const u8[:], here: bool, owner: const u8[:], yes: bool) -> u8[>..] {
    let invalid = check_names(name, owner);
    guard invalid.len == 0 else { return invalid; }
    let target: const u8[:] = if here { "." } else { name };
    let label: const u8[:] = if here { "the current folder" } else { target };
    let egg = str(owner, "/", name);
    let refused = prepare_folder(target, label, egg, name, yes);
    guard refused.len == 0 else { return refused; }
    guard write_project_files(target, owner, name) else { return str("cannot write the files in ", label); }
    print("hatched ", egg, ":0.1.0");
    return str("");
}
