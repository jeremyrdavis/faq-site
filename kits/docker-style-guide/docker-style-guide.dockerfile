FROM scratch
COPY guide/STYLE_GUIDE.md guide/tokens.css /usr/share/docker-style-guide/
COPY guide/skill/ /home/agent/.claude/skills/docker-style-guide/
