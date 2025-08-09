# Dockerfile for NeoVarAI (varfish-server)
# Use the official VarFish server image as base
FROM ghcr.io/varfish-org/varfish-server:main

# Set Django production settings
ENV DJANGO_SETTINGS_MODULE=config.settings.production

# Expose the port Render will bind to
EXPOSE 8080

# Copy a lightweight entrypoint that runs migrations and starts gunicorn
COPY render/entrypoint.sh /usr/src/app/entrypoint.sh
RUN chmod +x /usr/src/app/entrypoint.sh

# Start the application via gunicorn after migrations/static collection
CMD ["/usr/src/app/entrypoint.sh"]
