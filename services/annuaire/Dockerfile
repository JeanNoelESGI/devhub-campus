# ---- Stage 1 : build / install des dépendances ----
# Image de base épinglée par tag immuable (digest serait encore mieux en prod).
FROM node:20-alpine AS build

WORKDIR /app

# On copie package.json EN PREMIER pour profiter du cache Docker :
# si le code change mais pas les dépendances, npm ci n'est pas ré-exécuté.
COPY package.json ./
# npm install car pas de package-lock.json dans le squelette du TP.
# En production, on utiliserait npm ci avec un lock file commité.
RUN npm install --omit=dev

# Copie du code source APRÈS les dépendances.
COPY src/ ./src/

# ---- Stage 2 : image runtime minimale ----
FROM node:20-alpine AS runtime

# Label OCI standard — obligatoire (critère de notation).
LABEL org.opencontainers.image.source="https://github.com/JeanNoelESGI/devhub-campus"
LABEL org.opencontainers.image.description="annuaire-service — DevHub Campus"

WORKDIR /app

# On ne copie que ce qui est nécessaire au runtime (pas les devDependencies s'il y en avait).
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/src ./src

# Création d'un utilisateur non-root (UID 1001 = cohérent avec securityContext du chart).
RUN addgroup -S appgroup && adduser -S appuser -G appgroup -u 1001
USER 1001

# Variables d'environnement de runtime — AUCUN secret ici.
ENV PORT=8080 \
    LOG_LEVEL=info \
    NODE_ENV=production

EXPOSE 8080

# Commande de démarrage.
CMD ["node", "src/index.js"]
