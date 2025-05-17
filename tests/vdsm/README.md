# 🧪 Virtual DSM (vdsm) – Test Environment

This folder contains everything needed to run a fully working **Virtual DSM** (Synology DiskStation Manager) container using [`vdsm/virtual-dsm`](https://github.com/vdsm/virtual-dsm), tested on **Windows 11 + WSL2 + Docker**.

---

## ⚙️ Prerequisites

- Windows 11 with virtualization enabled (Intel VT-x or AMD-V)
- WSL2 installed with a Linux distribution (e.g. Debian, Ubuntu)
- Docker installed **inside WSL2** (not Docker Desktop)
- `/dev/kvm` must be available in WSL (KVM support is required)

> 💡 `Docker Desktop` and macOS are **not supported** for this project due to lack of KVM/macvtap.

---

## 📥 Cloning the Repository (from WSL)

In your WSL terminal:

```bash
git clone https://github.com/germain-italic//synology-nas-cli-firewall-manager.git
cd synology-nas-cli-firewall-manager/tests/vdsm
```

---

## 🚀 Installation

Inside WSL:

```bash
chmod +x install-vdsm.sh
./install-vdsm.sh
```

This script will:

- Check for Docker and Docker Compose
- Create the `data/` directory if needed
- Generate `docker-compose.yml` if not present
- Start the Virtual DSM container
- Launch an interactive control menu

---

## 🧭 Managing the Container

You can always rerun:

```bash
./vdsm-control.sh
```

### Menu options:

| Option | Description                         |
|--------|-------------------------------------|
| 1      | Start the DSM container             |
| 2      | Restart the container               |
| 3      | Stop and remove the container       |
| 4      | View live logs                      |
| 5      | Show container internal IP address  |
| 6      | Show container health status        |
| 7      | Open DSM in your browser (`localhost:5000`) |
| 0      | Exit the control menu               |

---

## 🌐 Access

Once running, DSM is accessible at:

[http://localhost:5000](http://localhost:5000)

---

## 📁 Data Location

All persistent DSM data is stored in:

```
./data/
```

This includes:
- `data.qcow2`: virtual system disk
- `*.img` and `*.pat`: boot and DSM system files
- `dsm.mac`, `dsm.ver`: internal Synology identifiers

> These files are **excluded from Git** via `.gitignore`.

---

## 📂 Accessing the Files from Windows Explorer

From your WSL terminal:

```bash
explorer.exe .
```

This opens the current folder (`vdsm/`) in Windows Explorer using the UNC path:

```
\\wsl.localhost\<YourDistro>\home\<you>\dev\synology-nas-cli-firewall-manager\tests\vdsm
```

> ⚠️ Do **not edit files directly from Windows** if they are mounted inside Docker containers.

---

## 💻 Linux Compatibility

This setup works **natively on Linux** with Docker and KVM. You must:

- have `/dev/kvm` available ([How to check for kvm and install it?](docs/kvm-check.md))
- add your user to the `kvm` group
- ensure network permissions for bridge or macvlan if used

### ❌ macOS Compatibility

macOS does **not support KVM**, so **this project cannot run on macOS**, even with Docker Desktop.

---

## 📣 Credits

This setup is based on the excellent open-source project:
[vdsm/virtual-dsm](https://github.com/vdsm/virtual-dsm)  
Maintained by [@vdsm](https://github.com/vdsm)

> All credit goes to the original author for building a fully functional Virtual DSM environment in Docker.

---

## 📜 Legal Note

This project is for **testing purposes only**. You must comply with Synology's [EULA](https://www.synology.com/en-global/company/legal/eula). This image is provided without any warranty and should not be used in production environments.
