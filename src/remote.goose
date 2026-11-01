import std;
import os;
import json;
import src.version;
import src.manifest;
import src.project;
import src.eggs;
import src.checksum;
import src.files;
import src.git;
import src.lay;
import src.release;

let TAG_PREFIX = "refs/tags/v";
let PEELED = "^{}";

struct Network { fetches: bool = false, offline: bool = false, priority: i64 = 0, home: u8[>..] }

let PRIORITY_FROM_PACKAGE = 0;
let LOCAL_FIRST = 1;
let REMOTE_FIRST = 2;

var network = Network { home: [] };

struct Tag { version: Version, commit: const u8[:] }

fn config_path() -> u8[>..] { str(network.home, "/config.json") }

fn host_base(host: const u8[:]) -> u8[>..], u8[>..] {
    var text: u8[>..] = [];
    guard read_file(config_path(), text) else { return str("https://", host), str(""); }
    var doc: json::Node[>..] = [];
    var decoded: u8[>..] = [];
    let root, error = json::parse(text, doc, decoded);
    guard root else { return str(""), str(config_path(), ": ", error); }
    let url, has_url = json::as_string(json::member(json::member(json::member(root, "hosts"), host), "url"));
    guard has_url else { return str("https://", host), str(""); }
    return str(url), str("");
}

fn repo_url(repo: const u8[:]) -> u8[>..], u8[>..] {
    let slash = find(repo, "/");
    let host: const u8[:] = if has_host(repo) { repo[..slash] } else { "github.com" };
    let path: const u8[:] = if has_host(repo) { repo[slash + 1..] } else { repo };
    let base, failed = host_base(host);
    return str(base, "/", path), failed;
}

fn find_tag(tags: const Tag[:], v: Version) -> i64 {
    for t, i in tags { if t.version == v { return i; } }
    return -1;
}

fn add_tag(tags: Tag[>..]&, line: const u8[:]) {
    let tab = find(line, "\t");
    guard tab > 0 && starts_with(line[tab + 1..], TAG_PREFIX) else { return; }
    let commit = line[..tab];
    var name = line[tab + 1 + TAG_PREFIX.len..];
    let peeled = ends_with(name, PEELED);
    if peeled { name = name[..name.len - PEELED.len]; }
    let v, ok = parse_version(name);
    guard ok && is_release(v) else { return; }
    let i = find_tag(tags[..], v);
    if i < 0 { tags.push(Tag { version: v, commit: commit }); }
    else if peeled { tags[i].commit = commit; }
}

fn remote_tags(eggs: const u8[:], repo: const u8[:], tags: Tag[>..]&, text: u8[>..]&) -> u8[>..] {
    let url, failed = repo_url(repo);
    guard failed.len == 0 else { return failed; }
    let command: const u8[:][3] = ["ls-remote", "--tags", url[..]];
    guard run_git(eggs, eggs, command[..], text) == 0 else {
        return str("cannot list the tags of ", repo, " at ", url);
    }
    each_split(text, '\n') { add_tag(tags, it); };
    return str("");
}

fn check_fetched(p: Project, repo: const u8[:], v: Version) -> u8[>..] {
    let found = p.manifest.egg;
    guard found.name == repo else { return str("the repository of ", repo, " holds ", found.name); }
    guard found.version == v else { return str(repo, " says version ", found.version, " at the tag v", v); }
    let invalid = check_layable(p);
    guard invalid.len == 0 else { return str(repo, ":", v, " is not a valid egg: ", invalid); }
    return str("");
}

fn stage_fetched(clone: const u8[:], stage: const u8[:], repo: const u8[:], tag: Tag) -> u8[>..] {
    var text: u8[>..] = [];
    guard read_file(str(clone, "/barn.json"), text) else { return str(repo, ":", tag.version, " has no barn.json"); }
    var problem: u8[>..] = [];
    let error = with_project_text(clone, text) { p =>
        problem.append(check_fetched(p, repo, tag.version));
        var sums: u8[>..] = [];
        if problem.len == 0 && !stage_egg(p, stage, sums) {
            problem.append(str("cannot copy ", repo, " into ", stage));
        }
    };
    guard error.len == 0 else { return str(repo, ":", tag.version, ": barn.json: ", error[find(error, ": ") + 2..]); }
    guard problem.len == 0 else { return problem; }
    guard write_file(str(stage, "/", ORIGIN_FILE), origin_text(repo, release_tag(tag.version), tag.commit)) else {
        return str("cannot write ", stage, "/", ORIGIN_FILE);
    }
    return str("");
}

fn fetch_tag(eggs: const u8[:], repo: const u8[:], tag: Tag) -> u8[>..] {
    let folder = egg_folder(eggs, repo);
    guard make_dirs(folder) || is_dir(folder) else { return str("cannot create ", folder); }
    let clone = str(folder, "/.fetching-", time_ns(), "-", random_seed());
    let stage = str(clone, "-egg");
    let url, _ = repo_url(repo);
    let name = release_tag(tag.version);
    let command: const u8[:][8] = ["clone", "-q", "--depth", "1", "--branch", name[..], url[..], clone[..]];
    var out: u8[>..] = [];
    guard run_git(eggs, eggs, command[..], out) == 0 else {
        delete_tree(clone);
        return str("cannot fetch ", repo, ":", tag.version, " from ", url);
    }
    let problem = stage_fetched(clone, stage, repo, tag);
    delete_tree(clone);
    guard problem.len == 0 else { delete_tree(stage); return problem; }
    let target = egg_dir(eggs, repo, tag.version);
    if !rename_file(stage, target) { delete_tree(stage); }
    guard is_dir(target) else { return str("cannot move ", repo, ":", tag.version, " into ", target); }
    print("fetched ", repo, ":", tag.version, " from ", url);
    return str("");
}

fn fetch_release(eggs: const u8[:], repo: const u8[:], v: Version) -> u8[>..] {
    guard network.fetches && !network.offline && is_release(v) else { return str(""); }
    var text: u8[>..] = [];
    var tags: Tag[>..] = [];
    let failed = remote_tags(eggs, repo, tags, text);
    guard failed.len == 0 else {
        write_stderr(str("warning: ", failed, "\n"));
        return str("");
    }
    let i = find_tag(tags[..], v);
    guard i >= 0 else { return str(""); }
    return fetch_tag(eggs, repo, tags[i]);
}

fn recorded_commit(eggs: const u8[:], repo: const u8[:], v: Version) -> u8[>..] {
    var text: u8[>..] = [];
    guard read_file(str(egg_dir(eggs, repo, v), "/", ORIGIN_FILE), text) else { return str(""); }
    var doc: json::Node[>..] = [];
    var decoded: u8[>..] = [];
    let root, _ = json::parse(text, doc, decoded);
    let commit, _ = json::as_string(json::member(root, "commit"));
    return str(commit);
}

fn moved_tag(eggs: const u8[:], repo: const u8[:], tag: Tag) -> u8[>..] {
    guard is_released(eggs, repo, tag.version) else { return str(""); }
    let recorded = recorded_commit(eggs, repo, tag.version);
    guard recorded.len > 0 && recorded != tag.commit else { return str(""); }
    return str("the tag v", tag.version, " of ", repo, " now points at ", tag.commit, ", not ", recorded,
               ": a release must never change");
}

fn add_known(versions: Version[>..]&, v: Version) {
    for known in versions { if known == v { return; } }
    versions.push(v);
}

fn known_releases(eggs: const u8[:], repo: const u8[:], versions: Version[>..]&) -> u8[>..] {
    each_version(eggs, repo) { if is_released(eggs, repo, it) { add_known(versions, it); } };
    guard network.fetches && !network.offline else { return str(""); }
    var text: u8[>..] = [];
    var tags: Tag[>..] = [];
    let failed = remote_tags(eggs, repo, tags, text);
    guard failed.len == 0 else {
        write_stderr(str("warning: ", failed, "; using the releases in ~/.barn/eggs\n"));
        return str("");
    }
    for tag in tags {
        let moved = moved_tag(eggs, repo, tag);
        guard moved.len == 0 else { return moved; }
        add_known(versions, tag.version);
    }
    return str("");
}

fn newest_known(versions: const Version[:], like: Version, compatible_only: bool) -> Version, bool {
    var newest = Version {..};
    var found = false;
    for v in versions {
        if (!compatible_only || compatible(v, like)) && (!found || is_newer(v, newest)) {
            newest = v;
            found = true;
        }
    }
    return newest, found;
}

fn asks_repository_first(m: Manifest) -> bool {
    guard network.priority == PRIORITY_FROM_PACKAGE else { return network.priority == REMOTE_FIRST; }
    return m.remote_first;
}

fn check_with_repository(eggs: const u8[:], repo: const u8[:], v: Version) -> u8[>..] {
    guard network.fetches && !network.offline && is_release(v) else { return str(""); }
    var text: u8[>..] = [];
    var tags: Tag[>..] = [];
    let failed = remote_tags(eggs, repo, tags, text);
    guard failed.len == 0 else {
        write_stderr(str("warning: ", failed, "; using the release in ~/.barn/eggs\n"));
        return str("");
    }
    let i = find_tag(tags[..], v);
    guard i >= 0 else { return str(""); }
    return moved_tag(eggs, repo, tags[i]);
}

fn apply_setting(setting: const u8[:]) -> u8[>..] {
    guard setting == "local_priority=true" || setting == "local_priority=false" else {
        return str("--set supports local_priority=true and local_priority=false, not '", setting, "'");
    }
    network.priority = if setting == "local_priority=true" { LOCAL_FIRST } else { REMOTE_FIRST };
    return str("");
}
