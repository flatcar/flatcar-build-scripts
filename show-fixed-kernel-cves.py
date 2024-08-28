#!/usr/bin/env python3

"""
Helper to show which Linux kernel CVEs got fixed in a given version

```
virtualenv venv
source venv/bin/activate
pip install feedparser
python show-fixed-kernel-cves.py --from_version 6.6.32 --to_version 6.6.44
```
"""
from optparse import OptionParser
import subprocess

import feedparser

class Version:
    """
    Version implement a simple semver version object.
    """
    def __init__(self, v):
        # Clean the 'v' from the version (e.g 'v6.6.44')
        if v.startswith("v"):
            v = v[1:]

        s = v.split(".")
        if len(s) != 3:
            self.major = "-1"
            self.minor = "-1"
            self.patch = "-1"
        else:
            self.major = s[0]
            self.minor = s[1]
            self.patch = s[2]

    def __str__(self):
        return f"{self.major}.{self.minor}.{self.patch}"

    def __eq__(self, v):
        if isinstance(v, Version):
            return (self.major, self.minor, self.patch) == (v.major, v.minor, v.patch)

        return False

    def __lt__(self, v):
        return (self.major, self.minor, self.patch) < (v.major, v.minor, v.patch)

    def __ge__(self, v):
        return not (self < v)

def list_all_tags_for_remote_git_repo(url: str, f: Version, t: Version):
    """
    Given a repository URL, list all tags for that repository
    without cloning it then return the tags between f (from) and t (to) version.

    This function use "git ls-remote", so the
    "git" command line program must be available.
    """
    # Run the 'git' command to fetch and list remote tags
    result = subprocess.run([
        "git", "ls-remote", "--tags", url
    ], stdout=subprocess.PIPE, text=True, check=True)

    # Process the output to extract tag names
    output_lines = result.stdout.splitlines()
    tags = [
        Version(line.split("refs/tags/")[-1]) for line in output_lines
        if "refs/tags/" in line and "^{}" not in line
    ]

    # Assert that the starting and the ending version are
    # in the list of existing tags.
    if f not in tags or t not in tags:
        return []

    return list(filter(lambda v: f < v <= t, tags))

def fixed_linux_cves(f, t):
    """
    fixed_linux_cves return a list of Kernel CVEs
    (in Flatcar changelog format) between two versions.
    """
    tags = list_all_tags_for_remote_git_repo("https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git", f, t)
    links = []
    for tag in tags:
        stream_data_url = f'https://lore.kernel.org/linux-cve-announce/?q=%22fixed+in+{tag}%22&x=A'
        feed = feedparser.parse(stream_data_url)
        for item in feed.entries:
            cve = item.title.split(":")[0]
            if not cve.startswith("CVE"):
                continue
            links += [f"[{cve}](https://nvd.nist.gov/vuln/detail/{cve})"]
    return ", ".join(links)

parser = OptionParser()
parser.add_option("-f", "--from_version", dest="from_version")
parser.add_option("-t", "--to_version", dest="to_version")
(options, args) = parser.parse_args()
if not options.from_version:
    parser.error("from_version not given")
if not options.to_version:
    parser.error("to_version not given")

cves = fixed_linux_cves(Version(options.from_version), Version(options.to_version))
if len(cves) > 0:
    print(f"- Linux ({cves})")
