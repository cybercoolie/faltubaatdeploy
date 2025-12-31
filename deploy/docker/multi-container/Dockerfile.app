FROM node:20-slim

# Set environment variables
ENV NODE_ENV=production

# Install build dependencies for native modules (bcrypt, better-sqlite3) and AWS CLI
RUN apt-get update && apt-get install -y \
    python3 \
    build-essential \
    openssl \
    curl \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Install AWS CLI for S3 sync (optional feature)
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" \
    && unzip awscliv2.zip \
    && ./aws/install \
    && rm -rf awscliv2.zip aws

# Create app directory
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production

# Copy application code
COPY db.js ./
COPY server-https.js ./
COPY public/ ./public/

# Copy S3 sync script
COPY deploy/docker/multi-container/s3-db-sync.sh /app/s3-db-sync.sh
RUN chmod +x /app/s3-db-sync.sh

# Generate self-signed certificates for HTTPS
RUN openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -days 365 -nodes \
    -subj "/C=US/ST=State/L=City/O=Organization/CN=localhost"

# Create data directory for SQLite
RUN mkdir -p /app/data && chmod 755 /app/data

# Initialize database
RUN npm run init-db 2>/dev/null || node -e "require('./db').initDatabase()"

# Expose ports
EXPOSE 3000 3443

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD node -e "require('http').get('http://localhost:3000/health', (r) => process.exit(r.statusCode === 200 ? 0 : 1))" || exit 1

# Start script that handles S3 sync
COPY deploy/docker/multi-container/start-app.sh /start-app.sh
RUN chmod +x /start-app.sh

CMD ["/start-app.sh"]
