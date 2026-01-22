#!/usr/bin/env python3
import uuid
import re

def generate_uuid():
    """Generate a unique 24-character hex UUID"""
    return uuid.uuid4().hex[:24].upper()

# Define the files to add
files_to_add = [
    # Utils (YouTube support)
    {"path": "SugarBeat/Utils/YouTubeUtils.swift", "group": "Utils", "name": "YouTubeUtils.swift"},
    # Views (YouTube player)
    {"path": "SugarBeat/Views/YouTubePlayerView.swift", "group": "Views", "name": "YouTubePlayerView.swift"},
]

# Generate UUIDs for all files
for file_info in files_to_add:
    file_info['file_ref_uuid'] = generate_uuid()
    file_info['build_file_uuid'] = generate_uuid()

# Read the project.pbxproj file
project_path = '/Users/fukushimatakumi/develop/sugarbeat/sugarbeat-front/SugarBeat.xcodeproj/project.pbxproj'
with open(project_path, 'r') as f:
    content = f.read()

# 1. Add PBXBuildFile entries
build_file_section = []
for file_info in sorted(files_to_add, key=lambda x: x['name']):
    build_file_entry = f"\t\t{file_info['build_file_uuid']} /* {file_info['name']} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_info['file_ref_uuid']} /* {file_info['name']} */; }};"
    build_file_section.append(build_file_entry)

# Insert after the last PBXBuildFile entry
build_file_end_match = re.search(r'(\t\tFAE652FB301C80A01F159386 /\* DiscoveryView\.swift in Sources \*/ = \{isa = PBXBuildFile; fileRef = B9F96BBF7CF4E889C7D2D4B2 /\* DiscoveryView\.swift \*/; \};)', content)
if build_file_end_match:
    insert_pos = build_file_end_match.end()
    build_file_text = '\n' + '\n'.join(build_file_section)
    content = content[:insert_pos] + build_file_text + content[insert_pos:]

# 2. Add PBXFileReference entries
file_ref_section = []
for file_info in sorted(files_to_add, key=lambda x: x['name']):
    file_ref_entry = f"\t\t{file_info['file_ref_uuid']} /* {file_info['name']} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {file_info['name']}; sourceTree = \"<group>\"; }};"
    file_ref_section.append(file_ref_entry)

# Insert before the closing of PBXFileReference section (before FADD45EA)
file_ref_end_match = re.search(r'(\t\tF5701DF1321EE3E818035EE7 /\* BlockedUsersView\.swift \*/ = \{isa = PBXFileReference; lastKnownFileType = sourcecode\.swift; path = BlockedUsersView\.swift; sourceTree = "<group>"; \};)', content)
if file_ref_end_match:
    insert_pos = file_ref_end_match.end()
    file_ref_text = '\n' + '\n'.join(file_ref_section)
    content = content[:insert_pos] + file_ref_text + content[insert_pos:]

# 3. Add files to appropriate PBXGroup sections
# For Models group (after User.swift)
models_files = [f for f in files_to_add if f['group'] == 'Models']
models_entries = []
for file_info in sorted(models_files, key=lambda x: x['name']):
    models_entries.append(f"\t\t\t\t{file_info['file_ref_uuid']} /* {file_info['name']} */,")

models_group_match = re.search(r'(\t\t\t\tF3BBF0A127E07FBDE8DB480A /\* User\.swift \*/,)', content)
if models_group_match:
    insert_pos = models_group_match.end()
    models_text = '\n' + '\n'.join(models_entries)
    content = content[:insert_pos] + models_text + content[insert_pos:]

# For Services group (after UnreadPostsManager.swift)
services_files = [f for f in files_to_add if f['group'] == 'Services']
services_entries = []
for file_info in sorted(services_files, key=lambda x: x['name']):
    services_entries.append(f"\t\t\t\t{file_info['file_ref_uuid']} /* {file_info['name']} */,")

services_group_match = re.search(r'(\t\t\t\t7F7F5DCDAD85A75EB1E0E4CB /\* UnreadPostsManager\.swift \*/,)', content)
if services_group_match:
    insert_pos = services_group_match.end()
    services_text = '\n' + '\n'.join(services_entries)
    content = content[:insert_pos] + services_text + content[insert_pos:]

# For Utils group (after EditableImagePicker.swift)
utils_files = [f for f in files_to_add if f['group'] == 'Utils']
utils_entries = []
for file_info in sorted(utils_files, key=lambda x: x['name']):
    utils_entries.append(f"\t\t\t\t{file_info['file_ref_uuid']} /* {file_info['name']} */,")

utils_group_match = re.search(r'(\t\t\t\t3FD08E3ADF25DE60B540F6E5 /\* EditableImagePicker\.swift \*/,)', content)
if utils_group_match:
    insert_pos = utils_group_match.end()
    utils_text = '\n' + '\n'.join(utils_entries)
    content = content[:insert_pos] + utils_text + content[insert_pos:]

# For Views group (after UserSearchView.swift)
views_files = [f for f in files_to_add if f['group'] == 'Views']
views_entries = []
for file_info in sorted(views_files, key=lambda x: x['name']):
    views_entries.append(f"\t\t\t\t{file_info['file_ref_uuid']} /* {file_info['name']} */,")

views_group_match = re.search(r'(\t\t\t\tC2D5F19F4F174EC3996C7A82 /\* UserSearchView\.swift \*/,)', content)
if views_group_match:
    insert_pos = views_group_match.end()
    views_text = '\n' + '\n'.join(views_entries)
    content = content[:insert_pos] + views_text + content[insert_pos:]

# 4. Add to PBXSourcesBuildPhase section
sources_entries = []
for file_info in sorted(files_to_add, key=lambda x: x['name']):
    sources_entries.append(f"\t\t\t\t{file_info['build_file_uuid']} /* {file_info['name']} in Sources */,")

sources_phase_match = re.search(r'(\t\t\t\tFAE652FB301C80A01F159386 /\* DiscoveryView\.swift in Sources \*/,)', content)
if sources_phase_match:
    insert_pos = sources_phase_match.end()
    sources_text = '\n' + '\n'.join(sources_entries)
    content = content[:insert_pos] + sources_text + content[insert_pos:]

# Write the updated content back to the file
with open(project_path, 'w') as f:
    f.write(content)

print("Successfully updated project.pbxproj with the following files:")
for file_info in files_to_add:
    print(f"  - {file_info['path']}")
    print(f"    Build File UUID: {file_info['build_file_uuid']}")
    print(f"    File Ref UUID:   {file_info['file_ref_uuid']}")
