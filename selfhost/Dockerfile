FROM node:22-alpine
WORKDIR /app
COPY server.mjs worker.mjs schema.sql migrate_v21.sql ./
ENV PORT=8787 DATA_DIR=/data NODE_ENV=production
VOLUME /data
EXPOSE 8787
HEALTHCHECK CMD wget -qO- http://localhost:8787/health || exit 1
CMD ["node", "--experimental-sqlite", "--no-warnings", "server.mjs"]
