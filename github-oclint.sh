#!/bin/bash
set -e

# GITHUB_TOKEN is a GitHub private access token configured for repo:status scope
# DROPBOX_TOKEN is an access token for the Dropbox API

OCLINT=oclint
BRANCH=${BRANCH:=master}

if [ "$GITHUB_ACTIONS" = "true" ]; then
  REPO_NAME=$(basename "$GITHUB_REPOSITORY")
  REPO_FULL_NAME=$GITHUB_REPOSITORY
  if [ "$(echo "$GITHUB_REF" | cut -d '/' -f4)" = "merge" ]; then
    PULL_REQUEST=$(echo "$GITHUB_REF" | cut -d '/' -f3)
  fi
fi

status () {
  if [ "$SHIPPABLE" = "true" ] || [ "$GITHUB_ACTIONS" = "true" ]; then
    if [ "$PULL_REQUEST" != "" ]; then
      DESCRIPTION=$(echo "$2" | cut -b -100)
      DATA="{ \"state\": \"$1\", \"description\": \"$DESCRIPTION\", \"context\": \"github / oclint\"}"
      PULL_REQUEST_STATUS=$(curl -s -H "Content-Type: application/json" -H "Authorization: token $GITHUB_TOKEN" -H "User-Agent: $REPO_FULL_NAME" -X GET "https://api.github.com/repos/$REPO_FULL_NAME/pulls/$PULL_REQUEST")
      STATUSES_URL=$(echo "$PULL_REQUEST_STATUS" | jq -r '.statuses_url')
      curl -H "Content-Type: application/json" -H "Authorization: token $GITHUB_TOKEN" -H "User-Agent: $REPO_FULL_NAME" -X POST -d "$DATA" "$STATUSES_URL" 1>/dev/null
    fi

    if [ "$FILES" = "." ] && [ "$1" != "pending" ]; then
      BADGE_COLOR=red
      if [ "$P1" -eq 0 ]; then
        BADGE_COLOR=yellow
        if [ "$P2" -eq 0 ] && [ "$P3" -eq 0 ]; then
          BADGE_COLOR=brightgreen
        fi
      fi

      BADGE_TEXT=$BUGS"_bug"$(test "$BUGS" -eq 1 || echo s)
      wget -O /tmp/oclint_"${REPO_NAME}"_"${BRANCH}".svg https://img.shields.io/badge/oclint-"$BADGE_TEXT"-"$BADGE_COLOR".svg 1>/dev/null 2>&1
      curl -X POST "https://api-content.dropbox.com/2/files/upload" \
        -H "Authorization: Bearer $DROPBOX_TOKEN" \
        -H "Content-Type: application/octet-stream" \
        -H "Dropbox-API-Arg: {\"path\": \"/oclint_${REPO_NAME}_${BRANCH}.svg\", \"mode\": \"overwrite\"}" \
        --data-binary @/tmp/oclint_"${REPO_NAME}"_"${BRANCH}".svg 1>/dev/null 2>&1
    fi
  fi

  echo "$2"
}

ARGS=("$@")
FILES=${ARGS[${#ARGS[@]}-1]}
unset "ARGS[${#ARGS[@]}-1]"

if [ "$FILES" = "diff" ]; then
  FILES=$(git diff --name-only --diff-filter ACMRTUXB $BRANCH | grep -e '\.c$' -e '\.cc$' -e '\cpp$' -e '\.cxx$' | xargs)
elif [ "$FILES" = "." ]; then
  OCLINT=oclint-json-compilation-database
fi

P1=0
P2=0
P3=0

if [ "$FILES" != "" ]; then
  status "pending" "Running $OCLINT with args ${ARGS[*]} $FILES"
  "$OCLINT" "${ARGS[*]}" $FILES 2>&1 | tee /tmp/oclint.log

  SUMMARY=$(grep "Summary:" /tmp/oclint.log)
  P1=$(echo "$SUMMARY" | cut -d ' ' -f4 | cut -d '=' -f2)
  P2=$(echo "$SUMMARY" | cut -d ' ' -f5 | cut -d '=' -f2)
  P3=$(echo "$SUMMARY" | cut -d ' ' -f6 | cut -d '=' -f2)
fi

BUGS=$((P1 + P2 + P3))
DESCRIPTION="Found $P1 P1, $P2 P2 and $P3 P3 violations"

if [ "$BUGS" -eq 0 ]; then
  status "success" "$DESCRIPTION"
else
  status "failure" "$DESCRIPTION"
fi
