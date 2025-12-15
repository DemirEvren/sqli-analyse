# This Dockerfile prepares a backend Node.js application for production use.
# It sets up the environment, installs necessary packages, prepares the database client,
# builds the application code, and creates a small final image for running the backend.

# The application is expected to run on port 3001 and should start in production mode.

# After setup, the database should be initialized before the backend is started.
# This process creates the required tables and seeds the database with initial data.

# A multi-stage build is used:
# - The first stage handles setup, dependency installation, and application build.
# - The second stage copies only the essential output into a clean base image.

# The result is a lightweight production image containing only what’s needed to run the app.


# ----------------------------------------------------
# Required commands (to be used in the Dockerfile):
#
# npm install
# npx prisma generate
# npm run build
# npm start
# npm run init-db
#
# ----------------------------------------------------
