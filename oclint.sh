#!/bin/bash
set -e

# GITHUB_TOKEN is a GitHub private access token configured for repo:status scope
# DROPBOX_TOKEN is an access token for the Dropbox API

OCLINT=oclint
BRANCH=${BRANCH:=develop}

status () {
  if [ "$SHIPPABLE" = "true" ]; then
    if [ "$IS_PULL_REQUEST" = "true" ]; then
      # Limit the description to 100 characters even though GitHub supports up to 140 characters
      DESCRIPTION=`echo $2 | cut -b -100`
      DATA="{ \"state\": \"$1\", \"target_url\": \"$BUILD_URL\", \"description\": \"$DESCRIPTION\", \"context\": \"oclint\"}"
      GITHUB_API="https://api.github.com/repos/$REPO_FULL_NAME/statuses/$COMMIT"
      curl -H "Content-Type: application/json" \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "User-Agent: bangolufsen/oclint" \
        -X POST -d "$DATA" $GITHUB_API 1>/dev/null 2>&1
    fi

    # Only update coverage badge if we are analyzing all files
    if [ "$FILES" = "." ] && [ "$1" != "pending" ]; then
      BADGE_COLOR=red
      if [ $ERRORS -eq 0 ]; then
        BADGE_COLOR=yellow
        if [ $WARNINGS -eq 0 ]; then
          BADGE_COLOR=brightgreen
        fi
      fi

      BADGE_TEXT=$BUGS"_bug"`test $BUGS -eq 1 || echo s`
      wget -O /tmp/oclint_${REPO_NAME}_${BRANCH}.svg https://img.shields.io/badge/oclint-$BADGE_TEXT-$BADGE_COLOR.svg 1>/dev/null 2>&1
      curl -X POST "https://api-content.dropbox.com/2/files/upload" \
        -H "Authorization: Bearer $DROPBOX_TOKEN" \
        -H "Content-Type: application/octet-stream" \
        -H "Dropbox-API-Arg: {\"path\": \"/oclint_${REPO_NAME}_${BRANCH}.svg\", \"mode\": \"overwrite\"}" \
        --data-binary @/tmp/oclint_${REPO_NAME}_${BRANCH}.svg 1>/dev/null 2>&1
    fi
  fi

  echo $2
}

ARGS=("$@")
FILES=${ARGS[${#ARGS[@]}-1]}
unset "ARGS[${#ARGS[@]}-1]"

if [ "$FILES" = "diff" ]; then
  FILES=`git diff --name-only --diff-filter ACMRTUXB origin/$BRANCH | grep -e '\.c$' -e '\.cc$' -e '\cpp$' -e '\.cxx$' | xargs`
elif [ "$FILES" = "." ]; then
  OCLINT=oclint-json-compilation-database
fi

status "pending" "Running $OCLINT with args ${ARGS[*]} $FILES"

ERRORS=0
WARNINGS=0

if [ "$FILES" != "" ]; then
  LOG=/tmp/oclint.log
  $OCLINT ${ARGS[*]} $FILES 2>&1 | tee $LOG

  SUMMARY=`grep "Summary:" $LOG`
  ERRORS=`echo $SUMMARY | cut -d ' ' -f4 | cut -d '=' -f2`
  WARNINGS=`echo $SUMMARY | cut -d ' ' -f5 | cut -d '=' -f2`
fi

DESCRIPTION="Found $ERRORS error`test $ERRORS -eq 1 || echo s` and $WARNINGS warning`test $WARNINGS -eq 1 || echo s`"
BUGS=$(($ERRORS + $WARNINGS))

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
  status "success" "$DESCRIPTION"
else
  status "failure" "$DESCRIPTION"
fi
