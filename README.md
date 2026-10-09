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

## Sizing and testing a 2.5 Gbit/s link

**What we measured.** Two 2 vCPU, 4 GB droplets in different US regions, 8 parallel
streams for 20 seconds, from a firewall in front of a 1 Gbit/s down, 500 Mbit/s up
cable line with inline IPS:

- Download to one droplet landed anywhere from 790 to 940 Mbit/s depending on the
  droplet and path, with the same client and settings. Two droplets at the same time
  reached about 910 to 920 Mbit/s combined.
- Upload reached about 460 Mbit/s to one droplet and about 510 Mbit/s combined across
  two.
- One droplet on its own was off by roughly 15 percent from path and host variance
  alone. When you compare a shaping or firewall change, use two servers and repeat
  the run before believing a difference smaller than that.

**Picking a size.**

- A 2 vCPU droplet did not look like the limit at about 1 Gbit/s: the slower of the
  two droplets was not at a hard ceiling, because the other, identical one reached
  a higher number on the same line. That is an observation on this line, not a
  guarantee for yours.
- Check the plan's published network rate before you rely on it. Shared-CPU plans can
  be throttled below the NIC speed.
- Check `iperf3 --version` on the droplet. Release 3.16 made parallel streams
  multi-threaded; older versions run every stream on one core, which caps a single
  server well below 2.5 Gbit/s.

**Going to 2.5 Gbit/s.**

- Plan on two or more droplets in different regions and run them at the same time.
  `cloud-init.sh` already starts servers on ports 5201 and 5202, so two clients, or
  one client with two tests, can use one droplet.
- Choose a CPU-optimised or dedicated-CPU plan with at least 4 vCPU, and confirm its
  network rate is above what you want to measure.
- The client matters as much as the server at this speed: use a host with a 2.5 Gbit/s
  NIC, or test from the firewall's own WAN side.
- Inline IDS/IPS and shaping use CPU. On the 8-thread Xeon D we tested, the busiest
  inline Suricata worker thread reached 86 percent of a core at about 1 Gbit/s, so
  expect the IPS to be the first limit above that.
- Run the same test shaped and unshaped. The difference tells you what the shaper
  costs; the unshaped number is the ceiling of the line plus the firewall.

**Reading the results.**

- Test from a wired client on the LAN, through the firewall, not only from the
  firewall. With shaping on, tests that start on the firewall itself understated
  upload by about half in our case, because locally terminated traffic interacts
  differently with dummynet. A forwarded client reached the configured cap.
- Wait a few seconds between runs. The server resets after each test and rejects an
  immediate reconnect with "Connection reset by peer".
- Watch latency during the test, not only throughput. Run `ping` to a nearby host
  while iperf3 is running and compare it with the idle value: a shaper that is
  working keeps the loaded latency close to idle and cuts the worst-case spikes.

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
