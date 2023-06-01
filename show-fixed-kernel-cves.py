#!/usr/bin/env python3

# Helper to show which Linux kernel CVEs got fixed in the update from
# FROM_VERSION to TO_VERSION.
# Usage: ./show-fixed-kernel-cves.py -f 5.15.37 -t 5.15.43

# Unfortunately, the data in https://github.com/CVEProject/cvelist is almost
# useless because the version information often doesn't tell if the version
# fixed a CVE or if the version is affected by a CVE and which other versions
# are affected or not.
# Luckily in https://github.com/nluedtke/linux_kernel_cves there are 3 JSON
# databases which get maintained to track what CVEs got fixed where.
# 1) kernel_cves.json is a format that doesn't cover backports:
#    "affected_versions": "v3.6-rc1 to v5.17-rc2"
#    "last_affected_version": "5.16.4"
# 2) stream_fixes.json is a format that covers backports:
#    a list of CVEs having entries like "5.15" with "fixed_version": "5.15.19"
#    (for each CVE and each fixed_version of the CVE, include
#    the CVE if FROM_VERSION < fixed_version >= TO_VERSION)
# 3) stream_data.json is a format that also covers backports:
#    for each stream there is a list of releases and which CVEs they fixed
#    (for each release, include the list of fixed CVEs if
#    FROM_VERSION < release <= TO_VERSION)

# Using the stream_data.json format seems to be best for our purpose of and is
# also what can be found under https://www.linuxkernelcves.com/streams/5.15

import json
from packaging import version
from optparse import OptionParser
import urllib.request

def print_fixed_linux_cves(from_version_str, to_version_str):
  stream_data_url = "https://raw.githubusercontent.com/nluedtke/linux_kernel_cves/master/data/stream_data.json"
  payload = urllib.request.urlopen(stream_data_url).read()
  streams = json.loads(payload)
  from_version=version.Version(from_version_str)
  to_version=version.Version(to_version_str)
  cvelist = []
  links = []
  for stream, releases in streams.items():
    for release, cves in releases.items():
      if release != "outstanding" and from_version < version.Version(release) <= to_version:
        cvelist += cves.keys()
  for cve in sorted(cvelist):
    links += [f"[{cve}](https://nvd.nist.gov/vuln/detail/{cve})"]
  print(", ".join(links))

parser = OptionParser()
parser.add_option("-f", "--from_version", dest="from_version", default="")
parser.add_option("-t", "--to_version", dest="to_version", default="")
(options, args) = parser.parse_args()
if not options.from_version:
  parser.error("from_version not given")
if not options.to_version:
  parser.error("to_version not given")

print_fixed_linux_cves(options.from_version, options.to_version)
