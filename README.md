# PostgreSQL SwissKnife

A comprehensive Bash suite for managing PostgreSQL instances.
Designed for **User-Space** usage (no root) and **Systemd** automation.

## Features

* **Multi-Profile Management**: Manage local or remote instances via a centralized interface.
* **Zero-Root Architecture**: Runs entirely as a standard user (supports `systemd --user`).
* **Automated Backups**: Intelligent rotation, compression, and retention policies.
* **Maintenance**: Auto-detection of missing Primary Keys and Bloat (Vacuum).
* **Security Audits**: Checks for empty passwords, superuser abuse, and dangerous settings.
* **Performance Monitor**: Real-time snapshot of Cache Hit Ratio, Connections, and Slow Queries.
* **Systemd Integration**: Easily schedule tasks like backups and maintenance.

## Installation

1.  Clone the repository:
    ```bash
    git clone https://github.com/viruslox/PostgreSQL_SwissKnife.git
    cd PostgreSQL_SwissKnife
    ```

2.  Make the script executable:
    ```bash
    chmod +x pgSQL_SwissKnife.sh
    ```

3.  Run the main menu to set up a profile:
    ```bash
    ./pgSQL_SwissKnife.sh
    ```
    Select **1. Setup & Profile Management** to add connection details or initialize a new instance.

## Usage

### Main Menu
The primary entry point is the `pgSQL_SwissKnife.sh` script:

```bash
./pgSQL_SwissKnife.sh
```

From here, you can access all modules:
*   **Setup & Profile Management**: Configure connection profiles.
*   **Backup Strategy**: Manage backups interactively.
*   **Maintenance Tasks**: Run VACUUM/ANALYZE checks.
*   **Performance Monitor**: View live metrics.
*   **Security Audit**: Generate security reports.
*   **Systemd Integration**: Schedule automated tasks.

### Updating
To update the tool to the latest version:

```bash
./pgSQL_SwissKnife.sh update
```

### Automation (Systemd)
To schedule Backups or Maintenance automatically:

1.  Launch the main menu: `./pgSQL_SwissKnife.sh`
2.  Select **6. Systemd Integration**.
3.  Choose a profile and configure the schedule (e.g., "daily", "weekly").
4.  Verify active timers:
    ```bash
    systemctl --user list-timers
    ```

## Requirements
*   `bash` (4.0+)
*   `postgresql-client` (psql, pg_dump, vacuumdb)
*   `systemd` (for automation features)

## Directory Structure
*   `~/.config/systemd/user/`: Systemd user service files.
*   `config/`: Configuration files (created after setup).
*   `backups/`: Backup destination (organized by profile name).
*   `logs/`: Application logs.
*   `audits/`: Security audit reports.
