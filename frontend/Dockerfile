# This Dockerfile prepares a frontend application for deployment.
# It uses a multi-stage build to separate the build process from the final production image.

# In the first stage, the application is built using Node.js:
# - A production build is generated

# In the second stage, the static build output is served using a lightweight web server.
# - A clean image is used to serve the app efficiently

# The final container exposes a single HTTP port and runs a web server in the foreground.

# ----------------------------------------------------
# Required commands and setup (to be used in the Dockerfile):
#
# npm install
# npm run build
# Port to expose: 80
# ----------------------------------------------------
