FROM ubuntu:24.04

# 1. Set environment variables to bypass interactive prompts
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Kolkata

# 2. Install basic tools and add the NodeSource repository for Node.js 20
RUN apt-get update && apt-get install -y \
    curl \
    ca-certificates \
    gnupg \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list

# 3. Install Node.js, Nginx, build tools, and other dependencies
RUN apt-get update && apt-get install -y \
    tzdata \
    nodejs \
    nginx \
    libnginx-mod-rtmp \
    openssl \
    build-essential \
    python3 \
    sqlite3 \
    libsqlite3-dev \
    && rm -rf /var/lib/apt/lists/*

# This ensures the npm tool itself is not flagged as vulnerable
RUN npm install -g npm@latest

# 4. Configure Timezone
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# 5. Create app directory
WORKDIR /app

# 6. Copy package files and install Node.js dependencies
# Note: Build from project root with: docker build -f docker/single-container/Dockerfile .
COPY package*.json ./

# Install dependencies and automatically fix known vulnerabilities
RUN npm install && npm audit fix --force

# 7. Copy application code
COPY . .

# 8. Generate self-signed certificates
RUN openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -days 365 -nodes \
    -subj "/C=US/ST=State/L=City/O=Organization/CN=localhost"

# 9. Setup data directory for SQLite database (persistent volume)
RUN mkdir -p /app/data && chmod 755 /app/data

# 10. Setup Nginx and HLS directory
COPY nginx.conf /etc/nginx/nginx.conf
RUN mkdir -p /var/www/html/hls && chmod 755 /var/www/html/hls

# 11. Initialize database (will be overwritten if volume is mounted)
RUN npm run init-db

# 12. Install AWS CLI for S3 sync (optional feature)
RUN apt-get update && apt-get install -y \
    unzip \
    && curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" \
    && unzip awscliv2.zip \
    && ./aws/install \
    && rm -rf awscliv2.zip aws \
    && rm -rf /var/lib/apt/lists/*

# 13. Prepare S3 sync script (optional)
COPY deploy/docker/single-container/s3-db-sync.sh /app/s3-db-sync.sh
RUN chmod +x /app/s3-db-sync.sh

# 14. Prepare startup script
COPY deploy/docker/single-container/start-services.sh /start-services.sh
RUN chmod +x /start-services.sh

# Expose ports: 
# 3000 (Node), 3443 (HTTPS), 1935 (RTMP), 8080 (HLS/HTTP)
EXPOSE 3000 3443 1935 8080

# Volume for persistent data (SQLite database)
VOLUME ["/app/data"]

# Start both services via the script
CMD ["/start-services.sh"]
