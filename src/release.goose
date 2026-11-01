import std;
import os;
import json;
import src.version;
import src.manifest;
import src.project;
import src.checksum;
import src.process;
import src.terminal;
import src.git;

fn release_tag(v: Version) -> u8[>..] { str("v", v) }

fn has_origin(p: Project, scratch: const u8[:]) -> bool {
    let command: const u8[:][3] = ["remote", "get-url", "origin"];
    return git_succeeds(p.dir, scratch, command[..]);
}

fn check_clean(p: Project, scratch: const u8[:]) -> u8[>..] {
    let repository: const u8[:][2] = ["rev-parse", "--git-dir"];
    guard git_succeeds(p.dir, scratch, repository[..]) else {
        return str("barn lay --release needs a git repository: a release is a git tag");
    }
    let status: const u8[:][2] = ["status", "--porcelain"];
    var changes: u8[>..] = [];
    guard run_git(p.dir, scratch, status[..], changes) == 0 else { return str("cannot read the git status"); }
    guard trim(changes).len == 0 else {
        var listed: u8[>..] = [];
        each_split(changes, '\n') { if it.len > 0 { format(listed, "\n  ", it); } };
        return str("commit or remove these first, since a release is the tagged commit:", listed);
    }
    return str("");
}

fn check_tag(p: Project, scratch: const u8[:], tag: const u8[:]) -> u8[>..] {
    let reference = str("refs/tags/", tag);
    let local: const u8[:][4] = ["rev-parse", "-q", "--verify", reference[..]];
    guard !git_succeeds(p.dir, scratch, local[..]) else { return str("the tag ", tag, " already exists"); }
    guard has_origin(p, scratch) else { return str(""); }
    let remote: const u8[:][4] = ["ls-remote", "--tags", "origin", reference[..]];
    var listed: u8[>..] = [];
    guard run_git(p.dir, scratch, remote[..], listed) == 0 else {
        return str("cannot reach origin to check for ", tag);
    }
    guard trim(listed).len == 0 else { return str("origin already has the tag ", tag); }
    return str("");
}

fn check_release(p: Project, scratch: const u8[:]) -> u8[>..] {
    let dirty = check_clean(p, scratch);
    guard dirty.len == 0 else { return dirty; }
    return check_tag(p, scratch, release_tag(p.manifest.egg.version));
}

fn head_commit(p: Project, scratch: const u8[:]) -> u8[>..] {
    let command: const u8[:][2] = ["rev-parse", "HEAD"];
    var out: u8[>..] = [];
    run_git(p.dir, scratch, command[..], out);
    return str(trim(out));
}

fn origin_text(egg: const u8[:], tag: const u8[:], commit: const u8[:]) -> u8[>..] {
    var out = str("{\n  ");
    json::format_key(out, "repo");
    out.push(' ');
    json::format_string(out, egg);
    out.append(",\n  ");
    json::format_key(out, "tag");
    out.push(' ');
    json::format_string(out, tag);
    out.append(",\n  ");
    json::format_key(out, "commit");
    out.push(' ');
    json::format_string(out, commit);
    out.append("\n}\n");
    return out;
}

fn create_tag(p: Project, scratch: const u8[:], stage: const u8[:]) -> bool {
    let egg = p.manifest.egg;
    let tag = release_tag(egg.version);
    let command: const u8[:][2] = ["tag", tag[..]];
    let origin = origin_text(egg.name, tag, head_commit(p, scratch));
    return write_file(str(stage, "/", ORIGIN_FILE), origin) && git_succeeds(p.dir, scratch, command[..]);
}

fn delete_tag(p: Project, scratch: const u8[:]) {
    let tag = release_tag(p.manifest.egg.version);
    let command: const u8[:][3] = ["tag", "-d", tag[..]];
    git_succeeds(p.dir, scratch, command[..]);
}

fn push_release(p: Project, scratch: const u8[:], yes: bool) -> u8[>..] {
    let tag = release_tag(p.manifest.egg.version);
    guard has_origin(p, scratch) else {
        print(tag, " stays on this machine: there is no origin to push it to");
        return str("");
    }
    guard yes || confirm(str("Push ", tag, " to origin?")) else {
        print(tag, " stays on this machine; git push origin ", tag, " publishes it");
        return str("");
    }
    let command: const u8[:][7] = ["git", "-C", p.dir, "push", "-q", "origin", tag[..]];
    guard run_program(command[..]) == 0 else {
        return str("cannot push ", tag, ": it stays on this machine, and git push origin ", tag, " publishes it");
    }
    print("pushed ", tag, " to origin");
    return str("");
}
