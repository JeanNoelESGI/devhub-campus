# Stage 1 : build / install des dépendances
FROM python:3.12-slim AS build

WORKDIR /app

# Installer pip et copier requirements.txt
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt --user

# Copier le code source de l'application
COPY app/ ./app/

# Stage 2 : runtime
FROM python:3.12-slim AS runtime

LABEL org.opencontainers.image.source="https://github.com/JeanNoelESGI/devhub-campus"
LABEL org.opencontainers.image.description="planning-service — DevHub Campus"

WORKDIR /app

# Copier les packages python de l'utilisateur installés dans l'étape build
COPY --from=build /root/.local /root/.local
COPY --from=build /app/app ./app

# S'assurer que le PATH inclut les paquets locaux de l'utilisateur
ENV PATH=/root/.local/bin:$PATH \
    PORT=8080 \
    LOG_LEVEL=info \
    PYTHONUNBUFFERED=1

EXPOSE 8080

CMD ["python", "-m", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
