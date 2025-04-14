FROM node:lts-alpine3.19

# Arguments
ARG APP_HOME=/home/node/app
ARG PLUGINS="" # Comma-separated list of plugin git URLs

# Install system dependencies
# Add unzip for extracting the application code
# Keep git for potential use by scripts or future plugin updates
# Add wget to download the zip file
RUN apk add --no-cache gcompat tini git unzip wget

# Create app directory
WORKDIR ${APP_HOME}

# Set NODE_ENV to production
ENV NODE_ENV=production

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

EXPOSE 8000

# Entrypoint: Read config from environment variable CONFIG_YAML if set, copy default if not, configure git, then run node server.js directly
ENTRYPOINT ["tini", "--", "sh", "-c", " \
    # --- BEGIN: Update SillyTavern Core at Runtime --- \
    echo '--- Attempting to update SillyTavern Core from GitHub (staging branch) ---'; \
    if [ -d \".git\" ] && [ \"$(git rev-parse --abbrev-ref HEAD)\" = \"staging\" ]; then \
      echo 'Existing staging branch found. Resetting and pulling latest changes...'; \
      git reset --hard HEAD && \
      git pull origin staging || echo 'WARN: git pull failed, continuing with code from build time.'; \
      echo '--- SillyTavern Core update check finished. ---'; \
    else \
      echo 'WARN: .git directory not found or not on staging branch. Skipping runtime update. Code from build time will be used.'; \
    fi; \
    # --- END: Update SillyTavern Core at Runtime --- \

    echo '--- Checking for CONFIG_YAML environment variable ---'; \
    # Ensure the CWD has correct permissions for writing config.yaml
    # mkdir -p ./config && chown node:node ./config; # Removed mkdir
    if [ -n \"$CONFIG_YAML\" ]; then \
      echo 'Environment variable CONFIG_YAML found. Writing to ./config.yaml (root directory)...'; \
      # Write directly to ./config.yaml in the CWD
      printf '%s\n' \"$CONFIG_YAML\" > ./config.yaml && \
      chown node:node ./config.yaml && \
      echo 'Config written to ./config.yaml and permissions set successfully.'; \
      # --- BEGIN DEBUG: Print the written config file ---
      echo '--- Verifying written ./config.yaml ---'; \
      cat ./config.yaml; \
      echo '--- End of ./config.yaml ---'; \
      # --- END DEBUG ---
    else \
      echo 'Warning: Environment variable CONFIG_YAML is not set or empty. Attempting to copy default config...'; \
      # Copy default if ENV VAR is missing and the example exists
      if [ -f \"./public/config.yaml.example\" ]; then \
          # Copy default to ./config.yaml in the CWD
          cp \"./public/config.yaml.example\" \"./config.yaml\" && \
          chown node:node ./config.yaml && \
          echo 'Copied default config to ./config.yaml'; \
      else \
          echo 'Warning: Default config ./public/config.yaml.example not found.'; \
      fi; \
    fi; \

    # --- BEGIN: Configure Git default identity at Runtime --- \
    echo '--- Configuring Git default user identity at runtime ---'; \
    git config --global user.name \"SillyTavern Sync\" && \
    git config --global user.email \"sillytavern-sync@example.com\"; \
    echo '--- Git identity configured for runtime user. ---'; \
    # --- END: Configure Git default identity at Runtime --- \

    # --- BEGIN: Dynamically Install Plugins at Runtime --- \
    echo '--- Checking for PLUGINS environment variable ---'; \
    if [ -n \"$PLUGINS\" ]; then \
      echo \"*** Installing Plugins specified in PLUGINS environment variable: $PLUGINS ***\" && \
      # Ensure plugins directory exists
      mkdir -p ./plugins && chown node:node ./plugins && \
      # Set comma as delimiter
      IFS=',' && \
      # Loop through each plugin URL
      for plugin_url in $PLUGINS; do \
        # Trim leading/trailing whitespace
        plugin_url=$(echo \"$plugin_url\" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//') && \
        if [ -z \"$plugin_url\" ]; then continue; fi && \
        # Extract plugin name
        plugin_name_git=$(basename \"$plugin_url\") && \
        plugin_name=${plugin_name_git%.git} && \
        plugin_dir=\"./plugins/$plugin_name\" && \
        echo \"--- Installing plugin: $plugin_name from $plugin_url into $plugin_dir ---\" && \
        # Remove existing dir if it exists
        rm -rf \"$plugin_dir\" && \
        # Clone the plugin (run as root, fix perms later)
        git clone --depth 1 \"$plugin_url\" \"$plugin_dir\" && \
        if [ -f \"$plugin_dir/package.json\" ]; then \
          echo \"--- Installing dependencies for $plugin_name ---\" && \
          (cd \"$plugin_dir\" && npm install --no-audit --no-fund --loglevel=error --no-progress --omit=dev --force && npm cache clean --force) || echo \"WARN: Failed to install dependencies for $plugin_name\"; \
        else \
           echo \"--- No package.json found for $plugin_name, skipping dependency install. ---\"; \
        fi || echo \"WARN: Failed to clone $plugin_name from $plugin_url, skipping...\"; \
      done && \
      # Reset IFS
      unset IFS && \
      # Fix permissions for plugins directory after installation
      echo \"--- Setting permissions for plugins directory ---\" && \
      chown -R node:node ./plugins && \
      echo \"*** Plugin installation finished. ***\"; \
    else \
      echo 'PLUGINS environment variable is not set or empty, skipping runtime plugin installation.'; \
    fi; \
    # --- END: Dynamically Install Plugins at Runtime --- \

    echo 'Starting SillyTavern server directly...'; \

    # --- BEGIN: Cleanup before start --- \
    # Remove .gitignore
    echo 'Attempting final removal of .gitignore...' && \
    rm -f .gitignore && \
    if [ ! -e .gitignore ]; then \
      echo '.gitignore successfully removed.'; \
    else \
      # This case is unlikely with rm -f unless permissions prevent removal
      echo 'WARN: .gitignore could not be removed or reappeared.'; \
    fi; \
    # Remove .git directory
    echo 'Attempting final removal of .git directory...' && \
    rm -rf .git && \
    if [ ! -d .git ]; then \
      echo '.git directory successfully removed.'; \
    else \
      # This case usually indicates a permission issue
      echo 'WARN: .git directory could not be removed.'; \
    fi; \
    # --- END: Cleanup before start --- \

    # Execute node server directly, bypassing docker-entrypoint.sh
    exec node server.js; \
  "]