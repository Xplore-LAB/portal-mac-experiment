#!/usr/bin/env python3
"""Offline behavioral checks: all network commands are replaced with local fakes."""
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

FAKES = r'''
require_tools() { :; }
need() { :; }
read_wifi_mac() { printf '%s\n' "${ACTUAL_MAC:-aa:bb:cc:dd:ee:ff}"; }
sudo() { printf 'MUTATION:%s\n' "$*"; "$@"; }
sysctl() { printf '%s\n' "${FORWARDING:-0}"; }
ip() {
  if [[ "$*" == *'route get'* ]]; then
    local dev="${SSH_DEV:-eth0}"
    [[ "${*: -1}" != '1.1.1.1' ]] || dev="${PUBLIC_DEV:-wlan0}"
    printf '192.0.2.1 dev %s src 192.0.2.2\n' "$dev"
  elif [[ "${NO_IPV4:-0}" == 0 ]]; then
    printf '3: wlan0 inet 192.0.2.2/24 scope global wlan0\n'
  fi
}
nmcli() {
  local field='' escaped=1
  if [[ "${1:-}" == '--escape' ]]; then
    [[ "$2" != no ]] || escaped=0
    shift 2
  fi
  if [[ "${1:-}" == '-g' ]]; then
    field="$2"
    case "$field" in
      connection.stable-id)
        if [[ "${FOREIGN:-0}" == 1 ]]; then printf 'someone-else\n'
        elif [[ "${*: -1}" == portal-mgmt-static ]]; then printf 'portal-mgmt-static-owned-v1\n'
        else printf 'portal-mac-test-owned-v1\n'; fi ;;
      802-11-wireless.cloned-mac-address)
        if (( escaped )); then printf 'aa\\:bb\\:cc\\:dd\\:ee\\:ff\n'
        else printf 'aa:bb:cc:dd:ee:ff\n'; fi ;;
      GENERAL.CONNECTION) printf '%s\n' "${ACTIVE:-portal-mac-test}" ;;
      *) printf 'UNHANDLED FIELD: %s\n' "$field" >&2; return 99 ;;
    esac
  elif [[ "$*" == 'connection show portal-mac-test' ]]; then
    [[ "${PROFILE_EXISTS:-1}" == 1 ]]
  elif [[ "$*" == 'connection up '* || "$*" == '--wait 45 connection up '* ]]; then
    [[ "${UP_FAIL:-0}" == 0 ]]
  elif [[ "$*" == 'connection add '* ]]; then
    PROFILE_EXISTS=1
  elif [[ "$*" == 'connection delete '* || "$*" == 'device down '* ]]; then
    :
  else
    printf 'UNHANDLED NMCLI: %s\n' "$*" >&2
    return 99
  fi
}
'''


class NetworkRegression(unittest.TestCase):
    def run_core(self, command, *, script="portal-mac.sh", input="YES\n", **values):
        env = os.environ.copy()
        env.update(SSH_CONNECTION="192.0.2.1 50000 192.0.2.2 22")
        for key in ("PORTAL_SSID", "PORTAL_TARGET_MAC", "WIFI_IF", "ETH_IF"):
            env.pop(key, None)
        env.update({k: str(v) for k, v in values.items()})
        source = f'source {shlex.quote(str(ROOT / "scripts" / script))}\n'
        return subprocess.run(["bash", "-c", source + FAKES + command],
                              input=input, capture_output=True, text=True, env=env, timeout=10)

    def assert_stopped_without_changes(self, result):
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("MUTATION:", result.stdout)

    def test_escaped_mac_is_read_as_literal(self):
        result = self.run_core("run_connect")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("MAC 已生效", result.stdout)

    def test_wireless_ssh_blocks_activation(self):
        self.assert_stopped_without_changes(self.run_core("run_connect", SSH_DEV="wlan0"))

    def test_ipv6_ssh_uses_ipv6_route(self):
        result = self.run_core(r'''
ip() { [[ "$*" == '-6 route get 2001:db8::1' ]] || return 99; printf '2001:db8::1 dev eth0\n'; }
check_management_path
''', SSH_CONNECTION="2001:db8::1 50000 2001:db8::2 22")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_forwarding_blocks_activation(self):
        self.assert_stopped_without_changes(self.run_core("run_connect", FORWARDING=1))

    def test_foreign_profile_is_never_deleted(self):
        self.assert_stopped_without_changes(self.run_core("run_restore", FOREIGN=1))

    def test_prepare_does_not_overwrite_old_profile(self):
        self.assert_stopped_without_changes(self.run_core("run_prepare"))

    def test_prepare_profile_is_memory_only_and_ipv4_required(self):
        result = self.run_core("run_prepare", PROFILE_EXISTS=0,
                               PORTAL_SSID="Example-WiFi", PORTAL_TARGET_MAC="aa:bb:cc:dd:ee:ff")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("connection add save no", result.stdout)
        self.assertIn("ipv4.may-fail no", result.stdout)

    def test_invalid_macs_are_rejected(self):
        for mac in ("00:00:00:00:00:00", "ff:ff:ff:ff:ff:ff", "01:23:45:67:89:ab", "bad"):
            with self.subTest(mac=mac):
                result = self.run_core("run_prepare", PROFILE_EXISTS=0,
                                       PORTAL_SSID="Example-WiFi", PORTAL_TARGET_MAC=mac)
                self.assert_stopped_without_changes(result)

    def test_ssid_length_counts_utf8_bytes(self):
        for ssid in ("x" * 33, "树" * 11, "two\nlines"):
            with self.subTest(ssid=ssid):
                self.assert_stopped_without_changes(self.run_core(
                    "run_prepare", PROFILE_EXISTS=0, PORTAL_SSID=ssid,
                    PORTAL_TARGET_MAC="aa:bb:cc:dd:ee:ff"))

    def test_wrong_public_route_disconnects_wifi(self):
        result = self.run_core("run_connect", PUBLIC_DEV="eth0")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("MUTATION:nmcli device down wlan0", result.stdout)

    def test_missing_ipv4_disconnects_wifi(self):
        result = self.run_core("run_connect", NO_IPV4=1)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("MUTATION:nmcli device down wlan0", result.stdout)

    def test_mac_mismatch_disconnects_wifi(self):
        result = self.run_core("run_connect", ACTUAL_MAC="02:00:00:00:00:01")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("MUTATION:nmcli device down wlan0", result.stdout)

    def test_failed_activation_disconnects_wifi(self):
        result = self.run_core("run_connect", UP_FAIL=1)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("MUTATION:nmcli device down wlan0", result.stdout)

    def test_restore_preserves_other_active_connection(self):
        result = self.run_core("run_restore", ACTIVE="My Wi-Fi")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("MUTATION:nmcli device down", result.stdout)
        self.assertIn("MUTATION:nmcli connection delete portal-mac-test", result.stdout)

    def test_restore_without_profile_is_idempotent(self):
        result = self.run_core("run_restore", PROFILE_EXISTS=0)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("MUTATION:", result.stdout)

    def test_ethernet_cannot_replace_newly_active_connection(self):
        result = self.run_core("run_up", script="ethernet-management.sh", ACTIVE="Business LAN")
        self.assert_stopped_without_changes(result)

    def test_ethernet_restore_cannot_disconnect_its_ssh(self):
        result = self.run_core("run_restore", script="ethernet-management.sh", SSH_DEV="eth0")
        self.assert_stopped_without_changes(result)

    def run_wizard(self, *, prepare_fails):
        with tempfile.TemporaryDirectory(prefix="portal-mac-regression-") as tmp:
            folder = Path(tmp)
            (folder / "wizard.sh").write_text((ROOT / "scripts/wizard.sh").read_text())
            (folder / "portal-mac.sh").write_text(
                'case "$1" in\n'
                'check) exit 0 ;;\n'
                f'prepare) exit {1 if prepare_fails else 0} ;;\n'
                'connect) exit 1 ;;\n'
                'restore) printf restored > "$TEST_RESTORE_FLAG" ;;\n'
                'esac\n')
            fake_nmcli = folder / "nmcli"
            fake_nmcli.write_text('#!/usr/bin/env bash\nprintf "portal-mac-test-owned-v1\\n"\n')
            fake_nmcli.chmod(0o755)
            flag = folder / "restore-called"
            env = os.environ.copy()
            env.update(PATH=str(folder) + os.pathsep + env["PATH"], TEST_RESTORE_FLAG=str(flag))
            result = subprocess.run(["bash", str(folder / "wizard.sh")], env=env,
                                    input="\n", capture_output=True, text=True, timeout=10)
            self.assertNotEqual(result.returncode, 0)
            return flag.exists()

    def test_wizard_prepare_failure_does_not_cleanup_existing_profile(self):
        self.assertFalse(self.run_wizard(prepare_fails=True))

    def test_wizard_connect_failure_cleans_up_its_profile(self):
        self.assertTrue(self.run_wizard(prepare_fails=False))

    def test_quick_start_mac_formats_and_rejections(self):
        with tempfile.TemporaryDirectory(prefix="portal-entry-regression-") as tmp:
            folder = Path(tmp)
            (folder / "quick-start.sh").write_text((ROOT / "quick-start.sh").read_text())
            (folder / "scripts").mkdir()
            (folder / "scripts/wizard.sh").write_text('printf "NORMALIZED:%s\\n" "$PORTAL_TARGET_MAC"\n')
            config = folder / "config"
            settings = config / "portal-mac-test"
            settings.mkdir(parents=True)
            (settings / "quick-start-ssid").write_text("Example-WiFi\n")
            env = os.environ.copy()
            env.pop("SSH_CONNECTION", None)
            env["XDG_CONFIG_HOME"] = str(config)
            for mac in ("AA:BB:CC:DD:EE:FF", "aa-bb-cc-dd-ee-ff", "aabbccddeeff"):
                with self.subTest(mac=mac):
                    result = subprocess.run(["bash", str(folder / "quick-start.sh")], env=env,
                                            input=mac + "\n", text=True, capture_output=True, timeout=10)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertIn("NORMALIZED:aa:bb:cc:dd:ee:ff", result.stdout)
            for mac in ("000000000000", "ffffffffffff", "invalid"):
                with self.subTest(mac=mac):
                    result = subprocess.run(["bash", str(folder / "quick-start.sh")], env=env,
                                            input=mac + "\n", text=True, capture_output=True, timeout=10)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertNotIn("NORMALIZED:", result.stdout)
            self.assertEqual([p.name for p in settings.iterdir()], ["quick-start-ssid"])

    def test_quick_setup_enforces_byte_limit_and_private_file(self):
        with tempfile.TemporaryDirectory(prefix="portal-ssid-regression-") as tmp:
            env = os.environ.copy()
            env["XDG_CONFIG_HOME"] = tmp
            settings = Path(tmp) / "portal-mac-test/quick-start-ssid"
            for ssid in ("树" * 11, "x" * 33):
                result = subprocess.run(["bash", str(ROOT / "quick-start.sh"), "--setup"],
                                        env=env, input=ssid + "\n", text=True, capture_output=True, timeout=10)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(settings.exists())
            result = subprocess.run(["bash", str(ROOT / "quick-start.sh"), "--setup"],
                                    env=env, input="Example-WiFi\n", text=True, capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(settings.stat().st_mode & 0o777, 0o600)
            self.assertEqual(settings.read_text(), "Example-WiFi\n")


if __name__ == "__main__":
    unittest.main(verbosity=2)
