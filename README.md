# Omarchy VPN

A VPN toggle in Omarchy’s Wi-Fi panel, with a shield showing connection status. Remembers your last on/off choice across reboots.

Requires Omarchy’s Quickshell shell and an existing NetworkManager WireGuard connection.

## Install

```sh
omarchy plugin add https://github.com/TitanUranus67/omarchy-vpn.git --enable
```

## Configure

In `~/.config/omarchy/shell.json`, set your saved connection name in the `community.vpn` bar entry:

```json
{
  "id": "community.vpn",
  "vpnConnection": "vpn",
  "vpnLabel": "VPN"
}
```

Click the Wi-Fi icon to toggle, or press **V** with the panel open. The shield lights up when NetworkManager reports the connection active.

Uses your existing VPN routing and DNS settings; does not provide a kill switch.

Based on [Omarchy](https://github.com/basecamp/omarchy). [MIT license](LICENSE).
