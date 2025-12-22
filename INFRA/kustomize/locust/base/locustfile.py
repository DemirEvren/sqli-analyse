import os
from locust import HttpUser, task, between

# We sturen requests naar de app cluster's ingress via the shared Docker network.
# Routing naar prod/test gebeurt via Host header.
BASE_URL = os.getenv(
    "BASE_URL",
    "http://172.18.0.5"
)

TARGET_ENV = os.getenv("TARGET_ENV", "prod").lower()  # "prod" of "test"

# Default hostnames voor jouw Gateway HTTPRoutes
DEFAULT_HOSTS = {
    "prod": "shelfware.local",
    "test": "test.shelfware.local",
}

HOST_HEADER = os.getenv("HOST_HEADER", DEFAULT_HOSTS.get(TARGET_ENV, "shelfware.local"))


class ShelfwareUser(HttpUser):
    host = BASE_URL
    wait_time = between(0.5, 2.0)

    def on_start(self):
        # Default headers voor alle requests
        self.client.headers.update({
            "Host": HOST_HEADER,
            "User-Agent": "locust",
        })

    @task(10)
    def root(self):
        # Dit werkt sowieso met je echo setup
        self.client.get("/", name="GET /")

    @task(5)
    def get_projects(self):
        self.client.get("/api/projects", name="GET /api/projects")

    @task(2)
    def health(self):
        # Alleen nuttig als je app dit heeft; anders krijg je 404 (mag ook)
        self.client.get("/health", name="GET /health", allow_redirects=False)
