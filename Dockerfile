FROM node:20-alpine

# Set working directory
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --omit=dev

# Copy source code
COPY src/ ./src/

# Create non-root user
RUN addgroup -g 1001 -S nodejs && \
    adduser -S service -u 1001 -G nodejs && \
    chown -R service:nodejs /app && \
    chgrp -R 0 /app && chmod -R g=u /app

USER 1001

# Expose port
ENV NODE_ENV=production PORT=8000
EXPOSE $PORT

# Start application
CMD ["node", "src/app.js"]
