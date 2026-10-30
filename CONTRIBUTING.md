# Contributing

Barn follows the Unix rules of clarity, silence and repair from Eric S. Raymond's
*The Art of Unix Programming*, the self-documenting code of Robert C. Martin's
*Clean Code*, and Rob Pike's Go proverb *clear is better than clever*.

## Code

- **No comments.** If code needs one, rename or extract until it does not.
  Reasons the code cannot show belong in the documentation.
- **Names** are full words. Functions are verbs (`load_project`), booleans read as
  questions (`is_released`).
- **Functions** do one thing, stay short (about 40 lines) and nest at most three levels.
- **Data** lives in structs, never encoded in strings.
- **Modules** hold one concept each.
- **Format**: 4 spaces, lines up to 120 characters.

## Behaviour

- **Output** states facts. Nothing is printed when nothing surprising happened.
- **Errors** protect barn's own integrity: checksums, immutable releases, versions
  that cannot be resolved. Anything about the user's code is a warning.

## Tests

- `test/run.sh` builds barn, runs every scenario and compares the output with
  `test/expected.txt`. It passes before every commit.
- Every change in behaviour comes with a scenario. `test/run.sh --update` rewrites
  the expected output; review the diff before committing it.

## Commits

- [Conventional Commits](https://www.conventionalcommits.org): `feat:`, `fix:`,
  `refactor:`, `test:`, `docs:`, `chore:`. One concern per commit.
- No personal names, emails or machine paths in any file.

## Versions

Barn is versioned with [SemVer](https://semver.org), and changes are recorded in
`CHANGELOG.md` as [Keep a Changelog](https://keepachangelog.com) describes.
