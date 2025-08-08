FROM ghcr.io/varfish-org/varfish-server:main
ENV DJANGO_SETTINGS_MODULE=config.settings.production
CMD ["/usr/local/bin/docker-entrypoint.sh","web"]
