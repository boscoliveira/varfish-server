# Dockerfile for NeoVarAI (varfish-server)
# Use the official VarFish server image as base
FROM ghcr.io/varfish-org/varfish-server:main

# Set Django production settings
ENV DJANGO_SETTINGS_MODULE=config.settings.production

# Expose the port Render will bind to
EXPOSE 8080

# Copy entrypoints
COPY render/entrypoint.sh /usr/src/app/entrypoint.sh
COPY render/entrypoint-web.sh /usr/src/app/entrypoint-web.sh
RUN chmod +x /usr/src/app/entrypoint.sh /usr/src/app/entrypoint-web.sh

# Start only the web server here; run migrations separately to avoid long startups
CMD ["/usr/src/app/entrypoint-web.sh"]
