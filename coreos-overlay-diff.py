#!/usr/bin/env python3

from sh import which, ErrorReturnCode  # Requires "sh": sudo dnf install python3-sh
from sh.contrib import git
# Read docs here: http://amoffat.github.io/sh/index.html

import argparse
import os
from pathlib import Path

parser = argparse.ArgumentParser(description="Compare two coreos-overlay branches including "
                                             "dereferened CROS_WORKON_COMMIT branches of "
                                             "repositories located in coreos-overlay/../.")

parser.add_argument("THEIRS", type=str, help="Reference/branch to compare to")
parser.add_argument("--ours", type=str, help="Our reference (defaults to \"HEAD\")")
parser.add_argument("--coreos-overlay", type=str, help="Path to coreos-overlay repository (defaults to \".\")")
parser.add_argument("--no-color", dest="no_color", action="store_true", help="Don't pipe diff through colordiff")
parser.add_argument("--no-commits", dest="no_commits", action="store_true", help="Don't log which commits are missing")
parser.add_argument("--no-diffs", dest="no_diffs", action="store_true", help="Don't show diffs")
parser.add_argument("--use-delta", dest="use_delta", action="store_true", help="Use https://github.com/dandavison/delta instead of colordiff")
parser.set_defaults(ours="HEAD", coreos_overlay=".", no_color=False, no_commits=False, no_diffs=False)
args = parser.parse_args()

base_folder = str(Path(args.coreos_overlay + "/../").resolve()) + "/"

colordifftool = "colordiff"
if args.use_delta:
    colordifftool = "delta"

if not args.no_color and not which(colordifftool):
    raise Exception(colordifftool + " not installed, try to run: sudo dnf install colordiff (for colordiff) or cargo install --git https://github.com/dandavison/delta (for --use-delta)")

if not args.no_color:
    if args.use_delta:
        from sh import delta as colordiff
        colordiff = colordiff.bake("--theme=none", "--color-only", "--paging=never")
    else:
        from sh import colordiff

warnings = []

repo_map = {"coreos-init": "init", "cros-devutils": "dev-util", "gmerge": "dev-util",
            "fero-client": "fero", "actool": "spec"}


def display_difference(from_theirs, to_ours, name, recurse=False):
    from_to = from_theirs + ".." + to_ours
    to_from = to_ours + ".." + from_theirs
    diff = git.diff(from_to, "--", ".", ":!.github", _bg=False, _decode_errors="replace")
    commits_we_have = git.log("--no-merges", from_to, "--", ".", ":!.github")
    commits_they_have = git.log("--no-merges", to_from, "--", ".", ":!.github")
    desc_start = "↓" * 25
    desc_end = "↑" * 25
    desc = "Diff for " + name
    if not args.no_diffs:
        print(desc_start, desc, desc_start + "\n")
        if args.no_color:
            print(diff)
        else:
            print(colordiff(diff, _decode_errors="replace"))
        print("\n" + desc_end, desc, desc_end + "\n")
    if not args.no_commits:
        desc = "Commits for " + name + " in our " + to_ours + " but not in their " + from_theirs
        print(desc_start, desc, desc_start + "\n")
        print(commits_we_have)
        print("\n" + desc_end, desc, desc_end + "\n")
        desc = "Commits for " + name + " in their " + from_theirs + " but not in our " + to_ours
        print(desc_start, desc, desc_start + "\n")
        print(commits_they_have)
        print("\n" + desc_end, desc, desc_end + "\n")
    if recurse:
        theirs = ""
        ours = ""
        repo = ""
        for line in diff.splitlines():
            if line.startswith("diff --git ") and line.endswith("ebuild"):
                if theirs != "" or ours != "":
                    warnings.append("Error: Unexpected variable content (theirs: [expected empty]: " + theirs + ", ours [expected empty]: " + ours + ") for " + repo)
                    theirs = ""
                    ours = ""
                repo = "-".join(line.split("/")[-1].split("-")[:-1])  # Get "some-name" for ".../some-name-9999.ebuild"
                if repo in repo_map:
                    repo = repo_map[repo]
            # @TODO: Add DOCKER_GITCOMMIT, COMMIT_ID, CONTAINERD_COMMIT
            if "CROS_WORKON_COMMIT=" in line:
                if repo == "":
                    raise Exception("No repo seen for: " + line)
                is_theirs = line.startswith("-")
                is_ours = line.startswith("+")
                if not is_theirs and not is_ours:
                    raise Exception("Unexpected line:" + line)
                # Checks that "- ..." is followed by "+ ..."
                if is_theirs:
                    if theirs != "" or ours != "":
                        warnings.append("Error: Unexpected variable content, expected empty (theirs: " + theirs + ", ours: " + ours + ") for " + repo + " in: " + line)
                        theirs = ""
                        ours = ""
                        repo = ""
                        continue
                    theirs = line.split("\"")[1]
                if is_ours:
                    if theirs == "" or ours != "":
                        warnings.append("Error: Unexpected variable content (theirs [expected not empty]: " + theirs + ", ours [expected empty]: " + ours + ") for " + repo + " in: " + line)
                        theirs = ""
                        ours = ""
                        repo = ""
                        continue
                    ours = line.split("\"")[1]
                if theirs != "" and ours != "":
                    os.chdir(base_folder)
                    try:
                        os.chdir(base_folder + repo)
                    except FileNotFoundError:
                        print("Failed to enter repo directory for \"" + repo + "\", trying to clone it")
                        git.clone("git@github.com:flatcar-linux/" + repo + ".git")
                        os.chdir(repo)
                    try:
                        git.fetch("github")
                    except ErrorReturnCode:
                        print("Tried to fetch from github without success, trying to fetch the default remote.")
                        git.fetch()
                    print(desc_start, "Difference for", repo, desc_start + "\n")
                    display_difference(theirs, ours, repo)
                    print("\n" + desc_end, "Difference for", repo, desc_end + "\n")
                    repo = ""
                    theirs = ""
                    ours = ""


os.chdir(args.coreos_overlay)
display_difference(args.THEIRS, args.ours, "coreos-overlay", recurse=True)
if warnings:
    print("Encountered some errors when trying to compare recursively, probably due to deleted files:")
    print("\n".join(warnings))
    print()
print("Done. Displayed all differences.")
