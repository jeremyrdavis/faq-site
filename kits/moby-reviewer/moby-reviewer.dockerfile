FROM docker/sandbox-templates:claude-code
USER root
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright
RUN npm install -g playwright@1 && npx playwright install --with-deps chromium
COPY render.sh /usr/local/bin/render.sh
RUN chmod 0755 /usr/local/bin/render.sh
USER agent
ENTRYPOINT ["claude", "--dangerously-skip-permissions"]
CMD []
