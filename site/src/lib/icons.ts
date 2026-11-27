// Brand marks from Simple Icons (CC0), used only to name the tools Pulse works with.
import { siApple, siDocker, siGithub, siGo, siLinux, siTailscale, siUbuntu, siPortainer, siCockpit } from 'simple-icons';

export const brands = {
  apple: siApple, docker: siDocker, github: siGithub, go: siGo, linux: siLinux,
  tailscale: siTailscale, ubuntu: siUbuntu, portainer: siPortainer, cockpit: siCockpit,
} as const;
export type Brand = keyof typeof brands;
export const brandPath = (b: Brand) => brands[b].path;
