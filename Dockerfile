FROM node:lts-alpine3.19

# Arguments
ARG APP_HOME=/home/node/app
ARG PLUGINS="" # Comma-separated list of plugin git URLs
ARG USERNAME=""
ARG PASSWORD=""

# Install system dependencies
# Add unzip for extracting the application code
# Keep git for potential use by scripts or future plugin updates
# Add wget to download the zip file
# Add curl for health checks and keep-alive
RUN apk add --no-cache gcompat tini git unzip wget curl

# Create app directory
WORKDIR ${APP_HOME}

# Set NODE_ENV to production and set credentials from ARGs
ENV NODE_ENV=production
ENV USERNAME=${USERNAME}
ENV PASSWORD=${PASSWORD}

# --- BEGIN: Clone SillyTavern Core from GitHub (staging branch) ---
RUN \
  echo "*** Cloning SillyTavern Core from GitHub (staging branch) ***" && \
  # Clone the specific branch into the current directory
  git clone -b staging --depth 1 https://github.com/SillyTavern/SillyTavern.git . && \
  echo "*** Cloning complete. ***"
# --- END: Clone SillyTavern Core ---

# --- BEGIN: Remove root .gitignore if exists ---
RUN \
  echo "*** Attempting to remove root .gitignore if it exists ***" && \
  rm -f .gitignore && \
  echo "*** Root .gitignore removed (if it existed). ***"
# --- END: Remove root .gitignore ---

# Install base SillyTavern dependencies (package*.json should be in the cloned root)
RUN \
  echo "*** Install Base npm packages ***" && \
  if [ -f package.json ]; then \
    # Added --force to potentially overcome file system issues in docker/overlayfs
    npm i --no-audit --no-fund --loglevel=error --no-progress --omit=dev --force && npm cache clean --force; \
  else \
    echo "No package.json found in root, skipping base npm install."; \
  fi

# Go back to the main app directory (redundant but safe)
WORKDIR ${APP_HOME}

# Create config directory. config.yaml will be handled at runtime by ENTRYPOINT
RUN mkdir -p config

# Pre-compile public libraries (build-lib.js should be in the unzipped structure)
RUN \
  echo "*** Run Webpack ***" && \
  # Check if build-lib.js exists before running
  if [ -f "./docker/build-lib.js" ]; then \
    node "./docker/build-lib.js"; \
  elif [ -f "./build-lib.js" ]; then \
    node "./build-lib.js"; \
  else \
    echo "build-lib.js not found, skipping Webpack build."; \
  fi

# Cleanup unnecessary files (like the docker dir if it exists in the zip) and make entrypoint executable
# This block is removed as we no longer use docker-entrypoint.sh
# RUN \
#  echo "*** Cleanup and Permissions ***" && \
#  ...

# Fix potential git safe.directory issues if git commands are run later by scripts
RUN git config --global --add safe.directory "${APP_HOME}"

# Ensure the node user owns the application directory and its contents
RUN chown -R node:node ${APP_HOME}

# No longer download external health.sh
# RUN git clone --depth 1 https://github.com/fuwei99/docker-health.sh.git /tmp/health_repo && \
#    cp /tmp/health_repo/health.sh ${APP_HOME}/health.sh && \
#    rm -rf /tmp/health_repo

# Make the downloaded script executable
# RUN chmod +x ${APP_HOME}/health.sh

# Create a new, self-contained entrypoint script
RUN <<EOF > /usr/local/bin/entrypoint.sh
#!/bin/sh
set -e

CONFIG_FILE="${APP_HOME}/config.yaml"

# Priority 1: Use USERNAME/PASSWORD if both are provided
if [ -n "\${USERNAME}" ] && [ -n "\${PASSWORD}" ]; then
  echo "--- Basic auth enabled: Creating config.yaml with provided credentials. ---"
  
  cat <<EOT > \${CONFIG_FILE}
dataRoot: ./data
listen: true
listenAddress:
  ipv4: 0.0.0.0
  ipv6: '[::]'
protocol:
    ipv4: true
    ipv6: false
dnsPreferIPv6: false
autorunHostname: "auto"
port: 8000
autorunPortOverride: -1
ssl:
  enabled: false
  certPath: "./certs/cert.pem"
  keyPath: "./certs/privkey.pem"
whitelistMode: false
enableForwardedWhitelist: false
whitelist:
  - ::1
  - 127.0.0.1
whitelistDockerHosts: true
basicAuthMode: true
basicAuthUser:
  username: "\${USERNAME}"
  password: "\${PASSWORD}"
enableCorsProxy: false
requestProxy:
  enabled: false
  url: "socks5://username:password@example.com:1080"
  bypass:
    - localhost
    - 127.0.0.1
enableUserAccounts: false
enableDiscreetLogin: false
autheliaAuth: false
perUserBasicAuth: false
sessionTimeout: -1
disableCsrfProtection: false
securityOverride: false
logging:
  enableAccessLog: true
  minLogLevel: 0
rateLimiting:
  preferRealIpHeader: false
autorun: false
avoidLocalhost: false
backups:
  common:
    numberOfBackups: 50
  chat:
    enabled: true
    checkIntegrity: true
    maxTotalBackups: -1
    throttleInterval: 10000
thumbnails:
  enabled: true
  format: "jpg"
  quality: 95
  dimensions: { 'bg': [160, 90], 'avatar': [96, 144] }
performance:
  lazyLoadCharacters: false
  memoryCacheCapacity: '100mb'
  useDiskCache: true
allowKeysExposure: true
skipContentCheck: false
whitelistImportDomains:
  - localhost
  - cdn.discordapp.com
  - files.catbox.moe
  - raw.githubusercontent.com
requestOverrides: []
extensions:
  enabled: true
  autoUpdate: false
  models:
    autoDownload: true
    classification: Cohee/distilbert-base-uncased-go-emotions-onnx
    captioning: Xenova/vit-gpt2-image-captioning
    embedding: Cohee/jina-embeddings-v2-base-en
    speechToText: Xenova/whisper-small
    textToSpeech: Xenova/speecht5_tts
enableDownloadableTokenizers: true
promptPlaceholder: "[Start a new chat]"
openai:
  randomizeUserId: false
  captionSystemPrompt: ""
deepl:
  formality: default
mistral:
  enablePrefix: false
ollama:
  keepAlive: -1
  batchSize: -1
claude:
  enableSystemPromptCache: false
  cachingAtDepth: -1
enableServerPlugins: true
enableServerPluginsAutoUpdate: false
EOT

# Priority 2: Use CONFIG_YAML if provided (and username/password are not)
elif [ -n "\${CONFIG_YAML}" ]; then
  echo "--- Found CONFIG_YAML, creating config.yaml from environment variable. ---"
  echo "\${CONFIG_YAML}" | base64 -d > \${CONFIG_FILE}

# Priority 3: No config provided, let the app use its defaults
else
    echo "--- No user/pass or CONFIG_YAML provided. App will use its default settings. ---"
fi

echo "*** Starting SillyTavern... ***"
node ${APP_HOME}/server.js &
SERVER_PID=\$!

echo "SillyTavern server started with PID \${SERVER_PID}. Waiting for it to become responsive..."

# Health check and keep-alive loop
RETRY_COUNT=0
MAX_RETRIES=12 # Wait for 60 seconds max
while ! curl -sf http://localhost:8000/ > /dev/null; do
    RETRY_COUNT=\$((RETRY_COUNT+1))
    if [ \${RETRY_COUNT} -ge \${MAX_RETRIES} ]; then
        echo "SillyTavern failed to start. Exiting."
        kill \${SERVER_PID}
        exit 1
    fi
    echo "SillyTavern is still starting or not responsive on port 8000, waiting 5 seconds..."
    sleep 5
done

echo "SillyTavern started successfully! Beginning periodic keep-alive..."

# Keep-alive loop
while kill -0 \${SERVER_PID} 2>/dev/null; do
    echo "Sending keep-alive request to http://localhost:8000/"
    curl -sf http://localhost:8000/ > /dev/null || echo "Keep-alive request failed."
    echo "Keep-alive request sent. Sleeping for 30 minutes."
    sleep 1800
done &

wait \${SERVER_PID}
EOF

# Make the new entrypoint executable
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 8000

# Entrypoint: Execute the self-contained startup script
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]