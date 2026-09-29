# Ma Friends backend. No npm install step: the service uses only Node's
# built-in modules, so the image is the runtime plus a few source files.
FROM node:24-alpine

# node:sqlite still prints an ExperimentalWarning on every start, hence NODE_OPTIONS.
ENV NODE_ENV=production \
    PORT=8095 \
    BASE_PATH=/ma/api \
    DATA_DIR=/data \
    NODE_OPTIONS=--disable-warning=ExperimentalWarning

WORKDIR /app
COPY package.json ./
COPY src ./src

# The stock "node" user (uid 1000) owns only the data directory.
RUN mkdir -p /data && chown node:node /data
USER node

VOLUME ["/data"]
EXPOSE 8095

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:'+(process.env.PORT||8095)+(process.env.BASE_PATH||'/ma/api')+'/health').then(r=>process.exit(r.ok?0:1),()=>process.exit(1))"

# exec form, so SIGTERM from `docker stop` reaches node directly.
CMD ["node", "src/server.js"]
