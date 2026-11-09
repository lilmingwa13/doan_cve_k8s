FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app
COPY images/github-credential-sink/app.py /app/app.py

RUN useradd --create-home --uid 10001 --shell /usr/sbin/nologin sink \
    && chown -R sink:sink /app
USER sink

EXPOSE 8080
CMD ["python", "/app/app.py"]
