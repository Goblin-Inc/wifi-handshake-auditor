# Wi-Fi Handshake Auditor

> 🌐 **Language:** **English** | [Русский (README_Ru.md)](README_Ru.md)

«for authorized / educational use only»

An interactive Bash script that automates WPA/WPA2 wireless security auditing using the `aircrack-ng` suite.

## ✨ Features
- 📡 Automatically verifies required dependencies and switches the wireless interface into monitor mode (`airmon-ng`).
- 🔍 Scans nearby access points and connected clients (`airodump-ng`).
- 🤝 Captures WPA/WPA2 4-way handshakes and audits password strength against a wordlist (`aircrack-ng`).
- 🧹 Cleanly restores the network interface back to managed mode upon exit.

## 🚀 Usage

```bash
sudo ./wifi_auditor.sh
```

## 📄 License
MIT © [Goblin-Inc](https://github.com/Goblin-Inc)
