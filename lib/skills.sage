import io

var skills_content = ""
var skills_count = 0

proc load_skills(dir):
    skills_content = ""
    skills_count = 0
    if not io.exists(dir) or not io.isdir(dir):
        return ""
    let entries = io.listdir(dir)
    var parts = []
    for e in entries:
        if endswith(e, ".md"):
            let path = dir + "/" + e
            let content = io.readfile(path)
            let name = slice(e, 0, len(e) - 3)
            let entry = "===== Skill: " + name + " =====\n" + content
            push(parts, entry)
            skills_count = skills_count + 1
    if len(parts) > 0:
        skills_content = join(parts, "\n\n")
    return skills_content

proc get_skills_content():
    return skills_content

proc get_skills_count():
    return skills_count
