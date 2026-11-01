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
fixtures="$root/test/home"
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
    local more=""
    [ -n "$1" ] && more=$',\n  '"$1"
    printf '{\n  "owner": "acme",\n  "name": "app",\n  "version": "0.1.0"%s\n}\n' "$more" > barn.json
}

commit_all() {
    git init -q . && git add -A && git commit -q -m "release" > /dev/null 2>&1
}

scenario() {
    export BARN_HOME="$work/home" BARN_OWNER=acme
    export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME="barn test" GIT_COMMITTER_NAME="barn test"
    export GIT_AUTHOR_EMAIL=test@example.invalid GIT_COMMITTER_EMAIL=test@example.invalid
    export GIT_AUTHOR_DATE=2026-01-01T00:00:00Z GIT_COMMITTER_DATE=2026-01-01T00:00:00Z
    enter "$work"
    mkdir -p home remotes
    printf '{"hosts": {"github.com": {"url": "%s/remotes"}, "gitlab.com": {"url": "%s/remotes"}}}\n' \
        "$work_native" "$work_native" > home/config.json

    section "hatch and lay"
    run barn hatch numbers
    show numbers/barn.json numbers/numbers.goose numbers/test/main_test.goose numbers/.gitignore
    run barn hatch numbers
    run barn hatch Bad-Name
    enter numbers
    commit_all
    run barn lay --release
    run barn lay --release
    sed -i 's/0.1.0/0.1.1/' barn.json
    commit_all
    run barn lay --release
    sed -i 's/0.1.1/0.2.0/' barn.json
    commit_all
    run barn lay --release
    run barn lay
    run barn lay
    run ls "$BARN_HOME/eggs/github.com/acme/numbers"
    enter ..

    section "add and upgrade"
    run barn hatch app --app
    enter app
    run barn add acme/numbers:0.1.0
    show barn.json main.goose test/main_test.goose
    run barn upgrade
    run barn add acme/numbers
    run barn add acme/numbers:0.2.0
    run barn add acme/numbers:0.2.0_snapshot
    run barn inspect
    run barn inspect --flat
    run barn add acme/numbers:0.2.0_snapshot
    run barn add acme/nothing
    run barn add nothing
    run barn add acme/numbers:0.2.0

    section "build and run"
    sed -i 's/print(app::honk());/print(numbers::honk());/' main.goose
    without_goose_progress barn run
    silently barn build -- -o "$work/app-executable"
    run "$work/app-executable"
    sed -i 's/"0.2.0"/"0.1.1"/' barn.json
    run barn run
    run barn build
    sed -i 's/"0.1.1"/"0.2.0"/' barn.json
    run barn run --bogus
    mkdir ../arguments
    enter ../arguments
    printf 'import os;\nfn main() {\n    for a in args()[1..] { print(a); }\n    exit(3);\n}\n' > main.goose
    write_pkg ''
    without_goose_progress barn run -- one "two words" -- --repo
    without_goose_progress barn run .
    write_pkg '"dependencies": {"acme/numbers": "0.2.0"}'
    run barn run
    enter ../app

    section "test"
    without_goose_progress barn test
    sed -i 's/"honk from app"/"honk from the app"/' test/main_test.goose
    without_goose_progress barn test
    sed -i 's/"honk from the app"/"honk from app"/' test/main_test.goose
    sed -i 's/"0.2.0"/"0.1.1"/' barn.json
    run barn test
    sed -i 's/"0.1.1"/"0.2.0"/' barn.json
    mv test/main_test.goose test/kept.goose
    run barn test
    mv test/kept.goose test/main_test.goose
    mkdir ../checks
    enter ../checks
    mkdir checks
    printf 'import os;\nfn main() {\n    for a in args()[1..] { print(a); }\n    print(numbers::honk());\n}\n' > checks/all.goose
    write_pkg $'"test": "checks/all.goose",\n  "dependencies": {"acme/numbers": "0.2.0"}'
    run barn install
    show checks/all.goose
    without_goose_progress barn test -- one "two words"
    write_pkg '"test": "checks/missing.goose"'
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

    section "eggs folder changed"
    printf '// changed\n' >> "$BARN_HOME/eggs/github.com/acme/numbers/0.2.0/numbers.goose"
    run barn install
    (cd "$BARN_HOME/eggs/github.com/acme/numbers/0.2.0" && sha256sum barn.json numbers.goose | sed 's/ [*]/  /' > barn.sha256)
    run barn install
    run barn install --force
    run barn verify

    section "remove"
    run barn remove numbers
    show barn.json main.goose test/main_test.goose
    run barn remove numbers
    enter ..

    section "transitive"
    run barn hatch stats
    enter stats
    run barn add acme/numbers:0.1.0
    commit_all
    run barn lay --release
    enter ../app
    run barn add acme/stats
    run barn inspect
    run barn remove stats
    enter ..

    section "barn.json rewrites"
    mkdir layouts
    enter layouts
    printf 'import src.app;\nfn main() {}\n' > main.goose
    printf '{"owner": "acme", "name": "app", "version": "0.1.0", "main": "main.goose",\n' > barn.json
    printf ' "dependencies": {"acme/numbers": "0.1.0", "acme/stats": "0.1.0"}}\n' >> barn.json
    run barn add acme/numbers:0.1.1
    run barn remove stats
    show barn.json
    write_pkg ''
    run barn add acme/stats acme/numbers:0.1.1
    show barn.json
    run barn remove stats numbers
    show barn.json
    enter ..

    section "local override"
    mkdir local
    enter local
    printf 'fn main() {}\n' > main.goose
    write_pkg $'"dependencies": {"acme/numbers": "0.1.0"},\n  "overrides": {"acme/numbers": "../numbers"}'
    run barn install
    run barn inspect
    show main.goose
    run barn verify
    without_goose_progress barn run
    run barn add acme/stats
    show barn.json
    enter ..

    section "uppercase"
    BARN_OWNER=Acme run barn hatch loud
    run barn hatch shouty --owner ACME
    show loud/barn.json shouty/barn.json
    mkdir uppercase
    enter uppercase
    printf 'fn main() {}\n' > main.goose
    write_pkg $'"dependencies": {"Acme/numbers": "0.1.0"},\n  "overrides": {"ACME/numbers": "0.1.1"}'
    run barn install
    run ls .barn
    run barn add ACME/stats
    run barn add acme/Stats
    run barn upgrade numbers
    run barn upgrade Numbers
    run barn remove ACME/stats
    show barn.json
    write_pkg '"dependencies": {"acme/numbers": "0.1.0", "Acme/numbers": "0.1.0"}'
    run barn inspect --flat
    write_pkg '"dependencies": {"acme/Numbers": "0.1.0"}'
    run barn inspect --flat
    printf '{"owner": "Acme", "name": "app", "version": "0.1.0"}\n' > barn.json
    run barn inspect --flat
    enter ..

    section "resolution"
    BARN_HOME="$fixtures" run barn inspect "$root/test/app"
    BARN_HOME="$fixtures" run barn inspect --flat "$root/test/app"
    mkdir resolution
    enter resolution
    write_pkg '"dependencies": {"example/auth": "1.0.0", "example/json": "0.6.0", "a/b": "1.0.0"}'
    BARN_HOME="$fixtures" run barn inspect
    write_pkg $'"dependencies": {"example/auth": "1.0.0", "example/json": "0.6.0"},\n'\
'  "overrides": {"example/json": "0.6.0"}'
    BARN_HOME="$fixtures" run barn inspect
    write_pkg $'"dependencies": {"example/json": "0.5.0"},\n  "overrides": {"acme/net": "0.3.0"}'
    BARN_HOME="$fixtures" run barn inspect --flat
    write_pkg '"dependencies": {"acme/net": "0.3.0_snapshot"}'
    BARN_HOME="$fixtures" run barn inspect --flat
    enter ..

    section "barn.json errors"
    mkdir errors
    enter errors
    write_pkg '"dependencies": {}'
    BARN_HOME="$fixtures" run barn inspect --flat
    write_pkg '"dependencies": ["example/json:0.5.0"]'
    BARN_HOME="$fixtures" run barn inspect --flat
    write_pkg '"dependencies": {"example/json": 5}'
    BARN_HOME="$fixtures" run barn inspect --flat
    write_pkg '"dependencies": {"example/json": "0.4.0->0.5.0"}'
    BARN_HOME="$fixtures" run barn inspect --flat
    write_pkg '"dependencies": {"example/json": "0.4"}'
    BARN_HOME="$fixtures" run barn inspect --flat
    write_pkg '"dependencies": {"example/json": "0.5.0_snapshot_20260101T000000Z"}'
    BARN_HOME="$fixtures" run barn inspect --flat
    write_pkg '"dependencies": {"example/json": "0.5.0", "example/json": "0.5.0"}'
    BARN_HOME="$fixtures" run barn inspect --flat
    write_pkg '"dependencies": {"json": "0.5.0"}'
    BARN_HOME="$fixtures" run barn inspect --flat
    write_pkg '"overrides": {"example/json": "/elsewhere"}'
    BARN_HOME="$fixtures" run barn inspect --flat
    write_pkg '"version": "0.2.0"'
    BARN_HOME="$fixtures" run barn inspect --flat
    write_pkg '"test": "../outside.goose"'
    BARN_HOME="$fixtures" run barn inspect --flat
    write_pkg '"colour": "red"'
    BARN_HOME="$fixtures" run barn inspect --flat
    write_pkg $'"dependencies": {"example/json": "0.5.0",}'
    BARN_HOME="$fixtures" run barn inspect --flat
    write_pkg $'// a comment\n  "dependencies": {}'
    BARN_HOME="$fixtures" run barn inspect --flat
    printf '{"name": "app", "version": "0.1.0"}\n' > barn.json
    BARN_HOME="$fixtures" run barn inspect --flat
    printf '[]\n' > barn.json
    BARN_HOME="$fixtures" run barn inspect --flat
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
    run barn help inspect
    run barn help frob
    run barn resolve
    run barn version

    section "egg contents"
    run barn hatch shapes --app
    enter shapes
    mkdir notes bench docs examples .private
    printf 'namespace shapes;\nfn area() -> int { return 1; }\n' > extra.goose
    printf 'todo\n' > notes/todo.txt
    printf 'fn main() {}\n' > bench/speed.goose
    printf 'docs\n' > docs/guide.md
    printf 'fn main() {}\n' > examples/demo.goose
    printf 'secret\n' > .private/key
    printf 'license\n' > LICENSE
    printf 'readme\n' > README.md
    printf 'built\n' > shapes.exe
    sed -i 's/"version": "0.1.0",/"version": "0.1.0",\n  "exclude": ["notes"],/' barn.json
    printf 'namespace shapes;\nimport numbers from "acme/numbers@v0.1.0";\n' > uses.goose
    run barn lay --check
    commit_all
    run barn lay --release
    run ls -A "$BARN_HOME/eggs/github.com/acme/shapes/0.1.0"
    run barn add acme/numbers:0.1.0
    show barn.json
    enter ..
    mkdir layered
    enter layered
    mkdir lib
    printf 'namespace layered;\n' > lib/layered.goose
    printf 'license\n' > LICENSE
    printf '{"owner": "acme", "name": "layered", "version": "0.1.0", "source": "lib"}\n' > barn.json
    commit_all
    run barn lay --release
    run ls -A "$BARN_HOME/eggs/github.com/acme/layered/0.1.0"
    rm lib/layered.goose
    run barn lay
    printf 'namespace other;\n' > lib/layered.goose
    run barn lay
    printf '{"owner": "acme", "name": "layered", "version": "0.1.0", "source": "missing"}\n' > barn.json
    run barn lay
    printf '{"owner": "acme", "name": "layered", "version": "0.1.0", "source": "../lib"}\n' > barn.json
    run barn lay
    printf '{"owner": "acme", "name": "layered", "version": "0.1.0", "source": "lib"}\n' > barn.json
    printf 'namespace layered;\n' > lib/layered.goose
    enter ..
    mkdir layered_user
    enter layered_user
    printf 'fn main() {}\n' > main.goose
    write_pkg $'"dependencies": {"acme/layered": "0.1.0"},\n  "overrides": {"acme/layered": "../layered"}'
    run barn install
    show main.goose
    enter ..

    section "git-ignored files"
    silently barn hatch tracked
    enter tracked
    git init -q .
    printf 'scratch.goose\n' >> .gitignore
    printf 'fn main() {}\n' > scratch.goose
    printf 'namespace tracked;\n' > helper.goose
    commit_all
    run barn lay --release
    run ls -A "$BARN_HOME/eggs/github.com/acme/tracked/0.1.0"
    run ls -A
    enter ..

    section "repositories"
    silently barn hatch geometry
    enter geometry
    sed -i 's/"version": "0.1.0",/"version": "0.1.0",\n  "repo": "acme\/goose-geometry",/' barn.json
    commit_all
    run barn lay --release
    enter ..
    mkdir tools
    enter tools
    printf 'namespace tools;\n' > tools.goose
    printf '{"owner": "acme", "name": "tools", "version": "0.1.0", "repo": "gitlab.com/acme/tools"}\n' > barn.json
    commit_all
    run barn lay --release
    enter ..
    mkdir other_geometry
    enter other_geometry
    printf 'namespace geometry;\n' > geometry.goose
    printf '{"owner": "acme", "name": "geometry", "version": "0.1.0", "repo": "acme/geometry-two"}\n' > barn.json
    commit_all
    silently barn lay --release
    enter ..
    run ls "$BARN_HOME/eggs" "$BARN_HOME/eggs/gitlab.com/acme"
    mkdir repos
    enter repos
    printf 'fn main() {}\n' > main.goose
    write_pkg ''
    run barn add acme/goose-geometry gitlab.com/acme/tools github.com/acme/numbers:0.1.0
    show barn.json main.goose
    run barn inspect
    run ls .barn
    run barn add acme/geometry-two
    run barn remove goose-geometry tools
    run barn add acme/Geometry-two
    write_pkg '"repo": "acme/Goose Geometry"'
    run barn inspect
    enter ..

    section "git releases"
    silently barn hatch loose
    enter loose
    run barn lay --release
    commit_all
    printf '// more\n' >> loose.goose
    printf 'new\n' > notes.txt
    run barn lay --release
    git checkout -q -- loose.goose
    rm notes.txt
    git init -q --bare ../loose-origin.git
    git remote add origin ../loose-origin.git
    printf 'n\n' | run barn lay --release
    show "$BARN_HOME/eggs/github.com/acme/loose/0.1.0/barn.origin"
    run git tag
    rm -rf "$BARN_HOME/eggs/github.com/acme/loose/0.1.0"
    run barn lay --release
    sed -i 's/0.1.0/0.2.0/' barn.json
    commit_all
    run barn lay --release -y
    run git ls-remote --tags origin
    git tag -d v0.2.0 > /dev/null
    rm -rf "$BARN_HOME/eggs/github.com/acme/loose/0.2.0"
    run barn lay --release
    enter ..

    section "fetching"
    mkdir -p remotes/acme
    git init -q --bare remotes/acme/fetched
    silently barn hatch fetched
    enter fetched
    commit_all
    git remote add origin ../remotes/acme/fetched
    silently barn lay --release -y
    enter ..
    export BARN_HOME="$work/elsewhere"
    mkdir elsewhere
    printf '{"hosts": {"github.com": {"url": "%s/remotes"}}}\n' "$work_native" > elsewhere/config.json
    mkdir consumer
    enter consumer
    printf 'fn main() {}\n' > main.goose
    write_pkg '"dependencies": {"acme/fetched": "0.1.0"}'
    run barn inspect
    run barn install
    run ls -A "$BARN_HOME/eggs/github.com/acme/fetched"
    run ls -A "$BARN_HOME/eggs/github.com/acme/fetched/0.1.0"
    show "$BARN_HOME/eggs/github.com/acme/fetched/0.1.0/barn.origin"
    run barn install
    run barn verify
    enter ../fetched
    sed -i 's/0.1.0/0.2.0/' barn.json
    commit_all
    BARN_HOME="$work/home" silently barn lay --release -y
    enter ../consumer
    run barn upgrade
    run barn add acme/fetched
    git -C ../remotes/acme/fetched tag -f v0.1.0 v0.2.0 > /dev/null
    run barn upgrade
    run barn install
    first_commit="$(git -C ../fetched rev-parse HEAD~1)"
    git -C ../remotes/acme/fetched tag -f v0.1.0 "$first_commit" > /dev/null
    run barn install --set local_priority=false
    git -C ../remotes/acme/fetched tag -f v0.2.0 "$first_commit" > /dev/null
    run barn install
    run barn install --set local_priority=false
    run barn install --offline --set local_priority=false
    write_pkg $'"local_priority": false,\n  "dependencies": {"acme/fetched": "0.2.0"}'
    run barn install
    run barn install --set local_priority=true
    run barn add acme/fetched --offline
    show barn.json
    run barn install --set colour=red
    write_pkg '"dependencies": {"acme/fetched": "0.9.0"}'
    run barn install
    write_pkg '"dependencies": {"acme/missing": "0.1.0"}'
    run barn install
    enter ..
    export BARN_HOME="$work/home"

    section "releases only"
    silently barn hatch draft
    enter draft
    silently barn lay
    enter ..
    mkdir releases
    enter releases
    write_pkg ''
    run barn add acme/draft
    run barn add acme/draft:0.1.0
    run barn add acme/draft:0.1.0_snapshot
    enter ../draft
    printf '// newer\n' >> draft.goose
    silently barn lay
    enter ../releases
    run barn verify
    run barn install
    run barn verify
    enter ..

    section "eggs folder"
    silently barn hatch plain
    export BARN_HOME="$work/other-home"
    run barn inspect --flat plain
    run barn lay --check plain
    run test -d "$BARN_HOME/eggs"
    run barn install plain
    run ls "$BARN_HOME"
    run barn install plain
    unset BARN_HOME
    export HOME="$work/user" USERPROFILE="$work_native/user"
    run barn lay plain
    run ls "$HOME/.barn"
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
