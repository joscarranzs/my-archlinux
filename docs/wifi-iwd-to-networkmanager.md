# Retiring iwd for NetworkManager (wpa_supplicant) on this host

Why `systemctl stop iwd` used to kill the wifi, why the machine sometimes ended up with
two IP addresses and two default routes, and the exact order that gets from the old stack
to a single owner without leaving the machine offline.

Everything here was measured on this machine (Arch, Intel wifi, NetworkManager 1.58.1,
iwd 3.12). It is written to be replayed on a fresh install years from now, by a person or
by a model that has never seen this host.

---

## 1. The symptom

Every attempt to leave iwd ended the same way:

```
$ nmcli device
Device "wlan0" does not exist.
$ iwctl station wlan0 show
(no station)
$ ip -br link
wlan0  DOWN  <mac>
```

The interface vanished from NetworkManager's view (and, when iwd was the one that had
created it, from the kernel too). The wifi panel showed `No device`. The only recovery
that always worked was a reboot, which made the problem look like a mystery instead of a
sequence.

---

## 2. Root cause A: iwd owns the wireless netdev, and destroys it on exit

This is documented upstream, in three places that agree:

* `iwd.config(5)`:

  > `[DriverQuirks] DefaultInterface=true` — *"Do not allow iwd to destroy / recreate
  > wireless interfaces at startup, including default interfaces."*
  >
  > The pre-3.x spelling is `[General] UseDefaultInterface=true` (deprecated, still
  > accepted).

* Gentoo's wiki states the other half explicitly: *"When iwd terminates, it destroys the
  wireless interface it created."*

* Arch BBS thread [#260888](https://bbs.archlinux.org/viewtopic.php?id=260888) is the
  identical symptom: `wlan0` is there while `iwd.service` runs and gone once it stops;
  NetworkManager then cannot find the device and the reporter's workaround was a reboot.

So it was never a driver bug or a broken install: iwd manages the *existence* of the
interface it uses. Stop the daemon and the interface it created goes with it. Nothing
downstream can fix that after the fact, which is why bringing iwd back (or rebooting)
was the only thing that ever worked.

**The fix** is `/etc/iwd/main.conf`:

```ini
[DriverQuirks]
DefaultInterface=true
```

With it, iwd stops taking ownership of the netdev lifecycle. Measured on this host: after
the quirk, stopping iwd left `/sys/class/net/wlan0` present (`iface=sí` in the scripts'
output) for the first time.

### 2.1 The quirk saves the interface, not the session

Measured afterwards, and this is the part that is easy to get wrong: **stopping iwd always
drops the 802.11 association**, even with the quirk applied and even when iwd is not the
supplicant that is connected. The quirk preserves the *netdev*; it does not preserve the
radio session — iwd powers the adapter down as it exits.

Consequence: the transition always costs a few seconds of downtime, and the recovery has
to be *re-activating the profile*, not waiting for the link to come back on its own. The
first version of `wifi-single-owner.sh` waited 20 s for that and then declared failure;
what actually worked was `nmcli connection up <ssid>` immediately after iwd left, which
re-associated in under a second.

---

## 3. Root cause B: two dhcp clients on one interface

Because the emergency profile had been restored *and* NetworkManager had been raised on
top of it, both managers configured `wlan0`:

```
$ ip -4 -o addr show dev wlan0
192.168.50.201/24          # NetworkManager's lease
192.168.50.200/24          # systemd-networkd's lease
$ ip route show default | wc -l
2
$ networkctl status wlan0
Network File: /etc/systemd/network/20-wlan.network
State: routable (configured)
```

This "works" — traffic leaves through whichever default route wins — and it is exactly
what makes the failure mode unpredictable. There must be **one** owner.

On this host the target owner is NetworkManager, because the wifi panel talks to
`Quickshell.Networking`, which is a NetworkManager client. With NM off the panel has no
model to read at all. So systemd-networkd keeps the ethernet/wwan profiles and loses the
one for the station-mode wlan link:

```bash
sudo mv /etc/systemd/network/20-wlan.network /var/tmp/      # move it, never delete
sudo systemctl restart systemd-networkd
networkctl status wlan0       # want: Network File: n/a / State: routable (unmanaged)
```

---

## 4. Root cause C: the boot ordering pulls iwd back in

`/etc/systemd/system/NetworkManager.service.d/10-after-iwd.conf` was created while
experimenting with NM's *iwd backend*:

```ini
[Unit]
After=iwd.service
Wants=iwd.service
```

Left behind, it re-introduces iwd at every boot. Measured after a reboot with the drop-in
still present: `iwd: active` while `systemctl is-enabled iwd` said `disabled` — the unit
was started by `NetworkManager.service`, and `systemctl show iwd -p WantedBy` reported
`WantedBy=NetworkManager.service`.

If the backend is `wpa_supplicant`, that drop-in is wrong twice over: iwd starts without
being enabled, and it competes with wpa_supplicant for the radio.

```bash
sudo rm -f /etc/systemd/system/NetworkManager.service.d/10-after-iwd.conf
sudo systemctl daemon-reload
systemctl show NetworkManager -p Wants -p After | tr ' ' '\n' | grep -c iwd   # want: 0
```

---

## 5. The secret: copy the PSK before switching backends

NetworkManager's profile had an **empty** passphrase (`psk length: 0`) although it was the
active connection — with NM on the iwd backend, iwd held the secret in
`/var/lib/iwd/<ssid>.psk` and NM's profile only referenced it.

Switch to `wpa_supplicant` with an empty profile and there is nothing to authenticate
with: the machine comes up associated-but-never-connected, or not at all.

The PSK lives in iwd's store, readable only by root:

```bash
sudo sed -n 's/^PreSharedKey=//p' /var/lib/iwd/LIB-2396867-5GHz.psk
```

and must be written into the NM profile before the backend changes:

```bash
sudo nmcli connection modify LIB-2396867-5GHz \
    wifi-sec.psk "$(sudo sed -n 's/^PreSharedKey=//p' /var/lib/iwd/LIB-2396867-5GHz.psk)"
```

A 64-character value is a raw PSK, not a passphrase; that is normal and must be stored
as-is. Verify without exposing it:

```bash
nmcli -f 802-11-wireless-security.psk connection show <ssid>   # want: <hidden>
nmcli --show-secrets -g 802-11-wireless-security.psk connection show <ssid> | wc -c
```

`nmcli -s -g ... | awk '{print length($0)}'` returned 0 once for a profile that did have a
secret. Prefer the `<hidden>` check.

---

## 6. The order that works

Do it in this order, verifying after each step. Downtime is unavoidable at step 4; being
stranded is not.

| # | Action | Verify |
|---|---|---|
| 1 | Copy the PSK from iwd's store into the NM profile (§5) | `psk: <hidden>` |
| 2 | Write `/etc/iwd/main.conf` with `[DriverQuirks] DefaultInterface=true` | file exists |
| 3 | `wifi.backend=wpa_supplicant` in `/etc/NetworkManager/conf.d/wifi-backend.conf`, start `wpa_supplicant`, restart NM | `nmcli device` shows `wlan0:connected` |
| 4 | Move `20-wlan.network` aside, restart networkd | `networkctl status wlan0` → `unmanaged`, and NM still `connected` |
| 5 | `systemctl disable --now iwd`, then **immediately** `nmcli connection up <ssid>` | `connected`, one address, one default route |
| 6 | Remove the `10-after-iwd.conf` drop-in | `systemctl show NetworkManager -p Wants` has no iwd |

Steps 2 and 6 are what survive a reboot; steps 3–5 are the transition.

---

## 7. The scripts (in `scripts/system/`)

| Script | Role | Refuses when |
|---|---|---|
| `wifi-rescue.sh` | **Panic button.** No arguments. Phase A: NM + wpa_supplicant (rebuilds the profile from iwd's PSK if the secret is missing). Phase B: delegates to the emergency script. Prints `✔ ONLINE` only when `nmcli` reports the device connected *and* the gateway answers. | not root |
| `wifi-emergency.sh` | Returns to the historical stack: iwd + systemd-networkd, NM and wpa_supplicant off. Rebuilds `20-wlan.network` from an embedded copy; verifies with `ip`/`iwctl` only, so it works with NM dead. | not root |
| `wifi-single-owner.sh` | Converges to NM as the only owner: moves networkd's wlan profile, keeps NM's connection, then retires iwd and re-activates the profile. | backend is not `wpa_supplicant`, NM not connected, or the quirk is missing |
| `wifi-boot-fix.sh` | Pre-reboot coherence check: removes the iwd drop-in and asserts eight facts about the boot path. | not root |
| `nm-wifi-backend.sh` | The original one-way switch to `wpa_supplicant` (copies the PSK, removes the drop-in, verifies, rolls back). | profile without a secret |
| `nm-iwd-switch.sh` | The historical switch to NM's **iwd** backend. Kept for reference; it writes the drop-in that `wifi-boot-fix.sh` removes. | — |

The panic button is the one to remember: `sudo ~/.dotfiles/scripts/system/wifi-rescue.sh`.
A copy of all of them plus the then-current state lives in `~/.local/share/wifi-backup/`.

---

## 8. Verification that actually proves it

```bash
nmcli -t -f DEVICE,STATE,CONNECTION device | grep wlan0   # connected:<ssid>
ip -4 -o addr show dev wlan0 | awk '{print $4}'           # exactly one address
ip route show default | wc -l                              # 1
networkctl status wlan0 | grep -E 'Network File|State'     # n/a + unmanaged
systemctl is-active iwd; systemctl is-enabled iwd          # inactive / disabled
grep -E '^wifi.backend=' /etc/NetworkManager/conf.d/wifi-backend.conf
systemctl show NetworkManager -p Wants -p After | tr ' ' '\n' | grep -c iwd   # 0
```

Do not accept a single `ping` as proof of ownership: while both managers held a lease,
`ping` succeeded and the state was still wrong.

---

## 9. Pitfalls, each one paid for

1. **Never call stopping iwd harmless.** It drops the association every time (§2.1). A
   command that "only stops a daemon" leaves the user offline.
2. **A safety net before the change, not after.** The panic button has to exist and be
   tested before touching the backend, because the failure mode removes the network you
   would use to read the docs.
3. **`iwctl` colours its output.** `iwctl known-networks list | awk '{print $1}'` returns
   an ANSI escape, not the SSID, and the station state comes back padded with spaces. Strip
   first: `sed 's/\x1b\[[0-9;]*m//g'`, then trim trailing spaces. Without this the recovery
   path cannot name the network it is supposed to join.
4. **`nmcli -s -g` can report an empty secret that exists.** Use the `<hidden>` form.
5. **An interrupted switch leaves the worst state.** Ctrl-C during verification leaves the
   backend on one supplicant and the profile on the other; always finish the verification
   or run the recovery on purpose.
6. **Verification windows must match reality.** A 90 s window once declared failure on a
   switch that completed at 118 s, and the automatic rollback then mixed two
   configurations. Prefer "verify, then retry the activation" over "wait longer".
7. **`Wants=` beats `is-enabled`.** A disabled unit can still run because another unit
   pulls it. Check `systemctl show <unit> -p WantedBy` when a disabled service is active.
8. **Don't `kill` a persistent surface** to reload it: use
   `systemd-run --user --collect --unit=<name>`; a TERM takes the session with it.

---

## 10. The wifi panel's side of the same story

The panel (`config/quickshell/wifi/`) reads through `Quickshell.Networking`, which is a
NetworkManager client. Three behaviours there are documented by Quickshell and easy to
misread:

* `WifiNetwork.connectWithPsk(psk)` — *"If the PSK is wrong, `connectionFailed()` will be
  emitted with `NoSecrets`."* So `NoSecrets` **with a passphrase in hand means the
  passphrase is wrong**; only `NoSecrets` with no passphrase means one is required. The
  panel used to answer `NoSecrets` by retrying the same rejected secret, which held it in
  `connecting` for the full 12 s timeout and then blamed the backend.
* A wrong attempt leaves a profile NM wrote, and `network.known` can be stale on a
  recreated access-point object, so a second click skipped the prompt and activated a
  profile with no secret. `NetworkState` now remembers the last failed SSID and asks again.
* `Networking.devices` / `.networks` are asynchronous and NM recreates access-point objects
  while scanning: never act on a network object held from a previous tick, and resolve the
  device again on every tick.

Verified end to end with a deliberately wrong passphrase against a real AP: status goes
`connecting…` → `wrong passphrase · back on <previous>`, `attempting` returns to false, the
previous network is restored within a second, and no profile is left behind.

---

## 11. Fresh machine checklist

1. `pacman -S networkmanager wpa_supplicant` (do **not** install iwd if NM will own the
   radio).
2. `systemctl enable --now NetworkManager`.
3. Make sure systemd-networkd has **no** `.network` file matching a station-mode wlan link.
4. If migrating from a machine that used iwd: copy the PSK out of `/var/lib/iwd/*.psk`
   before touching anything (§5).
5. `wifi.backend=wpa_supplicant` (the default) and no `10-after-iwd.conf` drop-in.
6. Run `sudo ~/.dotfiles/scripts/system/wifi-boot-fix.sh` and require
   `✔ arranque coherente` before believing any of the above.

---

## 12. Sources

* `iwd.config(5)` — https://man.archlinux.org/man/iwd.config.5 (option semantics,
  `[DriverQuirks] DefaultInterface`).
* Gentoo wiki, iwd — the "destroys the interface it created" sentence.
* Arch BBS #260888 — https://bbs.archlinux.org/viewtopic.php?id=260888 (same symptom).
* Quickshell docs v0.3.0, `Quickshell.Networking.WifiNetwork` — `connectWithPsk` and
  `NoSecrets`.
* NetworkManager: `wifi.backend` in `NetworkManager.conf(5)`; `libnm-device-plugin-wifi.so`
  on this host contains the `net.connman.iwd` references, i.e. the iwd backend is compiled
  in.
