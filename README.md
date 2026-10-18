# The Movie Hat 🤠🎬

A lightweight, self-hosted web application for organizing themed movie collections ("hats"), drawing random films with card-flip animations, collaborating with family or friends, and maintaining your watched history.

---

## ✨ Features

- 🎩 **Themed Movie Hats:** Group films by genre, director, marathon, or mood (*e.g., Spooky Season, 90s Action, Oscar Contenders*).
- 🎲 **Interactive Drawings:**
  - **Solo Draw:** Pulls one movie directly into the spotlight.
  - **Collaborative Pick-from-3:** Pulls 3 synchronized candidate cards across all devices. Collaborators can vote on their favorite to put it **On Deck**.
- 👥 **Real-Time Collaboration:** Share hats with friends by username. Active candidates, watch states, and pool updates sync instantly over WebSockets.
- 🍿 **TMDb Poster & Metadata Integration:** Search films directly with live autocomplete, release dates, and high-resolution posters. Configured dynamically through the web UI and stored safely in SQLite.
- 📱 **Responsive Cinema UI:** Mobile-first responsive navigation bar with cinema-themed styling, drawer menus, and toast notifications.
- ⚡ **Background Version Updates:** Built-in Service Worker automatically checks for app updates and shows a non-intrusive floating cinema banner to reload.

---

## 🖥️ Proxmox VE LXC 1-Liner Installation

Deploy The Movie Hat inside an isolated, lightweight Debian 12 LXC container on your Proxmox VE node with a single command:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/keljoundi/movie-hat/main/ct/movie-hat.sh)"
```

### What the Script Configures
- **Base OS:** Debian 12 (Bookworm) Unprivileged Container
- **Default Resources:** 1 vCPU, 1024 MB RAM, 4 GB Disk, DHCP network
- **Runtime:** Node.js 22 LTS, SQLite3, systemd daemon
- **Install Directory:** `/srv/movie-hat`
- **Persistent Database:** `/srv/movies.db` (persists across updates)
- **Service:** Automatically configured as `movie-hat.service` with auto-restart on boot

---

## 🔄 Updating Your Container

To upgrade an existing container to the latest release, open the Proxmox LXC console and run:

```bash
update
```

The updater pulls the latest pre-compiled bundle from GitHub Releases, updates dependencies, preserves your database and `.env` settings, and restarts the service with zero data loss.

---

## 📦 Manual / Bare-Metal / Docker Installation

If you prefer installing on an existing Linux host, VM, or custom server:

### Prerequisites
- Node.js 20.x or 22.x LTS
- SQLite3

### Step-by-Step

1. **Download the latest release:**
   Visit the [Releases](https://github.com/keljoundi/movie-hat/releases) page and download `movie-hat-vX.Y.Z.tar.gz`.

2. **Extract to your desired application directory:**
   ```bash
   sudo mkdir -p /srv/movie-hat
   sudo tar -xzf movie-hat-v*.tar.gz -C /srv/movie-hat
   cd /srv/movie-hat
   ```

3. **Install production dependencies:**
   ```bash
   npm install --omit=dev
   ```

4. **Configure environment:**
   ```bash
   cp .env.example .env
   # Edit .env with your preferred PORT and persistent DB_PATH
   nano .env
   ```

5. **Start the application:**
   ```bash
   # Directly:
   npm start

   # Or using PM2:
   pm2 start ecosystem.config.js --env production
   ```

6. Open `http://<YOUR_IP>:3000` in your browser to complete the first-run Admin setup wizard.

---

## ⚙️ Configuration & Diagnostics

| Variable | Default | Purpose |
| :--- | :--- | :--- |
| `PORT` | `3000` | Port the HTTP and WebSocket server listens on |
| `DB_PATH` | `/srv/movies.db` | Location of the SQLite database file |
| `JWT_SECRET` | Auto-generated | Cryptographic secret for cookie-based session tokens |

> **Note on TMDb:** You do **not** need to set your TMDb API key in `.env`. Once the web interface is opened, you can supply your API key during the initial setup wizard or at any time in the **Settings** menu.

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).
