FROM docker/sandbox-templates:claude-code
USER root
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright
RUN npm install -g playwright@1 && npx playwright install --with-deps chromium
COPY render.sh /usr/local/bin/render.sh
RUN chmod 0755 /usr/local/bin/render.sh
# The reviewer gets no privilege escalation: drop the template's passwordless sudo
# grant and the sudo/docker group memberships. sudoers.d/proxyconfig stays (env_keep only).
RUN rm -f /etc/sudoers.d/agent && gpasswd -d agent sudo && gpasswd -d agent docker
USER agent
ENTRYPOINT ["claude", "--dangerously-skip-permissions"]
CMD []
