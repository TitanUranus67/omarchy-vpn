import base64
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import vpn


class ImportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / 'provider with a long name.conf'
        # Synthetic parser fixture, never used for a real tunnel.
        key = base64.b64encode(bytes(range(32))).decode()
        self.config = ('[Interface]\nPrivateKey = ' + key
                       + '\nAddress = 10.222.0.2/32\nDNS = 1.1.1.1\n'
                       + '[Peer]\nPublicKey = ' + key
                       + '\nAllowedIPs = 0.0.0.0/0, ::/0\nEndpoint = vpn.example.com:51820\n')
        self.path.write_text(self.config)

    def test_import_is_inactive_and_keeps_routes_and_dns(self):
        c = vpn.prepare_import(str(self.path), 'Work VPN', [])
        self.assertEqual(c.get_id(), 'Work VPN')
        self.assertFalse(c.get_setting_connection().get_autoconnect())
        self.assertEqual(c.get_setting_ip4_config().get_dns(0), '1.1.1.1')
        self.assertEqual(c.get_setting(vpn.NM.SettingWireGuard).get_peer(0).get_allowed_ip(0), '0.0.0.0/0')
        self.assertEqual(c.get_setting(vpn.NM.SettingWireGuard).get_peer(0).get_allowed_ip(1), '::/0')
        self.assertTrue(c.verify())

    def test_imports_get_unique_ids_and_interface_names(self):
        a = vpn.prepare_import(str(self.path), 'One', [])
        b = vpn.prepare_import(str(self.path), 'Two', [])
        self.assertNotEqual(a.get_uuid(), b.get_uuid())
        self.assertNotEqual(a.get_interface_name(), b.get_interface_name())
        self.assertLessEqual(len(a.get_interface_name()), 15)

    def test_duplicate_name_rejected(self):
        with self.assertRaisesRegex(vpn.VpnError, 'already exists'):
            vpn.prepare_import(str(self.path), 'Work', [{'name': 'Work'}])

    def test_invalid_key_does_not_leak_in_error(self):
        marker = 'SENSITIVE-INVALID-KEY'
        self.path.write_text('[Interface]\nPrivateKey = ' + marker + '\n')
        with self.assertRaises(vpn.VpnError) as caught:
            vpn.prepare_import(str(self.path), 'Work', [])
        self.assertNotIn(marker, str(caught.exception))

    def test_invalid_name_and_missing_file(self):
        for name in ('', ' \t ', 'Bad\nname', 'x' * 129):
            with self.assertRaises(vpn.VpnError):
                vpn.prepare_import(str(self.path), name, [])
        with self.assertRaises(vpn.VpnError):
            vpn.prepare_import('/missing/file.conf', 'Work', [])

    def test_no_addition_after_validation_failure(self):
        client = Mock()
        client.get_connections.return_value = []
        self.path.write_text('not a wireguard config')
        with self.assertRaises(vpn.VpnError):
            vpn.import_profile(client, str(self.path), 'Work')
        client.add_connection_async.assert_not_called()

    def test_listing_only_exposes_wireguard_metadata(self):
        def connection(name, kind):
            c = Mock()
            c.get_id.return_value = name
            c.get_uuid.return_value = name + '-uuid'
            c.get_connection_type.return_value = kind
            return c
        client = Mock()
        client.get_connections.return_value = [connection('Wi-Fi', '802-11-wireless'), connection('Work', 'wireguard')]
        active = Mock()
        active.get_uuid.return_value = 'Work-uuid'
        active.get_state.return_value = vpn.NM.ActiveConnectionState.ACTIVATED
        client.get_active_connections.return_value = [active]
        self.assertEqual(vpn.profiles(client), [{'name': 'Work', 'uuid': 'Work-uuid', 'active': True}])


if __name__ == '__main__':
    unittest.main()
