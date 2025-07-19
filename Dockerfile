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
# Add dos2unix to fix CRLF issues
RUN apk add --no-cache gcompat tini git unzip wget curl dos2unix

# Create app directory
WORKDIR ${APP_HOME}

# Set NODE_ENV to production and set credentials from ARGs
ENV NODE_ENV=production
ENV APP_HOME=${APP_HOME}
ENV USERNAME=${USERNAME}
ENV PASSWORD=${PASSWORD}

# --- BEGIN: Clone SillyTavern Core from GitHub (release branch) ---
RUN \
  echo "*** Cloning SillyTavern Core from GitHub (release branch) ***" && \
  # Clone the specific branch into the current directory
  git clone -b release --depth 1 https://github.com/SillyTavern/SillyTavern.git . && \
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

# Copy the entrypoint script from the repository
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

# Make the new entrypoint executable
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 8000

# Entrypoint: Execute the self-contained startup script
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
