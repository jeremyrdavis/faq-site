FROM docker/sandbox-templates:claude-code
USER agent
ENTRYPOINT ["claude", "--dangerously-skip-permissions"]
CMD []
