FROM --platform=$BUILDPLATFORM ghcr.io/getzola/zola:v0.21.0 AS zola
WORKDIR /app
COPY . .
RUN ["zola", "build"]

FROM nginx:alpine-slim
COPY --from=zola /app/public /usr/share/nginx/html
