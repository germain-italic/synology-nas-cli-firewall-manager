# 🧠 Checking and Enabling /dev/kvm on Linux

Some containers, like Virtual DSM or other VM-based systems, require access to `/dev/kvm` to use hardware virtualization (KVM).

Here’s how to check if KVM is available and install it if needed.

---

## ✅ 1. Check if `/dev/kvm` exists

In your terminal, run:

```bash
ls -l /dev/kvm
```

If it returns something like:

```
crw-rw---- 1 root kvm 10, 232 /dev/kvm
```

➡️ You're good — KVM is available.

---

## ❌ If `/dev/kvm` is missing

You likely need to load the KVM kernel module or enable virtualization in your BIOS.

---

## 🔧 2. Load KVM manually

For Intel CPUs:

```bash
sudo modprobe kvm_intel
```

For AMD CPUs:

```bash
sudo modprobe kvm_amd
```

Then check:

```bash
lsmod | grep kvm
```

You should see lines like:

```
kvm_intel  ...
kvm        ...
```

---

## 🔁 3. Ensure your user can access `/dev/kvm`

Check group permissions:

```bash
ls -l /dev/kvm
```

Then add yourself to the `kvm` group:

```bash
sudo usermod -aG kvm $USER
newgrp kvm
```

---

## 🖥️ 4. If it still doesn’t work

- Ensure virtualization is **enabled in BIOS** (Intel VT-x or AMD-V)
- If you're running inside a VM, check that **nested virtualization** is allowed
- On WSL2, `/dev/kvm` is only available if Docker is installed directly in WSL (not via Docker Desktop)

---

## 📌 Note for macOS

macOS does not support `/dev/kvm` — this guide only applies to Linux and WSL2.

---

## ℹ️ Further help

RTFM from the vdsm repo: https://github.com/vdsm/virtual-dsm?tab=readme-ov-file#how-do-i-verify-if-my-system-supports-kvm