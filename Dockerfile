# syntax=docker/dockerfile:1
#
# TaskApp Frontend (React + Vite + TypeScript) — multi-stage image
# Lesson references: slides 18-20 (Containerizing Applications, Multi-Stage Builds)
#
# Stage 1 builds the static SPA with Node. Stage 2 throws Node away entirely and
# ships only the compiled HTML/JS/CSS on a tiny Nginx image. The final image
# contains NO Node, NO source, NO node_modules — just static files + Nginx.

############################
# Stage 1 — build the SPA
############################
FROM node:18-alpine AS builder

WORKDIR /app

# Copy manifests first and install with the lockfile for a reproducible build —
# this layer is cached until dependencies actually change (lesson 02-dockerfile).
COPY package.json package-lock.json ./
RUN npm ci

# Build-time API base URL. With our Nginx reverse proxy the SPA calls the
# same-origin path "/api", which Nginx forwards to the backend container.
# NOTE: Vite inlines VITE_* vars into the bundle at BUILD time, so this is an
# ARG (build-time), not a runtime env var.
ARG VITE_API_URL=/api
ENV VITE_API_URL=${VITE_API_URL}

COPY . .
RUN npm run build          # -> /app/dist

############################
# Stage 2 — serve with Nginx
############################
FROM nginx:alpine AS runtime

# Our SPA + API-proxy server config replaces the stock default site.
COPY docker/nginx.conf /etc/nginx/conf.d/default.conf

# Copy ONLY the build output from the builder stage.
COPY --from=builder /app/dist /usr/share/nginx/html

EXPOSE 80

# Health endpoint defined in docker/nginx.conf (returns 200 "ok").
# Use 127.0.0.1 (not localhost): busybox wget tries IPv6 ::1 first, but nginx
# listens on IPv4 only, so "localhost" yields a false "connection refused".
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD wget -q --spider http://127.0.0.1/healthz || exit 1

# nginx:alpine's default CMD runs nginx in the foreground as PID 1.
