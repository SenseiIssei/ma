# Compile sandbox for the daily lessons: g++ 14 with the sanitizers, Node to
# answer the Ma server. No network at runtime (internal Docker network), the
# root filesystem is read-only and only /tmp is writable, see the compose file.
FROM node:24-trixie-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends g++ libc6-dev \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY runner.js ./
RUN printf '{"type":"module"}\n' > package.json

USER node
EXPOSE 8096
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:8096/health').then(r=>process.exit(r.ok?0:1),()=>process.exit(1))"
CMD ["node", "runner.js"]
