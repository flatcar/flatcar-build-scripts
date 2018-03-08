# Applying Flatcar patches

To apply Flatcar patches on top of a Container Linux release we use the
[`apply-flatcar-patches` script](../apply-flatcar-patches).

## What does the script do?

This script will sync a tag from
[coreos/manifest](https://github.com/coreos/manifest) using
[repo](https://gerrit.googlesource.com/git-repo).

It will then go to each git repo, create a branch named `build-$BUILD_ID`,
(where `$BUILD_ID` is the Container Linux release we're patching) and try to
apply the corresponding Flatcar commit.
This commit lives in a branch named `flatcar` on each mirrored repository in
the [flatcar-linux](https://github.com/flatcar-linux) organization.
If there's any conflicts, the caller of the script will need to fix them.

Then, the `build-$BUILD_ID` branch will be pushed to the mirrored repository,
the repo manifest will be updated to the new repository, commit, id and
reference.
After that, if needed, the repository ebuild will update its
`CROS_WORKON_COMMIT` to the new commit id so ebuilds build the correct version.

The last step is manual and involves going to the manifests directory, checking
everything is OK, committing, tagging, and pushing the new version to the
[manifest repository](https://github.com/flatcar-linux/manifest). The script
will print rough instructions for that.
