# Squelette à compléter — étape 3.
# Mêmes contraintes que les autres services (multi-stage, non-root, ≤ 200 Mo).

# ---- Stage 1 : build / install des dépendances ----
FROM python:3.12-slim AS build

WORKDIR /app

# TODO : copiez requirements.txt et installez les dépendances dans un venv ou un --user.
# Pourquoi ne PAS faire un simple `pip install` global dans cette stage ?
# (réponse dans RAPPORT.md)

# TODO : copiez le code de l'app.

# ---- Stage 2 : runtime ----
FROM python:3.12-slim AS runtime

# TODO : LABEL org.opencontainers.image.source.

WORKDIR /app

# TODO : copiez depuis `build` le venv et le code, rien de plus.

# TODO : créez l'utilisateur non-root, passez en USER.

ENV PORT=8080 \
    LOG_LEVEL=info \
    PYTHONUNBUFFERED=1

EXPOSE 8080

# TODO : commande de démarrage (uvicorn app.main:app …).
# CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
