#!/usr/bin/env bash
set -euo pipefail

project_id=1833973
curseforge_url=https://wow.curseforge.com
forever_version_type=88568
status_context="CurseForge/$RELEASE_TAG"
status_endpoint="repos/$GITHUB_REPOSITORY/statuses/$RELEASE_COMMIT"

# A retry after a confirmed upload should not create another CurseForge file.
receipt=$(gh api --paginate "repos/$GITHUB_REPOSITORY/commits/$RELEASE_COMMIT/statuses" \
    --jq ".[] | select(.context == \"$status_context\" and .state == \"success\") | .target_url")
if [[ -n "$receipt" ]]; then
    printf 'Already uploaded to CurseForge: %s\n' "$receipt"
    exit 0
fi
if [[ -z "${CURSEFORGE_API_TOKEN:-}" ]]; then
    echo '::error::Add the CURSEFORGE_API_TOKEN repository secret to enable CurseForge uploads.'
    exit 1
fi

interface=$(sed -n 's/^## Interface: //p' ForeverQuestRep.toc)
if [[ ! "$interface" =~ ^[0-9]{5,6}$ ]]; then
    echo 'Expected one numeric Interface value in ForeverQuestRep.toc.' >&2
    exit 1
fi
printf -v game_version '%d.%d.%d' "$((10#$interface / 10000))" "$((10#$interface / 100 % 100))" "$((10#$interface % 100))"
versions=$(curl --fail --silent --show-error --max-time 30 -H "X-Api-Token: $CURSEFORGE_API_TOKEN" \
    "$curseforge_url/api/game/wow/versions")
version_id=$(jq -er --arg version "$game_version" --argjson flavor "$forever_version_type" \
    '[.[] | select(.gameVersionTypeID == $flavor and .name == $version) | .id] | unique |
    if length == 1 then .[0] else error("Expected one WoW Forever game version matching " + $version) end' <<< "$versions")

archive="QuestRepForecast-${RELEASE_TAG#v}.zip"
gh release download "$RELEASE_TAG" --pattern "$archive" --dir "$RUNNER_TEMP"
printf '%s  %s\n' "$RELEASE_CHECKSUM" "$RUNNER_TEMP/$archive" | sha256sum --check --status
unzip -t "$RUNNER_TEMP/$archive"
metadata=$(jq -cn --arg name "Quest Rep Forecast $RELEASE_TAG" --argjson version "$version_id" \
    --rawfile changelog CHANGELOG.txt '{displayName: $name, gameVersions: [$version], releaseType: "release",
    isMarkedForManualRelease: false, changelog: $changelog, changelogType: "text",
    relations: {projects: [{slug: "questie", type: "requiredDependency"}]}}')

# Do not automatically retry a POST whose response may have been lost after acceptance.
response=$(curl --fail --silent --show-error --max-time 180 -H "X-Api-Token: $CURSEFORGE_API_TOKEN" \
    --form-string "metadata=$metadata" --form "file=@$RUNNER_TEMP/$archive" \
    "$curseforge_url/api/projects/$project_id/upload-file")
file_id=$(jq -er '.id | select(type == "number" and . > 0)' <<< "$response")
file_url="https://www.curseforge.com/wow/addons/quest-rep-forecast/files/$file_id"
printf 'Submitted to CurseForge: %s\n' "$file_url"
gh api --method POST "$status_endpoint" -f state=success -f "context=$status_context" \
    -f 'description=Release file submitted to CurseForge' -f "target_url=$file_url" >/dev/null
