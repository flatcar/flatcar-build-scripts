#!/usr/bin/env python3

from sh import which, grep, cut, mktemp, ErrorReturnCode  # Requires "sh": sudo dnf install python3-sh
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
parser.add_argument("--no-prs", dest="no_prs", action="store_true", help="Don't show PR links for merge commits "
    "(ignoring cherry picks without a merge commit as cherry-pick-for can do)")
parser.add_argument("--diff-style", choices=["standard", "word-diff", "icdiff", "colordiff", "delta"],
                    help="Instead of standard git diff, use either git --word-diff, git icdiff, or pipe the existing diff through colordiff or delta")
parser.set_defaults(ours="HEAD", coreos_overlay=".", no_color=False, no_commits=False, no_diffs=False)
args = parser.parse_args()

base_folder = str(Path(args.coreos_overlay + "/../").resolve()) + "/"

if args.diff_style == "colordiff":
    if not which("colordiff"):
        raise Exception("colordiff not installed, try to run: sudo dnf install colordiff")
    from sh import colordiff
elif args.diff_style == "delta":
    if not which("delta"):
        raise Exception("delta not installed, try to run: cargo install --git https://github.com/dandavison/delta")
    from sh import delta
    colordiff = delta.bake("--theme=none", "--color-only", "--paging=never")

warnings = []

repo_map = {"coreos-init": "init", "cros-devutils": "flatcar-dev-util", "gmerge": "flatcar-dev-util",
            "fero-client": "fero", "actool": "spec"}


def commits_to_pick(src="src", dst="dst"):
    # Shows which commits in src can be picked from src to dst.
    # The output is in the format of git log dst..src but excluding
    # changes to .github and commits that are cherry-picked already.
    # The function is equivalent to these two commands but with error checking:
    # $ git cherry dst src | grep ^+ | cut -d " " -f 2 > tmp_outfile
    # $ git log --no-merges --cherry-pick --format=%H dst..src -- . :!.github | grep -F -x -f tmp_outfile | xargs git show -s
    # In our case --cherry-pick doesn't actually filter out we want to filter out
    # (maybe a Flatcar branch strangeness), so we need to postprocess with git cherry.
    tmp_outfile = str(mktemp("-u")).split("\n")[0]
    commits_src_has_with_cherry = git.log("--no-merges", "--cherry-pick", # set --cherry-pick just in case it will filter out something already
        "--format=%H", dst + ".." + src , "--", ".", ":!.github")
    _commits_src_has_without_cherry = cut(grep(git.cherry(dst, src, _bg=False),
                                               "^+", _ok_code=[1, 0]),
                                          "-d", " ", "-f", "2", _out=tmp_outfile)
    commits_src_has_filtered = str(grep(commits_src_has_with_cherry,
                                        "-F", "-x", "-f", tmp_outfile,
                                        _ok_code=[1, 0])).strip().split("\n")
    commits_src_has_filtered = [commit for commit in commits_src_has_filtered if commit != ""]
    if len(commits_src_has_filtered) > 0:
        git_log = git.show("-s", *commits_src_has_filtered)
    else:
        git_log = ""
    os.remove(tmp_outfile)
    return git_log

def pull_requests_for_merge_commits(src="src", dst="dst", repo="repo"):
    # Prints links for GitHub PRs from merge commits.
    # It uses merge commits which means that we don't find the PRs for cherry picks unless they have a merge commit
    # as the cherry-pick-for script can do.
    # The git log format is "subject#body" being "Merge pull request #NUMBER from BRANCH#PR_TITLE".
    merge_commits = str(git.log("--merges", "--format=%s#%b", dst + ".." + src))
    filtered = [line for line in merge_commits.split("\n") if "Merge pull request" in line and line.count("#") >= 2]
    # Won't panic because we ensured above that two # characters exist
    pr_and_titles = [(line.split("#")[1].split(" ")[0], "#".join(line.split("#")[2:])) for line in filtered]
    # TODO: find the correct upstream GitHub organization (from branch?) if it isn't kinvolk but systemd or coreos
    # Ignores PRs that tell that they only change the .github folder by having a title starting with ".github"
    links = [title + ": https://github.com/kinvolk/" + repo + "/pull/" + pr for (pr, title) in pr_and_titles if not title.startswith(".github")]
    return "\n".join(links)

def display_difference(from_theirs, to_ours, name, recurse=False):
    # That means, show what "our" branch adds to "their" branch
    diff_args = [from_theirs + ".." + to_ours, "--", ".", ":!.github"]
    diff = git.diff(*diff_args, _bg=False, _decode_errors="replace")
    desc_start = "↓" * 25
    desc_end = "↑" * 25
    desc = "Diff for " + name
    if not args.no_diffs:
        print(desc_start, desc, desc_start + "\n")
        if args.diff_style == "icdiff":
            print(git.difftool("-y", "-x", "icdiff --is-git-diff --cols=160", *diff_args, _bg=False, _decode_errors="replace"))
        elif args.diff_style == "word-diff":
            print(git.diff("--word-diff", "--no-color" if args.no_color else "--color", *diff_args, _bg=False, _decode_errors="replace"))
        elif args.no_color:
            print(diff)
        elif args.diff_style == "colordiff" or args.diff_style == "delta":
            print(colordiff(diff, _decode_errors="replace"))
        else:
            print(git.diff("--color", *diff_args, _bg=False, _decode_errors="replace"))
        print("\n" + desc_end, desc, desc_end + "\n")
    if not args.no_commits:
        # Branch "our" is the checked out branch and "git diff" shows what "our" branch has that "their" branch doesn't.
        # Converting the diff to "our" commits to pick for "their" branch) means setting "src" as "our".
        commits_we_have = commits_to_pick(src=to_ours, dst=from_theirs)
        commits_they_have = commits_to_pick(src=from_theirs, dst=to_ours)
        desc = "Commits for " + name + " in our " + to_ours + " but not in their " + from_theirs
        print(desc_start, desc, desc_start + "\n")
        print(commits_we_have)
        print("\n" + desc_end, desc, desc_end + "\n")
        desc = "Commits for " + name + " in their " + from_theirs + " but not in our " + to_ours
        print(desc_start, desc, desc_start + "\n")
        print(commits_they_have)
        print("\n" + desc_end, desc, desc_end + "\n")
    if not args.no_prs:
        prs_we_have = pull_requests_for_merge_commits(src=to_ours, dst=from_theirs, repo=name)
        prs_they_have = pull_requests_for_merge_commits(src=from_theirs, dst=to_ours, repo=name)
        desc = "PRs (from merge commits) for " + name + " in our " + to_ours + " but not in their " + from_theirs
        print(desc_start, desc, desc_start + "\n")
        print(prs_we_have)
        print("\n" + desc_end, desc, desc_end + "\n")
        desc = "PRs (from merge commits) for " + name + " in their " + from_theirs + " but not in our " + to_ours
        print(desc_start, desc, desc_start + "\n")
        print(prs_they_have)
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
                        git.clone("git@github.com:kinvolk/" + repo + ".git")
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
display_difference(args.THEIRS, args.ours, os.path.basename(os.path.abspath(".")), recurse=True)
if warnings:
    print("Encountered some errors when trying to compare recursively, probably due to deleted files:")
    print("\n".join(warnings))
    print()
print("Done. Displayed all differences.")
