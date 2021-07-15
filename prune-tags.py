import time
from subprocess import check_output, run


def get_old_tags(day=15):
    """Get ref/tags older than n days"""
    days_ago = time.time() - 60 * 60 * 24 * day
    for tag in tags_date:
        try:
            ref_tag, time_raw, _ = tag.split()
            if float(time_raw) < days_ago:
                yield ref_tag.decode("utf-8")
        except ValueError:
            pass


def delete_tag_chunks(tags, chunk_length=100):
    """The amount of tags to be deleted in chunks"""
    for i in range(0, len(tags), chunk_length):
        yield tags[i:i + chunk_length]


tags_date = check_output("""
    git for-each-ref --sort=creatordate --format '%(refname:short) %(creatordate:raw)' refs/tags | grep -v '^v[0-9]'
    """, shell=True)

tags_date = tags_date.split(b'\n')

add_ref_tag = (
    f":refs/tags/{tag}" for tag in get_old_tags()
)

for chunk in delete_tag_chunks(list(add_ref_tag)):
    run(f"git push origin {' '.join(chunk)}", shell=True)

run("git fetch --prune origin +refs/tags/*:refs/tags/*", shell=True)
