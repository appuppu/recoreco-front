#!/usr/bin/env python3
import re
import secrets

# Read the project file
project_path = '/Users/fukushimatakumi/develop/sugarbeat/sugarbeat-front/SugarBeat.xcodeproj/project.pbxproj'
with open(project_path, 'r') as f:
    content = f.read()

# Generate unique IDs for the new file
build_file_id = secrets.token_hex(12)
file_ref_id = secrets.token_hex(12)

print(f"Generated build_file_id: {build_file_id}")
print(f"Generated file_ref_id: {file_ref_id}")

# 1. Add to PBXBuildFile section
build_file_section = re.search(r'(/\* Begin PBXBuildFile section \*/)', content)
if build_file_section:
    insert_pos = build_file_section.end()
    new_build_file = f"\n\t\t{build_file_id} /* MusicPermissionView.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {file_ref_id} /* MusicPermissionView.swift */; }};"
    content = content[:insert_pos] + new_build_file + content[insert_pos:]
    print("Added to PBXBuildFile section")

# 2. Add to PBXFileReference section
file_ref_section = re.search(r'(/\* Begin PBXFileReference section \*/)', content)
if file_ref_section:
    insert_pos = file_ref_section.end()
    new_file_ref = f"\n\t\t{file_ref_id} /* MusicPermissionView.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = MusicPermissionView.swift; sourceTree = \"<group>\"; }};"
    content = content[:insert_pos] + new_file_ref + content[insert_pos:]
    print("Added to PBXFileReference section")

# 3. Add to Views group (find the Views group and add the file reference)
views_group_pattern = r'(\/\* Views \*\/ = \{[^}]*children = \()'
views_group_match = re.search(views_group_pattern, content)
if views_group_match:
    insert_pos = views_group_match.end()
    new_file_in_group = f"\n\t\t\t\t{file_ref_id} /* MusicPermissionView.swift */,"
    content = content[:insert_pos] + new_file_in_group + content[insert_pos:]
    print("Added to Views group")

# 4. Add to Sources build phase
sources_pattern = r'(/\* Begin PBXSourcesBuildPhase section \*/.*?files = \()'
sources_match = re.search(sources_pattern, content, re.DOTALL)
if sources_match:
    insert_pos = sources_match.end()
    new_source = f"\n\t\t\t\t{build_file_id} /* MusicPermissionView.swift in Sources */,"
    content = content[:insert_pos] + new_source + content[insert_pos:]
    print("Added to PBXSourcesBuildPhase")

# Write back
with open(project_path, 'w') as f:
    f.write(content)

print("Successfully added MusicPermissionView.swift to Xcode project")
