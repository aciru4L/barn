#!/usr/bin/env bash
set -u

root="$(cd "$(dirname "$0")/.." && pwd)"
root_native="$root"
command -v cygpath > /dev/null && root_native="$(cygpath -m "$root")"
expected="$root/test/expected.txt"

case "$(uname -s)" in
    MINGW* | MSYS* | CYGWIN*) executable="$root/bin/barn.exe" ;;
    *) executable="$root/bin/barn" ;;
esac

build_output="$(cd "$root" && goose build barn.goose -o "$executable" 2>&1)" || {
    printf '%s\n' "$build_output"
    exit 1
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
work_native="$work"
command -v cygpath > /dev/null && work_native="$(cygpath -m "$work")"
fixtures="$root/test/repository"
version="$(sed -n 's/^let VERSION = "\(.*\)";$/\1/p' "$root/barn.goose")"

barn() { "$executable" "$@"; }

section() { printf '\n## %s\n' "$1"; }

run() {
    printf '$ %s\n' "$*"
    "$@" 2>&1
    local status=$?
    [ "$status" -ne 0 ] && printf '[exit %d]\n' "$status"
    return 0
}

without_goose_progress() {
    printf '$ %s\n' "$*"
    "$@" 2> /dev/null
    local status=$?
    [ "$status" -ne 0 ] && printf '[exit %d]\n' "$status"
    return 0
}

silently() {
    printf '$ %s\n' "$*"
    "$@" > /dev/null 2>&1
    local status=$?
    [ "$status" -ne 0 ] && printf '[exit %d]\n' "$status"
    return 0
}

show() {
    for file in "$@"; do
        printf -- '--- %s\n' "$file"
        cat "$file"
    done
}

enter() {
    printf '$ cd %s\n' "$1"
    cd "$1" || exit 1
}

write_pkg() {
    printf 'owner = "acme";\nname = "app";\nversion = "0.1.0";\n%s' "$1" > barn.pkg
}

scenario() {
    export BARN_REPO="$work/repo" BARN_OWNER=acme
    unset BARN_HOME
    enter "$work"

    section "hatch and lay"
    run barn hatch numbers
    show numbers/barn.pkg numbers/src/numbers.goose numbers/main.goose numbers/test/main_test.goose numbers/.gitignore
    run barn hatch numbers
    run barn hatch Bad-Name
    enter numbers
    run barn lay --release
    run barn lay --release
    sed -i 's/0.1.0/0.1.1/' barn.pkg
    run barn lay --release
    sed -i 's/0.1.1/0.2.0/' barn.pkg
    run barn lay --release
    run barn lay
    enter ..

    section "add and upgrade"
    run barn hatch app
    enter app
    run barn add acme/numbers:0.1.0
    show barn.pkg barn.lock main.goose test/main_test.goose
    run barn upgrade
    run barn add acme/numbers
    run barn add acme/numbers:0.2.0
    run barn add acme/numbers:0.2.0_snapshot
    run barn inspect
    run barn resolve
    run barn add acme/numbers:0.2.0_snapshot
    run barn add acme/nothing
    run barn add nothing
    run barn add acme/numbers:0.2.0

    section "build and run"
    sed -i 's/print(app::honk());/print(numbers::honk());/' main.goose
    without_goose_progress barn run
    silently barn build -- -o "$work/app-executable"
    run "$work/app-executable"
    sed -i 's/numbers:0.2.0/numbers:0.1.1/' barn.pkg
    run barn run
    run barn build
    sed -i 's/numbers:0.1.1/numbers:0.2.0/' barn.pkg
    run barn run --bogus
    mkdir ../arguments
    enter ../arguments
    printf 'import os;\nfn main() {\n    for a in args()[1..] { print(a); }\n    exit(3);\n}\n' > main.goose
    write_pkg ''
    without_goose_progress barn run -- one "two words" -- --repo
    without_goose_progress barn run . --repo "$BARN_REPO"
    write_pkg $'dependencies = ["acme/numbers:0.2.0"];\n'
    run barn run
    enter ../app

    section "test"
    without_goose_progress barn test
    sed -i 's/"honk from app"/"honk from the app"/' test/main_test.goose
    without_goose_progress barn test
    sed -i 's/"honk from the app"/"honk from app"/' test/main_test.goose
    sed -i 's/numbers:0.2.0/numbers:0.1.1/' barn.pkg
    run barn test
    sed -i 's/numbers:0.1.1/numbers:0.2.0/' barn.pkg
    mv test/main_test.goose test/kept.goose
    run barn test
    mv test/kept.goose test/main_test.goose
    mkdir ../checks
    enter ../checks
    mkdir checks
    printf 'import os;\nfn main() {\n    for a in args()[1..] { print(a); }\n    print(numbers::honk());\n}\n' > checks/all.goose
    write_pkg $'test = "checks/all.goose";\ndependencies = ["acme/numbers:0.2.0"];\n'
    run barn install
    show checks/all.goose
    without_goose_progress barn test -- one "two words"
    write_pkg $'test = "checks/missing.goose";\n'
    run barn install
    run barn test
    enter ../app

    section "verify and edited copies"
    run barn verify
    printf '// edited\n' >> .barn/numbers/numbers.goose
    run barn verify
    run barn run
    run barn build
    run barn install
    run barn install --force
    run barn verify

    section "repository changed"
    printf '// changed\n' >> "$BARN_REPO/acme/numbers/0.2.0/numbers.goose"
    run barn install
    (cd "$BARN_REPO/acme/numbers/0.2.0" && sha256sum barn.pkg numbers.goose | sed 's/ [*]/  /' > barn.sha256)
    run barn install
    run barn install --force
    run barn verify

    section "remove"
    run barn remove numbers
    show barn.pkg main.goose test/main_test.goose barn.lock
    run barn remove numbers
    enter ..

    section "transitive"
    run barn hatch stats
    enter stats
    run barn add acme/numbers:0.1.0
    run barn lay --release
    enter ../app
    run barn add acme/stats
    run barn inspect
    run barn remove stats
    enter ..

    section "barn.pkg layouts"
    mkdir layouts
    enter layouts
    printf 'import src.app;\nfn main() {}\n' > main.goose
    write_pkg $'\ndependencies = [\n    "acme/numbers:0.1.0",   // the maths\n    "acme/stats:0.1.0"\n];\n\n// after\n'
    run barn add acme/numbers:0.1.1
    run barn remove stats
    show barn.pkg
    write_pkg $'dependencies = [\n  "acme/numbers:0.1.0"  // two spaces\n];\n'
    run barn add acme/stats
    show barn.pkg
    write_pkg ''
    run barn add acme/stats
    show barn.pkg
    write_pkg $'dependencies = [];\n'
    run barn add acme/stats acme/numbers:0.1.1
    show barn.pkg
    run barn remove stats
    show barn.pkg
    enter ..

    section "local override"
    mkdir local
    enter local
    printf 'fn main() {}\n' > main.goose
    write_pkg $'dependencies = ["acme/numbers:0.1.0"];\noverrides = ["acme/numbers=../numbers"];\n'
    run barn install
    run barn inspect
    show main.goose barn.lock
    run barn verify
    without_goose_progress barn run
    enter ..

    section "uppercase"
    BARN_OWNER=Acme run barn hatch loud
    run barn hatch shouty --owner ACME
    show loud/barn.pkg shouty/barn.pkg
    mkdir uppercase
    enter uppercase
    printf 'fn main() {}\n' > main.goose
    write_pkg $'dependencies = ["Acme/numbers:0.1.0"];\noverrides = ["ACME/numbers:0.1.1"];\n'
    run barn install
    show barn.lock
    run barn add ACME/stats
    run barn add acme/Stats
    run barn upgrade numbers
    run barn upgrade Numbers
    run barn remove ACME/stats
    show barn.pkg
    write_pkg $'dependencies = ["acme/numbers:0.1.0", "Acme/numbers:0.1.0"];\n'
    run barn resolve
    write_pkg $'dependencies = ["acme/Numbers:0.1.0"];\n'
    run barn resolve
    printf 'owner = "Acme";\nname = "app";\nversion = "0.1.0";\n' > barn.pkg
    run barn resolve
    enter ..

    section "resolution"
    run barn inspect "$fixtures/../app" --repo "$fixtures"
    run barn resolve "$fixtures/../app" --repo "$fixtures"
    mkdir resolution
    enter resolution
    write_pkg $'dependencies = ["example/auth:1.0.0", "example/json:0.6.0", "a/b:1.0.0"];\n'
    run barn inspect --repo "$fixtures"
    write_pkg $'dependencies = ["example/auth:1.0.0", "example/json:0.6.0"];\noverrides = ["example/json:0.6.0"];\n'
    run barn inspect --repo "$fixtures"
    write_pkg $'dependencies = ["example/json:0.5.0"];\noverrides = ["acme/net:0.3.0"];\n'
    run barn resolve --repo "$fixtures"
    write_pkg $'dependencies = ["acme/net:0.3.0_snapshot"];\n'
    run barn resolve --repo "$fixtures"
    enter ..

    section "barn.pkg errors"
    mkdir errors
    enter errors
    write_pkg $'dependencies = [\n];\n\ndependencyManagement = [\n];\n'
    run barn resolve --repo "$fixtures"
    write_pkg $'dependencyManagement = ["example/json:0.4.0->0.5.0"];\n'
    run barn resolve --repo "$fixtures"
    write_pkg $'local = ["a/b=../b"];\n'
    run barn resolve --repo "$fixtures"
    write_pkg $'dependencies = ["example/json"];\n'
    run barn resolve --repo "$fixtures"
    write_pkg $'dependencies = ["example/json:0.4.0->0.5.0"];\n'
    run barn resolve --repo "$fixtures"
    write_pkg $'dependencies = ["example/json:0.4"];\n'
    run barn resolve --repo "$fixtures"
    write_pkg $'dependencies = ["example/json:0.5.0", "example/json:0.5.0"];\n'
    run barn resolve --repo "$fixtures"
    write_pkg $'version = "0.2.0";\n'
    run barn resolve --repo "$fixtures"
    write_pkg $'test = "../outside.goose";\n'
    run barn resolve --repo "$fixtures"
    write_pkg $'test = "a.goose";\ntest = "b.goose";\n'
    run barn resolve --repo "$fixtures"
    write_pkg $'colour = "red";\n'
    run barn resolve --repo "$fixtures"
    enter ..

    section "usage"
    run barn
    run barn frob
    run barn install --bogus
    run barn hatch
    run barn add
    run barn install a b
    run barn help lay
    run barn help run
    run barn help test
    run barn help frob
    run barn version
}

normalize() {
    sed -e "s|$work_native|<work>|g" -e "s|$root_native|<root>|g" -e "s|$root|<root>|g" -e "s|$work|<work>|g" -e 's/[0-9]\{8\}T[0-9]\{6\}Z/<stamp>/g' \
        -e "s/^barn $version\$/barn <version>/"
}

actual="$(scenario | normalize)"

if [ "${1:-}" = "--update" ]; then
    printf '%s\n' "$actual" > "$expected"
    echo "updated test/expected.txt"
    exit 0
fi

if diff -u "$expected" <(printf '%s\n' "$actual"); then
    echo "ok"
else
    exit 1
fi
