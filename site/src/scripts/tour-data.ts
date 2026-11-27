// Made-up but realistic state of the server the tour shows.
export interface Ctr {
  name: string;
  project: string;
  image: string;
  status: string;
  mem: number;
  cpu: number;
  health: 'healthy' | 'running' | 'starting' | 'failing';
}

export const host = {
  name: 'macmini-server',
  os: 'Ubuntu 24.04',
  cpu: 'i7-3615QM',
  ram: '16 GB',
  uptime: 'up 6d 10h',
  kernel: '6.8.0-151-generic',
};

export const containers: Ctr[] = [
  { name: 'agent', project: 'pulse', image: 'pulse-agent:0.1.0', status: 'Up 3 hours (healthy)', mem: 9, cpu: 0.3, health: 'healthy' },
  { name: 'cloudflared', project: 'perde-site', image: 'cloudflare/cloudflared:2026.11.2', status: 'Up 34 hours', mem: 19, cpu: 0.1, health: 'running' },
  { name: 'cloudflared', project: 'key-proxy', image: 'cloudflare/cloudflared:2026.11.2', status: 'Up 35 hours', mem: 19, cpu: 0.1, health: 'running' },
  { name: 'docker-proxy', project: 'pulse', image: 'tecnativa/docker-socket-proxy:3.4', status: 'Up 3 hours', mem: 28, cpu: 0.0, health: 'running' },
  { name: 'jellyfin', project: 'perde-test', image: 'jellyfin/jellyfin:10.11.11', status: 'Up 26 hours (healthy)', mem: 168, cpu: 0.4, health: 'healthy' },
  { name: 'samba', project: 'perde-test', image: 'dockurr/samba:4.23.10', status: 'Up 25 hours (healthy)', mem: 24, cpu: 0.0, health: 'healthy' },
  { name: 'site', project: 'perde-site', image: 'perde-site:latest', status: 'Up 22 minutes (healthy)', mem: 8, cpu: 0.0, health: 'healthy' },
  { name: 'perde-key-proxy', project: 'key-proxy', image: 'perde-key-proxy', status: 'Up 28 hours (healthy)', mem: 38, cpu: 0.0, health: 'healthy' },
  { name: 'portainer', project: '', image: 'portainer/portainer-ce:lts', status: 'Up 6 days', mem: 95, cpu: 0.0, health: 'running' },
];

export const sites = [
  { name: 'perde', url: 'https://perde.kutluhangil.dev', ms: 136 },
  { name: 'perde-keys', url: 'https://perde-keys.kutluhangil.dev', ms: 183 },
  { name: 'pulse', url: 'https://pulse.kutluhangil.dev', ms: 121 },
];

const LINES: Record<string, string[]> = {
  jellyfin: [
    '[INF] Main: Jellyfin version: 10.11.11',
    '[INF] Startup complete 0:00:04.81',
    '[INF] Scheduled task "Scan Media Library" completed after 0 minute(s) and 6 seconds',
    '[INF] HTTP GET /System/Ping 200 1ms',
    '[INF] Playback stopped reported by app "Perde" playing "Sintel". Stopped at 552113 ms',
  ],
  agent: ['pulse-agent dev listening on 127.0.0.1:9123', 'docker: connected to 28.5.2', 'probe perde ok 136 ms', 'probe perde-keys ok 183 ms', 'GET /v1/stream 200 client=100.88.12.4'],
  samba: ['smbd version 4.23.10 started.', 'Copyright Andrew Tridgell and the Samba Team 1992-2026', 'daemon_ready: daemon \'smbd\' finished starting up and ready to serve connections'],
};

export function logsFor(name: string): string {
  const base = LINES[name] ?? [`${name}: started`, 'listening', 'GET /health 200', 'GET /health 200', 'heartbeat ok'];
  const now = Date.now();
  return Array.from({ length: 18 }, (_, i) => {
    const ts = new Date(now - (18 - i) * 47_000).toISOString().replace('T', ' ').slice(0, 19);
    return `${ts}  ${base[i % base.length]}`;
  }).join('\n');
}

export const summary = (cpu: number, temp: number, mem: number) =>
  `${host.name} · health 98 (Excellent)\nCPU ${Math.round(cpu)}% · ${Math.round(temp)}°C · MEM ${Math.round(mem)}%\nDisk 54% · 46 GB free\nContainers: 9/9`;
