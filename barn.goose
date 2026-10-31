import std;
import os;
import src.manifest;
import src.resolve;
import src.show;
import src.hatch;
import src.lay;
import src.install;
import src.edit;
import src.build;

let VERSION = "0.1.0";

fn help() {
    print("""
        barn: the package manager for Goose

        usage: barn <command> [arguments] [options]

        commands:
          hatch <name>      create a project
          install [dir]     install the project's eggs into .barn/
          add <egg>...      add dependencies
          remove <egg>...   remove dependencies
          upgrade [egg]...  upgrade dependencies to their newest compatible releases
          verify [dir]      check .barn/ against barn.lock
          build [dir]       check the eggs, then build the project with goose
          run [dir]         check the eggs, then run the project with goose
          test [dir]        check the eggs, then run the project's tests with goose
          lay [dir]         put the egg into the repository
          inspect [dir]     show the dependency tree
          resolve [dir]     list the eggs the project uses
          help [command]    show help
          version           show barn's version

        options:
          --repo DIR        the repository (default: $BARN_REPO, else ~/.barn/repository)
          --owner NAME      the owner of a new egg (default: $BARN_OWNER)
          --here            hatch: in the current folder
          -y, --yes         hatch: do not ask
          --force           install, add, remove, upgrade: replace edited or changed eggs
          --release         lay: a release instead of a snapshot
          -- ...            build: goose's options; run, test: the program's arguments
          -h, --help        help for the command
        """);
}

struct CommandHelp { command: const u8[:], usage: const u8[:], summary: const u8[:] }

let COMMAND_HELP: const CommandHelp[14] = [
    CommandHelp { command: "hatch", usage: "barn hatch <name> [--here] [--owner NAME] [-y]", summary: """
                      Creates ./<name>, or with --here the current folder, with barn.pkg,
                      src/<name>.goose, main.goose, test/main_test.goose and .gitignore.
                      """ },
    CommandHelp { command: "install", usage: "barn install [dir] [--repo DIR] [--force]", summary: """
                      Installs the project's eggs into .barn/, updates the imports in
                      main.goose and test/main_test.goose and writes barn.lock.
                      """ },
    CommandHelp { command: "add", usage: "barn add <owner/name[:version]>... [--repo DIR] [--force]", summary: """
                      Adds dependencies to barn.pkg, at the newest release unless a
                      version is given, then installs.
                      """ },
    CommandHelp { command: "remove", usage: "barn remove <egg>... [--repo DIR] [--force]",
                  summary: "Removes dependencies from barn.pkg, then installs." },
    CommandHelp { command: "upgrade", usage: "barn upgrade [egg]... [--repo DIR] [--force]", summary: """
                      Upgrades all dependencies, or those named, to their newest
                      compatible releases, then installs.
                      """ },
    CommandHelp { command: "verify", usage: "barn verify [dir] [--repo DIR]",
                  summary: "Checks .barn/ against barn.lock." },
    CommandHelp { command: "build", usage: "barn build [dir] [--repo DIR] [-- goose options...]", summary: """
                      Checks that barn.lock matches barn.pkg and .barn/ matches barn.lock,
                      then builds the project's main file with goose build.
                      """ },
    CommandHelp { command: "run", usage: "barn run [dir] [--repo DIR] [-- program arguments...]", summary: """
                      Checks that barn.lock matches barn.pkg and .barn/ matches barn.lock,
                      then runs the project's main file with goose run.
                      """ },
    CommandHelp { command: "test", usage: "barn test [dir] [--repo DIR] [-- program arguments...]", summary: """
                      Checks that barn.lock matches barn.pkg and .barn/ matches barn.lock,
                      then runs the project's test file (test/main_test.goose unless
                      barn.pkg sets test) with goose run. A test fails by exiting with
                      a status other than 0.
                      """ },
    CommandHelp { command: "lay", usage: "barn lay [dir] [--release] [--repo DIR]", summary: """
                      Puts the egg into the repository: a new snapshot, or with
                      --release the release.
                      """ },
    CommandHelp { command: "inspect", usage: "barn inspect [dir] [--repo DIR]", summary: "Shows the dependency tree." },
    CommandHelp { command: "resolve", usage: "barn resolve [dir] [--repo DIR]",
                  summary: "Lists the eggs the project uses." },
    CommandHelp { command: "help", usage: "barn help [command]", summary: "" },
    CommandHelp { command: "version", usage: "barn version", summary: "" },
];

fn command_help(command: const u8[:]) -> bool {
    for h in COMMAND_HELP {
        if h.command == command {
            if h.summary.len == 0 { print("usage: ", h.usage); }
            else { print("usage: ", h.usage, "\n\n", h.summary); }
            return true;
        }
    }
    return false;
}

fn fail_usage(message: const u8[:]) {
    write_stderr(str("barn: ", message, "\nRun 'barn help' for usage.\n"));
    exit(2);
}

fn default_repository(out: u8[>..]&) -> bool {
    var home: u8[>..] = [];
    if env("BARN_HOME", home) && home.len > 0 { format(out, home, "/repository"); return true; }
    home.clear();
    if !env("USERPROFILE", home) || home.len == 0 {
        home.clear();
        guard env("HOME", home) && home.len > 0 else { return false; }
    }
    format(out, home, "/.barn/repository");
    return true;
}

struct Flags { here: bool = false, yes: bool = false, force: bool = false, release: bool = false }

let COMMANDS: const u8[:][12] = [
    "hatch", "install", "add", "remove", "upgrade", "verify", "build", "run", "test", "lay", "inspect", "resolve",
];

fn is_edit_command(command: const u8[:]) -> bool { command == "add" || command == "remove" || command == "upgrade" }

fn is_goose_command(command: const u8[:]) -> bool { command == "build" || command == "run" || command == "test" }

fn check_argument_count(command: const u8[:], count: i64) {
    if is_edit_command(command) {
        guard command == "upgrade" || count > 0 else { fail_usage(str("usage: barn ", command, " <egg>...")); }
    } else {
        guard count <= 1 else { fail_usage(str(command, " takes at most one folder")); }
    }
}

fn run_hatch(arguments: const u8[:][:], owner: const u8[:], flags: Flags) -> u8[>..] {
    guard arguments.len == 1 else { fail_usage("usage: barn hatch <name>"); }
    return hatch(arguments[0], flags.here, owner, flags.yes);
}

fn run_listing(dir: const u8[:], repository: const u8[:], inspects: bool) -> u8[>..] {
    return resolve(dir, repository) {
        if inspects { print_tree(it); } else { print_list(it); }
    };
}

fn run_in_project(command: const u8[:], arguments: const u8[:][:], passed: const u8[:][:], repository: const u8[:],
                  flags: Flags) -> u8[>..] {
    if is_edit_command(command) {
        if command == "add" { return add(".", repository, arguments, flags.force); }
        if command == "remove" { return remove(".", repository, arguments, flags.force); }
        return upgrade(".", repository, arguments, flags.force);
    }
    let dir: const u8[:] = if arguments.len == 1 { arguments[0] } else { "." };
    if command == "install" { return install(dir, repository, flags.force); }
    if command == "verify" { return verify(dir, repository); }
    if is_goose_command(command) { return run_goose(command, dir, repository, passed); }
    if command == "lay" { return lay(dir, repository, flags.release); }
    return run_listing(dir, repository, command == "inspect");
}

fn run(command: const u8[:], argv: u8[:][:]) -> u8[>..] {
    var arguments: (const u8[:])[>..] = [];
    var repository: u8[>..] = [];
    var owner: u8[>..] = [];
    var lowered: u8[>..] = [];
    var passed: (const u8[:])[>..] = [];
    var flags = Flags {};
    env("BARN_REPO", repository);
    env("BARN_OWNER", owner);
    var i = 0;
    while i < argv.len {
        let a = argv[i];
        i++;
        if a == "--" && is_goose_command(command) { for rest in argv[i..] { passed.push(rest); } break; }
        if a == "-h" || a == "--help" { command_help(command); return str(""); }
        else if a == "-y" || a == "--yes" { flags.yes = true; }
        else if a == "--here" { flags.here = true; }
        else if a == "--force" { flags.force = true; }
        else if a == "--release" { flags.release = true; }
        else if a == "--repo" || a == "--owner" {
            guard i < argv.len else { fail_usage(str(a, " needs a value")); }
            if a == "--repo" { repository.clear(); repository.append(argv[i]); }
            else { owner.clear(); owner.append(argv[i]); }
            i++;
        } else {
            guard !starts_with(a, "-") else { fail_usage(str("unknown option '", a, "' for ", command)); }
            arguments.push(if is_edit_command(command) { lowercase_spec_owner(a, lowered) } else { a });
        }
    }
    guard command != "hatch" else {
        return run_hatch(arguments, lowercase_owner(owner, owner.len, lowered), flags);
    }
    check_argument_count(command, arguments.len);
    if repository.len == 0 && !default_repository(repository) {
        fail_usage("no repository: --repo DIR, BARN_REPO or BARN_HOME");
    }
    return run_in_project(command, arguments, passed, repository, flags);
}

fn main() {
    let argv = args();
    guard argv.len >= 2 else { help(); exit(2); }
    let command = argv[1];
    if command == "help" || command == "-h" || command == "--help" {
        guard argv.len > 2 else { help(); return; }
        guard command_help(argv[2]) else { fail_usage(str("unknown command '", argv[2], "'")); }
        return;
    }
    if command == "version" || command == "--version" || command == "-V" { print("barn ", VERSION); return; }
    guard contains(COMMANDS[..], command) else { fail_usage(str("unknown command '", command, "'")); }
    let error = run(command, argv[2..]);
    if error.len > 0 {
        write_stderr(str("barn: ", error, "\n"));
        exit(1);
    }
}
