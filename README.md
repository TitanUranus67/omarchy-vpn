# Omarchy VPN

A VPN picker and toggle in Omarchy’s Wi-Fi panel. Import WireGuard configs, see connection status, and remember your on/off choice across reboots.

Requires Omarchy’s Quickshell shell, NetworkManager, `python-gobject`, `libnm`, and `zenity`.

## Install

```sh
omarchy plugin add https://github.com/TitanUranus67/omarchy-vpn.git --enable
```

## Use

- **Choose a VPN** from the picker, then toggle it on or off.
- **Add VPN…** → choose a WireGuard `.conf` → name it → **Add**. It stays disconnected until you click **Connect**.
- Disconnect an active VPN before connecting another. Your selection is saved automatically.
- Press **V** to toggle. On the VPN row, use **Left/Right** to choose the switch, picker, or Add button, then **Enter**.

The shield shows NetworkManager’s connection state. Uses your VPN’s routing and DNS settings; does not provide a kill switch.

Based on [Omarchy](https://github.com/basecamp/omarchy). [MIT license](LICENSE).
