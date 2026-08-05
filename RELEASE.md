# Releasing this project

The routine, start to finish. Settings live in [build/build.json](build/build.json); the
commands below come from the build kit in [build/](build/).

## One-time setup

- **CommandBox** installed (`box version`).
- **GitHub CLI** signed in, if you publish GitHub Releases: `gh auth login`.
- **ForgeBox** signed in, if you publish there: `box forgebox login`.
- A test server you can start, unless `runTests` is off in build.json.
- `branch` in build/build.json set to the production branch you publish from, normally `main`
  or `master`. In Gitflow this is never `develop` or `release/*`.

Check all of it at once:

```
box run-script release:check
```

## The routine

### 1. Write your notes as you work

Put changes under `## [Unreleased]` in the changelog. Write them for the people who use the
project, because this text becomes the release notes.

### 2. Test on every engine

```
box run-script test:engines
```

Runs the whole suite on each engine in turn. It takes a while, so it is a separate step. Skip
it if your project only supports one engine.

### 3. Raise the version

> **Using Gitflow?** Create `release/<version>` from `develop` first, then run the bump on
> that release branch. Do not bump `develop` before creating the branch. Follow the complete
> sequence in the [Gitflow cheat sheet](#gitflow-cheat-sheet) below.

```
box run-script bump:patch     # bug fixes           1.0.0 -> 1.0.1
box run-script bump:minor     # new features        1.0.0 -> 1.1.0
box run-script bump:major     # breaking changes    1.0.0 -> 2.0.0
```

This raises the version in box.json and moves your `[Unreleased]` notes into a dated section.
It does not commit anything.

Add `:dryRun=true` to any of these to see what would change without writing anything.

**Your notes are required.** If `[Unreleased]` is empty, nothing happens at all: no version
change and no changelog change. The dated section becomes your release notes on GitHub, so an
empty one would ship a release nobody can interpret. Write a line first, even just
`- Maintenance release`.

**Releasing 1.0.0 for the first time?** box.json probably already says 1.0.0, and raising it
would skip that number. Date the notes without changing the version:

```
box task run taskFile=build/Bump.cfc :level=none
```

#### Alphas and betas

Version numbers follow SemVer, where `1.2.0-beta.3` comes **before** `1.2.0`. These commands
follow the same rule, so finishing a beta lands on the version it was leading up to rather than
stepping past it.

```
box run-script bump:beta          # start one:  1.1.0 -> 1.2.0-beta.1
box run-script bump:alpha         # the same, labelled alpha
box run-script bump:prerelease    # step it on: 1.2.0-beta.1 -> 1.2.0-beta.2
box run-script bump:patch         # finish it:  1.2.0-beta.2 -> 1.2.0
```

`bump:beta` and `bump:alpha` start a prerelease of the next **minor** version. For a prerelease
of the next patch or major instead, name the level yourself:

```
box task run taskFile=build/Bump.cfc :level=prepatch     # 1.1.0 -> 1.1.1-beta.1
box task run taskFile=build/Bump.cfc :level=preminor     # 1.1.0 -> 1.2.0-beta.1
box task run taskFile=build/Bump.cfc :level=premajor     # 1.1.0 -> 2.0.0-beta.1
```

Add `:preid=rc` to use a different label. Switching label restarts the count, so
`1.2.0-alpha.7` with `:preid=beta` becomes `1.2.0-beta.1`.

A prerelease is flagged as one on GitHub automatically, because the version contains a hyphen.

Every level, for reference:

| Level | What it does |
| --- | --- |
| `patch`, `minor`, `major` | Raise the version. On a prerelease, settle on the version it was leading up to. |
| `prerelease` | Step an existing prerelease forward, `beta.3` to `beta.4`. |
| `prepatch`, `preminor`, `premajor` | Start a prerelease. Uses `:preid=beta` unless you say otherwise. |
| `none` | Keep the version and just date the changelog. |

### 4. Check and commit

```
git status
git diff -- box.json CHANGELOG.md
git add box.json CHANGELOG.md
git diff --staged
git commit -m "Release 1.0.1"
git push origin <current-branch>
```

Replace `CHANGELOG.md`, `1.0.1`, and `<current-branch>` with the values for your project.

**Using GitKraken or another Git GUI?** Review the changed `box.json` and changelog, stage only
those release files, review the staged changes, commit them as `Release 1.0.1`, and then push
the current branch. Those are the GUI equivalents of the commands above.

- `git status` lists changed and untracked files.
- `git diff` shows the unstaged version and changelog edits for review.
- `git add` selects exactly those files for the next commit.
- `git diff --staged` previews exactly what the commit will contain.
- `git commit` records that snapshot in your local repository; it does not upload anything.
- `git push` sends the commit to the named branch on the `origin` remote.

Using explicit `git add` is intentional. `git commit -am` skips untracked files, which can make
a commit look complete when a new release file was left out.

### 5. Rehearse (recommended the first few times)

```
box run-script release:dryrun
```

Runs the checks and the full build, then prints exactly what it would publish, tag, and push.
Nothing leaves your machine. You can rehearse from a Gitflow `release/*` branch; the command
warns that the real release must still run from the configured production branch.

### 6. Release

Start a test server first, unless `runTests` is off:

```
box run-script release
```

That runs the checks, lines up with the remote, runs the tests, builds and verifies the
package, publishes it, tags the version, and creates the GitHub Release.

## Gitflow cheat sheet

In Gitflow, `develop` collects features, `release/<version>` prepares a release, and the
production branch records published releases. A finished release must reach both production
and `develop`. The build kit's `branch` setting always names production.

The branch order is the important part:

1. Create the release branch from an up-to-date `develop`.
2. While checked out on the release branch, bump the version and commit the version and
   changelog changes. **Do not run the bump on `develop` before creating the branch.**
3. Test and rehearse on the release branch.
4. Finish the release by merging it into both production and `develop`.
5. Publish from production, using the command that matches whichever tool created the tag.

See Atlassian's
[Gitflow workflow guide](https://www.atlassian.com/git/tutorials/comparing-workflows/gitflow-workflow/)
for the branch model.

### Plain Git or pull requests

This path lets the build kit create the tag. The example releases `1.2.0`; substitute your
version and production branch name.

1. Start from an up-to-date `develop` branch:

   ```
   git switch develop
   git pull --ff-only origin develop
   git switch -c release/1.2.0
   ```

2. You are now on `release/1.2.0`. Finalize the notes and run the appropriate bump here, not
   on `develop`:

   ```
   box run-script bump:minor
   git diff -- box.json CHANGELOG.md
   git add box.json CHANGELOG.md
   git diff --staged
   git commit -m "Release 1.2.0"
   ```

   Push the preparation branch with:

   ```
   git push -u origin release/1.2.0
   ```

3. Test and rehearse on the release branch:

   ```
   box run-script test:engines
   box run-script release:dryrun
   ```

4. Merge `release/1.2.0` into both the production branch and `develop`. Use pull requests when
   your repository requires review. Do not delete the release branch until both merges land.

5. Check out the updated production branch and publish:

   ```
   git switch main
   git pull --ff-only origin main
   box run-script release:check
   box run-script release
   ```

6. After the publish succeeds and both merges are present, delete the release branch locally
   and remotely if your pull-request host did not already do so.

A Gitflow hotfix starts from production instead of `develop`, usually bumps the patch version,
and is also bumped on its `hotfix/<version>` branch before being merged into production and
`develop`.

### Using GitKraken

GitKraken's **Finish release** action merges the release into production and `develop` and
always creates a tag. It does not offer the command-line extension's no-tag finish option.
Configure the version-tag prefix under **Preferences > Gitflow** to match `tagPrefix` in
build/build.json; the usual value is `v`. See GitKraken's
[Gitflow documentation](https://help.gitkraken.com/gitkraken-desktop/git-flow/).

1. Create `release/1.2.0` from `develop` in GitKraken.
2. On `release/1.2.0`, run `box run-script bump:minor`, review the files, and commit them.
3. Test and run `box run-script release:dryrun` on the release branch.
4. Use **Finish release**. GitKraken merges both branches and creates `v1.2.0`.
5. Push production, `develop`, and `v1.2.0`, then check out the updated production branch.
6. Choose one publisher:
   - If the tag push triggers the supplied GitHub Actions workflow, let that workflow publish.
   - To publish locally, run `box run-script release:existing-tag`.

`release:existing-tag` runs the normal checks, tests, package build, ForgeBox publish, and
GitHub Release creation, but it does not create, move, or push the tag. It refuses unless the
expected tag points exactly at the checked-out production commit. Do not run the ordinary
`box run-script release` after GitKraken finishes; that command owns tag creation and therefore
rejects an existing tag.

### Using the `git-flow` extension

The commands below use the extension's
[documented release `finish` behavior](https://github.com/nvie/gitflow/blob/develop/git-flow-release)
and its `-n` no-tag option.

Set its version-tag prefix to the build kit's `tagPrefix` once. The default here is `v`:

```
git config gitflow.prefix.versiontag v
```

Choose exactly one of these finish paths so only one tool owns the tag:

- **Publish locally with the build kit:** run `git flow release finish -n 1.2.0` so Gitflow
  performs both merges without tagging. Push production and `develop`, switch to production,
  then run `box run-script release`; the build kit creates and pushes `v1.2.0`.
- **Let Gitflow create the tag:** run the normal `git flow release finish 1.2.0`, then push
  production, `develop`, and `v1.2.0`. Either let the tag-triggered GitHub Actions workflow
  publish it or switch to production and run `box run-script release:existing-tag` locally.

Never run the normal tagging form of `git flow release finish` and then run the ordinary
`box run-script release` command. Both would try to own the same tag, and the ordinary command
correctly refuses.

### If the release tag already exists before Finish

First find out whether the tag is only local or has already been shared:

```
git fetch --tags origin
git show --no-patch --decorate v1.2.0
git ls-remote --tags origin refs/tags/v1.2.0
```

- If both finish merges already landed and `v1.2.0` points at production `HEAD`, do not Finish
  again. Push any unpushed branches and tag, then use `release:existing-tag` or the tag workflow.
- If the required merges have not landed, merge the release into production and `develop`
  manually or through pull requests so no tool tries to recreate the tag. The tag must resolve
  to the final production `HEAD` before `release:existing-tag` will publish it.
- If the tag is an accidental, local-only tag that has never been published or consumed,
  delete that local tag and then let GitKraken Finish. In GitKraken, right-click the tag and
  choose **Delete locally**; at the command line use `git tag -d v1.2.0`.
- If the tag is on the remote, has already been published, or points at a different commit,
  do not silently delete or move it. The version may already be claimed. Verify the release
  history and either choose a new version or coordinate an intentional repair.

## Already tested and deliberately skipping the release test run?

```
box run-script release:skip-tests
```

Same as `release`, but skips the test suite and says so loudly. The older
`box run-script release:hotfix` name remains as an alias. Neither command creates, merges, or
finishes a Gitflow hotfix branch.

## If something fails partway

Everything that can stop a release happens **before** anything is published. If a step fails
**after** publishing, do not run the release again: the version is already out, so the checks
will refuse. The failure message prints the exact commands to finish by hand.

To finish the tag and GitHub Release when the tag was not created yet:

```
box task run taskFile=build/Release.cfc target=github :version=1.0.1
```

If the failure message says the tag was already pushed, publish that existing tag instead:

```
box task run taskFile=build/Release.cfc target=github :version=1.0.1 :existingTag=true
```

## Common problems

| Message | What it means |
| --- | --- |
| `You have uncommitted changes` | Commit or stash first. The release refuses so the forced checkout cannot throw work away. |
| `No answer from the test server` | Start your server, or set `runTests` to false in build.json. |
| `Could not find the GitHub CLI` | Install it, then **open a new terminal**. A terminal keeps the PATH it started with. |
| `Permission denied (publickey)` | git cannot sign in to your remote. Add your SSH key on GitHub, or switch the remote to HTTPS. |
| `has no "## [1.0.1]" section` | Run a `bump:` command to move your notes into a dated section. |
| `The "## [Unreleased]" section is empty` | Write your release notes first. Nothing was changed. |
| `is not a prerelease, so there is nothing to step forward` | Use `bump:beta` to start one, not `bump:prerelease`. |
| `Tag v1.0.1 already exists` | That version is already released. Raise the version. |
| `Tag v1.0.1 already exists on origin` | Fetch tags and choose a version that has not already been published. |
| `Tag v1.0.1 does not point at the checked-out commit` | A tag-triggered build checked out the wrong source. Check the workflow ref and version. |
