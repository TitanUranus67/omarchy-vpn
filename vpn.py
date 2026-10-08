#!/usr/bin/env python3
"""Non-secret WireGuard profile metadata and safe, inactive config imports."""
import json
from pathlib import Path
import sys
import tempfile
import uuid

import gi

gi.require_version("NM", "1.0")
from gi.repository import GLib, NM


class VpnError(Exception):
    pass


def profiles(client):
    active = {a.get_uuid() for a in client.get_active_connections()
              if a.get_state() == NM.ActiveConnectionState.ACTIVATED}
    return sorted([
        {"uuid": c.get_uuid(), "name": c.get_id(), "active": c.get_uuid() in active}
        for c in client.get_connections()
        if c.get_connection_type() == "wireguard"
    ], key=lambda p: (p["name"].casefold(), p["uuid"]))


def prepare_import(filename, name, existing):
    name = name.strip()
    if not name or len(name) > 128 or any(ord(c) < 32 for c in name):
        raise VpnError("Enter a VPN name (1–128 characters).")
    if any(p["name"] == name for p in existing):
        raise VpnError("A connection with that name already exists. Choose another name.")
    path = Path(filename)
    try:
        if path.suffix.lower() != ".conf" or path.stat().st_size > 1024 * 1024:
            raise VpnError("Choose a WireGuard .conf file smaller than 1 MB.")
        # libnm's importer may include offending values in parse errors. Never
        # forward those errors (or file contents) to logs or the UI.
        # libnm derives an interface name from the filename. Use a private,
        # valid temporary basename so provider filenames may contain spaces.
        with tempfile.TemporaryDirectory(prefix="omarchy-vpn-") as directory:
            normalized = Path(directory) / "import.conf"
            with normalized.open("xb") as target:
                normalized.chmod(0o600)
                with path.open("rb") as source:
                    contents = source.read(1024 * 1024 + 1)
                if len(contents) > 1024 * 1024:
                    raise VpnError("Choose a WireGuard .conf file smaller than 1 MB.")
                target.write(contents)
            connection = NM.conn_wireguard_import(str(normalized))
    except (GLib.Error, OSError):
        raise VpnError("Could not read this WireGuard config. Check the file and try again.") from None
    setting = connection.get_setting_connection()
    identity = str(uuid.uuid4())
    setting.set_property("id", name)
    setting.set_property("uuid", identity)
    setting.set_property("interface-name", "wg-" + identity[:8])
    # Set BEFORE adding to NetworkManager: there is no activation race.
    setting.set_property("autoconnect", False)
    try:
        connection.normalize()
        connection.verify()
    except GLib.Error:
        raise VpnError("This WireGuard config contains unsupported or invalid settings.") from None
    return connection


def import_profile(client, filename, name):
    existing = [{"name": c.get_id()} for c in client.get_connections()]
    connection = prepare_import(filename, name, existing)
    loop = GLib.MainLoop()
    result = {}

    def finished(source, task, _data):
        try:
            saved = source.add_connection_finish(task)
            result.update(uuid=saved.get_uuid(), name=saved.get_id())
        except GLib.Error:
            result["error"] = "NetworkManager could not save the VPN. Check your connection permissions."
        loop.quit()

    client.add_connection_async(connection, True, None, finished, None)
    loop.run()
    if "error" in result:
        raise VpnError(result["error"])
    return result


def main():
    try:
        client = NM.Client.new(None)
        if not client.get_nm_running():
            raise VpnError("NetworkManager is not running.")
        if len(sys.argv) == 2 and sys.argv[1] == "list":
            result = {"profiles": profiles(client)}
        elif len(sys.argv) == 4 and sys.argv[1] == "import":
            result = import_profile(client, sys.argv[2], sys.argv[3])
        else:
            raise VpnError("Usage: vpn.py list | import FILE NAME")
        print(json.dumps(result))
    except (VpnError, GLib.Error) as error:
        # Only our own errors are safe to display. D-Bus errors can carry
        # details about the underlying connection that are not needed here.
        message = str(error) if isinstance(error, VpnError) else "Could not contact NetworkManager."
        print(json.dumps({"error": message}))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
