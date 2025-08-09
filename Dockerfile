# Dockerfile for NeoVarAI (varfish-server)
# Use the official VarFish server image as base
FROM ghcr.io/varfish-org/varfish-server:main

# Set Django production settings and correct service hostnames/ports
ENV DJANGO_SETTINGS_MODULE=config.settings.production \
    WAIT_HOSTS=dpg-d2b1cvre5dus73c4nqjg-a:5432,red-d2b3hq49c44c7388uqlg:6379 \
    CACHE_URL=redis://red-d2b3hq49c44c7388uqlg:6379/0 \
    CELERY_BROKER_URL=redis://red-d2b3hq49c44c7388uqlg:6379/0

# Expose the port Render will bind to
EXPOSE 8080

# Copy a lightweight entrypoint that runs migrations and starts gunicorn
COPY render/entrypoint.sh /usr/src/app/entrypoint.sh
RUN chmod +x /usr/src/app/entrypoint.sh

# Start the application via gunicorn after migrations/static collection
CMD ["/usr/src/app/entrypoint.sh"]
