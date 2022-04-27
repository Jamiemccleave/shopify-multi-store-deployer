FROM alpine:latest

LABEL repository="https://github.com/jamiemccleave/merge"
LABEL homepage="https://github.com/jamiemccleave/merge"
LABEL "com.github.actions.name"="Upmerge"
LABEL "com.github.actions.description"="Automatically merge one branch into another"
LABEL "com.github.actions.icon"="git-merge"
LABEL "com.github.actions.color"="orange"

RUN apk --no-cache add bash curl git git-lfs jq

ADD entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
