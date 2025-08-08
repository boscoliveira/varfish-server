FROM ghcr.io/varfish-org/varfish-server:main
ENV DJANGO_SETTINGS_MODULE=config.settings.production
EXPOSE 8080
CMD ["/usr/local/bin/docker-entrypoint.sh","web"]
