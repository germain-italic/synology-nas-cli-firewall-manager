# Synology Firewall CLI Tools (DSM 7.x)

Shell scripts to manage Synology DSM 7.x firewall rules dynamically via SSH, without using the web GUI.

## 🔧 Included Scripts

- `manage.sh`: Main CLI interface with menu to manage all firewall operations
- `add_firewall_ip.sh`: Adds an IP address to the Synology firewall whitelist
- `remove_firewall_ip.sh`: Removes a firewall rule by its name (IP or hostname)
- `list_firewall_rules.sh`: Lists firewall rules with their name, IP address(es), and status
- `update_hostname_ip.sh`: Resolves a hostname (e.g., DDNS) and updates the firewall rule if the associated IP changes
- `rotate_logs_ip.sh`: Rotates log files when they exceed 1MB
- `update_firewall_rule_name.sh`: Updates the "name" field of a firewall rule matching a specific IP address

## 🌍 Multilingual Support

The scripts now include multilingual support (English/French):

- `lang/en.sh`: English language strings
- `lang/fr.sh`: French language strings
- `.env`: Configuration file to select language (not committed, created from .env.dist on first start)

To change the language, you can:
1. Edit `config.sh` and change `LANG="fr"` to `LANG="en"` (or vice versa)
2. Use option l/L (lower or upper key "L") in the main menu of `manage.sh`

## ⚙️ Requirements

- Root SSH access to the NAS
- DSM 7.x with active firewall configuration
- `jq` installed (read below)

## 📦 Installation

1. Copy all scripts into a directory on your NAS:

```bash
git clone git@github.com:germain-italic/synology-nas-cli-firewall-manager.git
```

2. Run the main menu interface:

```bash
./manage.sh
```

## 📦 Installation of jq

The `jq` command is required for these scripts. Here's how to install it based on your NAS architecture:

### 1. Determine your NAS architecture

```bash
uname -a
```

This command will give you information about your system. Note the architecture (x86_64, i686, armv7l, etc.).

### 2. Install jq directly from binary (recommended method)

#### For x86_64 (64-bit) systems:
```bash
# Download the 64-bit version
wget https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 -O jq

# Make it executable
chmod +x jq

# Move it to a directory in your PATH
sudo mv jq /usr/local/bin/
```

#### For i686/i386 (32-bit) systems:
```bash
# Download the 32-bit version
wget https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux32 -O jq

# Make it executable
chmod +x jq

# Move it to a directory in your PATH
sudo mv jq /usr/local/bin/
```

#### For ARM systems (like DS218j, DS220j, etc.):
For ARM-based NAS models, you may need to use the Entware or ipkg method mentioned in the project wiki.

### 3. Verify the installation

Regardless of the method used, verify that jq works correctly:

```bash
jq --version
```

If this command displays the jq version, the installation was successful.

## 🧪 Usage

### Main Menu Interface

The easiest way to use these tools is through the main menu interface:

```bash
./manage.sh
```

![GUI screenshot](screenshots/q1D882Yzbk.png)

This interactive menu provides access to all firewall management functions:

- List firewall rules
- Add an IP to the whitelist
- Remove a rule
- Update rule names
- Update IP for a hostname (DDNS)
- View iptables rules
- Enable/disable firewall
- Reload firewall configuration
- Clean up backup files
- Update scripts (via git pull)
- Change language (English/French)

### Individual Script Usage

If you prefer, you can also use the individual scripts directly:

#### Add an IP to the firewall whitelist

```bash
./add_firewall_ip.sh 192.168.1.100 myhome.ddns.net
```

If no hostname is provided, the IP address is used as the rule name.

#### Remove a firewall rule

```bash
./remove_firewall_ip.sh myhome.ddns.net
```

or

```bash
./remove_firewall_ip.sh 192.168.1.100
```

#### List firewall rules

```bash
./list_firewall_rules.sh
```

#### Update rule dynamically based on a hostname (e.g., DDNS)

```bash
./update_hostname_ip.sh myhome.ddns.net
```

If no argument is provided, it defaults to `myhome.ddns.net`.

#### Rotate log file

```bash
./rotate_logs_ip.sh
```

#### Update the name of a specific firewall rule

```bash
./update_firewall_rule_name.sh 192.168.1.100 myhome.ddns.net
```

This command will locate the rule containing the specified IP and update its `"name"` attribute.  
After execution, `list_firewall_rules.sh` will be called automatically to verify the result.

## 🛠️ Schedule via DSM GUI (Task Scheduler)

You can run `update_hostname_ip.sh` and `rotate_logs_ip.sh` automatically using Synology's Task Scheduler.

### Step-by-step (DSM GUI):

1. Open **Control Panel** → **Task Scheduler**
2. Click **Create** → **Scheduled Task** → **User-defined script**
3. Under the **General** tab:
   - Name: `Update DDNS IP`
   - User: `root`
4. Under the **Schedule** tab:
   - Set to run every 30 minutes (or as needed)
5. Under the **Task Settings** tab:
   - Paste the command:
     ```bash
     /volume1/homes/YourUser/scripts/cli-tools/synology/update_hostname_ip.sh
     ```
6. Repeat steps for `rotate_logs_ip.sh`, if desired.

#### DSM screenshots 

- [Task scheduler](screenshots/chrome_WnCAkr6PxU.png)
- [Update DDNS - General](screenshots/chrome_d9BmIjVpfx.png)
- [Update DDNS - Schedule](screenshots/chrome_kDxHyPqbSJ.png)
- [Update DDNS - Task](screenshots/chrome_rvF9eaVECz.png)
- [Rotate logs - Schedule](screenshots/chrome_8nY67MK55r.png)
- [Rotate logs - Task](screenshots/chrome_NKUCBflL0W.png)

## 🔐 Safety & Implementation Details

### How the scripts work internally

These scripts follow best practices for modifying the Synology firewall configuration:

1. **Official API Usage**: All permanent changes to the firewall configuration use the Synology's official firewall API, not direct iptables manipulations:
   - Scripts modify the JSON configuration files in `/usr/syno/etc/firewall.d/`
   - After modifications, they call `/usr/syno/bin/synofirewall --reload` to apply changes

2. **Typical Workflow**:
   - Identify the active firewall profile configuration file
   - Create a timestamped backup of this file
   - Modify the JSON by adding/removing/changing rules
   - Reload configuration through Synology's firewall API
   - If any errors occur, restore the backup automatically

3. **Iptables Commands** are used only for:
   - Displaying current status (`iptables -S`, `iptables -L`)
   - Verifying if rules were applied correctly
   - Detecting if the firewall is active

4. **Error Handling**: If the Synology API reports an error during reload, the original configuration is automatically restored to maintain firewall functionality.

This approach ensures that all changes are:
- Persistent across reboots
- Compatible with DSM's implementation
- Properly tracked in DSM's configuration system
- Safe with automatic rollback on errors

### Backup Safety

Every firewall config change is backed up with a timestamp. If something fails, the previous file is automatically restored and the firewall reloaded.

## 🧾 IP Change History

The script stores IP history in a permanent location that won't be wiped on reboot:
```bash
/volume1/homes/YourUser/firewall_history/
```

Each hostname has its own history file named after the hostname (with dots replaced by underscores):
```bash
/volume1/homes/YourUser/firewall_history/myhome_ddns_net.history
/volume1/homes/YourUser/firewall_history/myoffice_ddns_net.history
```

To reset tracking for a specific hostname, simply delete its corresponding history file.

## 📝 License

MIT – Use at your own risk.