# DevOps Capstone Project: Voting App

## What the App Does
This project is a distributed containerized application that lets users vote between two choices (e.g., Cats vs. Dogs).

It consists of multiple microservices working together:
- **Vote (Python):** A web frontend where users can cast their vote.
- **Result (Node.js):** A web frontend that displays the live voting totals.
- **Worker (.NET):** A background processor that takes votes from Redis and stores them permanently in PostgreSQL.
- **Redis:** An in-memory cache used to collect votes temporarily.
- **PostgreSQL:** A relational database used to store the final tally.

---

## How to Run Locally

To run this application locally on your machine for testing, make sure you have **Docker Desktop** installed and running, then follow these steps:

1. Clone your repository:
   ```bash
   git clone https://github.com/YOUR_USERNAME/example-voting-app.git
   cd example-voting-app
   ```

2. Build and start the containers using Docker Compose:
   ```bash
   docker compose up --build
   ```

3. Open your browser to test:

   Voting Page: http://localhost:8080

   Result Page: http://localhost:8081

4. To stop the application, press Ctrl + C in your terminal, then clean up the containers:
   ```bash
   docker compose down
   ```