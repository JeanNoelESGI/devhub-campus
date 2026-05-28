# Squelette — étape 3.
# Cible : image FINALE ≤ 50 Mo (Go produit un binaire statique, profitez-en).

# ---- Stage 1 : build du binaire Go ----
FROM golang:1.22-alpine AS build

WORKDIR /src

# TODO : copier go.mod / go.sum et faire `go mod download` AVANT de copier le code.

# TODO : copier le code et compiler.
# Indice : `CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /out/notif ./cmd`

# ---- Stage 2 : runtime minimal ----
# TODO : choisir une image de runtime ULTRA-minimale (scratch ? distroless ? alpine ?)
# Comparez les tailles dans RAPPORT.md. Quel est le compromis pour chaque option ?
FROM gcr.io/distroless/static:nonroot AS runtime

# TODO : LABEL org.opencontainers.image.source.

# TODO : copiez le binaire depuis le stage `build`.

ENV PORT=8080 \
    LOG_LEVEL=info

EXPOSE 8080

# USER nonroot:nonroot     # déjà fourni par l'image distroless
# TODO : ENTRYPOINT.
# ENTRYPOINT ["/notif"]
