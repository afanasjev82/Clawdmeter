# Clawdmeter BLE daemon — polls the Claude API and pushes usage to the device
# over Bluetooth LE. Runs on a Linux host only (needs host BlueZ via D-Bus).
FROM python:3.12-slim

WORKDIR /app

COPY requirements-docker.txt ./
RUN pip install --no-cache-dir -r requirements-docker.txt

COPY claude_usage_daemon.py token_refresher.py ./

ENV PYTHONUNBUFFERED=1

# Default command runs the daemon; the token-refresher service overrides it.
CMD ["python", "claude_usage_daemon.py"]
