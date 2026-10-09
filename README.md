# speedtest-droplet

A throwaway Ubuntu 24.04 DigitalOcean droplet that runs iperf3 servers. Use it to
measure a home internet link and the firewall in front of it (1 to 2.5 Gbit/s)
against one stable server of your own, instead of busy public iperf3 servers
whose results swing by 20 percent between runs.

## What the script does

`cloud-init.sh` is the droplet's user data. On first boot it:

- installs `iperf3` and `ufw`;
- raises the TCP socket buffer limits so a single flow can fill a fast path;
- runs two iperf3 servers as hardened systemd units, on ports 5201 and 5202, so
  two tests can run at once (each instance serves one test at a time);
- turns on the host firewall, allowing **one CIDR** to reach ports 22, 5201 and 5202;
- sets key-only SSH.

The allowed CIDR is not stored in this repository. `scripts/render-userdata.sh`
fills it in when you need it. An unrendered `cloud-init.sh` refuses to run, so a
droplet cannot come up open to the internet.

## Use

1. Render the script. With no argument it detects the public IPv4 of the network
   you run it from (via `api.ipify.org`) and allows that address as a /32.

   ```sh
   scripts/render-userdata.sh | xclip -selection clipboard   # or copy from the terminal
   scripts/render-userdata.sh -o ~/userdata.txt              # or write a file (mode 600)
   scripts/render-userdata.sh 203.0.113.7/32                 # or give the CIDR yourself
   ```

   It rejects `0.0.0.0/0`, malformed addresses and anything wider than /24 unless
   you pass `--allow-wide`. With `-o`, a path inside this repository must be
   git-ignored (`rendered/` and `*.userdata` are), so the address cannot be
   committed. Delete the file once the droplet exists.

2. Create a droplet: Ubuntu 24.04, your SSH key, a region near you (Memphis is
   `mem1`), and a size whose network rate clearly exceeds the speed you want to
   test. Paste the rendered script into **Advanced options, User data**.

3. Attach a DigitalOcean cloud firewall that allows only the same address on TCP
   22 and 5201 to 5202.

4. Wait for setup to finish. The file `/var/lib/speedtest-droplet/ready` appears
   when it is done; the log is `/var/log/speedtest-droplet-init.log`.

## Test

From the client, replacing `DROPLET_IP`:

```sh
iperf3 -c DROPLET_IP -p 5201 -R -P 4 -t 20 -O 3   # download (the server sends)
iperf3 -c DROPLET_IP -p 5201 -P 4 -t 20 -O 3      # upload (the client sends)
```

`-O 3` leaves out the first three seconds, so TCP ramp-up does not drag the
average down. Use port 5202 from a second host to load both servers at once.

## Cost and teardown

A droplet bills until it is destroyed; powering it off does not stop the charge.
Destroy it when the testing is done.

## Tests

```sh
bash tests/test-render.sh
```

The checks are offline: they exercise the renderer and the template, and need no
network or root. CI runs them through the reusable workflows in
[git-your-ship-together](https://github.com/ChiefGyk3D/git-your-ship-together).

## Licence

MPL-2.0.
