FROM docker/sandbox-templates:claude-code
USER root
RUN npm install -g http-server@14 html-validate@8
# The fixer can push, so it gets no privilege escalation on top: drop the template's passwordless
# sudo grant and the sudo/docker group memberships. sudoers.d/proxyconfig stays (env_keep only).
RUN rm -f /etc/sudoers.d/agent && gpasswd -d agent sudo && gpasswd -d agent docker
# No telemetry or error reporting: the runner's deny-by-default policy blocks it (see kits/mobyreviewer).
ENV CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
USER agent
ENTRYPOINT ["claude", "--dangerously-skip-permissions"]
CMD []
