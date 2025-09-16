FROM ghcr.io/getzola/zola:v0.19.2 AS zola
WORKDIR /app
COPY . .
RUN ["zola", "build"]

FROM nginx:alpine-slim
COPY --from=zola /app/public /usr/share/nginx/html
