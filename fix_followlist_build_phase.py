#!/usr/bin/env python3
import re
import sys

# Read the project file
project_path = '/Users/fukushimatakumi/develop/sugarbeat/sugarbeat-front/SugarBeat.xcodeproj/project.pbxproj'
with open(project_path, 'r') as f:
    content = f.read()

# Find the file reference ID for FollowListView.swift
file_ref_match = re.search(r'([A-F0-9]{24}) /\* FollowListView\.swift \*/', content)
if not file_ref_match:
    print("ERROR: Could not find FollowListView.swift file reference")
    sys.exit(1)

file_ref_id = file_ref_match.group(1)
print(f"Found file reference ID: {file_ref_id}")

# Find the build file ID for FollowListView.swift
build_file_pattern = r'([A-F0-9]{24}) /\* FollowListView\.swift in (?:Sources|Resources) \*/ = \{isa = PBXBuildFile; fileRef = ' + file_ref_id
build_file_match = re.search(build_file_pattern, content)
if not build_file_match:
    print("ERROR: Could not find FollowListView.swift build file")
    sys.exit(1)

build_file_id = build_file_match.group(1)
print(f"Found build file ID: {build_file_id}")

# Check if it's in Copy Bundle Resources and remove it
resources_pattern = r'(/\* Begin PBXResourcesBuildPhase section \*/.*?files = \()(.*?)(\);.*?/\* End PBXResourcesBuildPhase section \*/)'
resources_match = re.search(resources_pattern, content, re.DOTALL)
if resources_match:
    resources_files = resources_match.group(2)
    if build_file_id in resources_files:
        print("Found FollowListView.swift in PBXResourcesBuildPhase, removing...")
        # Remove the line with this build file ID
        new_resources_files = re.sub(
            r'\s*' + build_file_id + r' /\* FollowListView\.swift in Resources \*/,?\n?',
            '',
            resources_files
        )
        content = content[:resources_match.start(2)] + new_resources_files + content[resources_match.end(2):]
        print("Removed from PBXResourcesBuildPhase")

# Now check if it's in Sources build phase
sources_pattern = r'(/\* Begin PBXSourcesBuildPhase section \*/.*?files = \()(.*?)(\);.*?/\* End PBXSourcesBuildPhase section \*/)'
sources_match = re.search(sources_pattern, content, re.DOTALL)
if sources_match:
    sources_files = sources_match.group(2)
    if build_file_id not in sources_files:
        print("FollowListView.swift not in PBXSourcesBuildPhase, adding...")
        # Add it to sources
        # Find the last file in the sources list
        lines = sources_files.split('\n')
        # Insert before the closing parenthesis
        insert_line = f"\t\t\t\t{build_file_id} /* FollowListView.swift in Sources */,"
        # Find a good place to insert (after other .swift files)
        inserted = False
        new_lines = []
        for line in lines:
            new_lines.append(line)
            if '.swift in Sources' in line and not inserted:
                # Keep adding lines until we find the right place
                pass
        # Just append at the end before closing
        if lines[-1].strip() == '':
            new_lines.insert(-1, insert_line)
        else:
            new_lines.append(insert_line)

        new_sources_files = '\n'.join(new_lines)
        content = content[:sources_match.start(2)] + new_sources_files + content[sources_match.end(2):]
        print("Added to PBXSourcesBuildPhase")
    else:
        print("FollowListView.swift already in PBXSourcesBuildPhase")

# Also need to update the PBXBuildFile entry to say "Sources" instead of "Resources"
# Find the build file entry
build_file_entry_pattern = r'(' + build_file_id + r' /\* FollowListView\.swift in )Resources( \*/ = \{isa = PBXBuildFile; fileRef = ' + file_ref_id + r')'
build_file_entry_match = re.search(build_file_entry_pattern, content)
if build_file_entry_match:
    print("Updating PBXBuildFile entry from Resources to Sources...")
    content = re.sub(build_file_entry_pattern, r'\1Sources\2', content)
    print("Updated PBXBuildFile entry")

# Write back
with open(project_path, 'w') as f:
    f.write(content)

print("Successfully fixed FollowListView.swift build phase")
