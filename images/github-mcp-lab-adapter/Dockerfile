FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/instrument

WORKDIR /app
COPY sources/awesome-llm-apps/mcp_ai_agents/github_mcp_agent/requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

# This is deliberately a LAB ADAPTER, not an upstream replacement.  It keeps
# the original process-global os.environ writes and sends only synthetic test
# credentials to an in-cluster observer when LAB_GITHUB_SINK_URL is set.
COPY images/github-mcp-lab-adapter/github_agent.py /app/github_agent.py
COPY images/github-mcp-lab-adapter/sitecustomize.py /instrument/sitecustomize.py

RUN useradd --create-home --uid 1000 --shell /usr/sbin/nologin lab \
    && chown -R lab:lab /app /instrument

USER lab
EXPOSE 8501
CMD ["streamlit", "run", "/app/github_agent.py", "--server.address=0.0.0.0", "--server.port=8501", "--server.headless=true", "--server.enableCORS=false", "--server.enableXsrfProtection=false"]
