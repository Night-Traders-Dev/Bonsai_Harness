import io

var skills_content = ""
var skills_count = 0
var skills_meta = []

proc _parse_frontmatter(content):
    let result = {}
    result["name"] = ""
    result["description"] = ""
    result["body"] = content
    result["has_frontmatter"] = false

    if not startswith(content, "---"):
        return result

    let rest = slice(content, 3, len(content))
    let end_idx = indexof(rest, "\n---")
    if end_idx < 0:
        return result

    let fm = slice(rest, 0, end_idx)
    let after = slice(rest, end_idx + 4, len(rest))
    if startswith(after, "\n"):
        after = slice(after, 1, len(after))

    result["has_frontmatter"] = true
    result["body"] = after

    let lines = split(fm, "\n")
    for line in lines:
        let trimmed = strip(line)
        if trimmed == "":
            continue
        let colon = indexof(trimmed, ":")
        if colon < 0:
            continue
        let key = strip(slice(trimmed, 0, colon))
        let value = strip(slice(trimmed, colon + 1, len(trimmed)))
        if key == "name":
            result["name"] = value
        if key == "description":
            result["description"] = value
    return result

proc _collect_md_files(dir, out):
    let entries = io.listdir(dir)
    for e in entries:
        let path = dir + "/" + e
        if io.isdir(path):
            let sub = path + "/SKILL.md"
            if io.exists(sub):
                push(out, sub)
        elif endswith(e, ".md"):
            push(out, path)
    return out

proc load_skills(dir):
    skills_content = ""
    skills_count = 0
    skills_meta = []
    if not io.exists(dir) or not io.isdir(dir):
        return ""

    var files = []
    files = _collect_md_files(dir, files)

    var parts = []
    for path in files:
        let content = io.readfile(path)
        let parsed = _parse_frontmatter(content)

        var name = parsed["name"]
        if name == "":
            let base = path
            let slash = _last_index(base, "/")
            if slash >= 0:
                base = slice(base, slash + 1, len(base))
            if endswith(base, ".md"):
                base = slice(base, 0, len(base) - 3)
            name = base

        let meta = {}
        meta["name"] = name
        meta["description"] = parsed["description"]
        meta["path"] = path
        push(skills_meta, meta)

        var header = "===== Skill: " + name + " ====="
        if parsed["description"] != "":
            header = header + "\n" + parsed["description"]
        let entry = header + "\n" + parsed["body"]
        push(parts, entry)
        skills_count = skills_count + 1

    if len(parts) > 0:
        skills_content = join(parts, "\n\n")
    return skills_content

proc _last_index(s, sub):
    var result = -1
    var i = 0
    let n = len(s)
    while i < n:
        if slice(s, i, i + len(sub)) == sub:
            result = i
        i = i + 1
    return result

proc get_skills_content():
    return skills_content

proc get_skills_count():
    return skills_count

proc get_skills_meta():
    return skills_meta

proc parse_frontmatter(content):
    return _parse_frontmatter(content)
