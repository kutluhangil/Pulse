// The release the download buttons point at. Bump with each GitHub release.
export const version = '0.1.0';
const base = 'https://github.com/kutluhangil/Pulse/releases';
export const repo = 'https://github.com/kutluhangil/Pulse';
export const links = {
  dmg: `${base}/download/v${version}/Pulse-${version}.dmg`,
  deb: `${base}/download/v${version}/pulse-monitor_${version}_all.deb`,
  releases: base,
  agent: `${repo}/tree/main/deploy`,
};
export const debFile = `pulse-monitor_${version}_all.deb`;
