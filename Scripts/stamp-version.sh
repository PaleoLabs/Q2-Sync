#!/bin/zsh
#
#  stamp-version.sh
#  Q2-Sync › Scripts
#
#  PURPOSE
#  Build phase: writes the build number into the built app's Info.plist so
#  About Q2 Sync can tell one build from another without anyone editing it.
#    CFBundleVersion       = git commit count (or "0" without git)
#    Q2SyncBuildCommit     = short commit hash, "-dirty" if uncommitted
#                            changes exist (or "unknown" without git)
#  The marketing version (MARKETING_VERSION in the project) stays manual.
#
set -u
PLIST="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"
[[ -f "$PLIST" ]] || exit 0
cd "${SRCROOT}"

count="0"; commit="unknown"
if git rev-parse --git-dir >/dev/null 2>&1; then
  count=$(git rev-list --count HEAD 2>/dev/null || echo 0)
  commit=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)
  [[ -n "$(git status --porcelain 2>/dev/null)" ]] && commit="${commit}-dirty"
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $count" "$PLIST" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $count" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :Q2SyncBuildCommit $commit" "$PLIST" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :Q2SyncBuildCommit string $commit" "$PLIST"
touch "${DERIVED_FILE_DIR}/stamp-version.done"
