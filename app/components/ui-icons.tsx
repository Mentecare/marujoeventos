import type { ReactNode, SVGProps } from "react";
import type { AppTab } from "@/lib/capabilities";

export type IconName = AppTab | "refresh" | "logout" | "location" | "arrow" | "check";
const paths: Record<IconName, ReactNode> = {
  home: <><rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/></>,
  dashboard: <><path d="M4 4v16h16"/><path d="M8 15v-4m5 4V7m5 8v-6"/></>,
  clients: <><rect x="3" y="7" width="18" height="14" rx="3"/><path d="M8 7V5a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2M3 12h18m-11 0v3h4v-3"/></>,
  team: <><path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2m20 0v-2a4 4 0 0 0-3-3.87"/><circle cx="9" cy="7" r="4"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/></>,
  events: <><rect x="3" y="5" width="18" height="16" rx="3"/><path d="M16 3v4M8 3v4M3 11h18m-13 5h3"/></>,
  schedule: <><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></>,
  finance: <><rect x="3" y="5" width="18" height="15" rx="3"/><path d="M3 9h18m-4 5h2"/><path d="M6 5V3h12"/></>,
  reputation: <path d="m12 3 2.8 5.7 6.2.9-4.5 4.4 1.1 6.2-5.6-3-5.6 3 1.1-6.2L3 9.6l6.2-.9L12 3Z"/>,
  profile: <><circle cx="12" cy="8" r="4"/><path d="M4 21v-2a8 8 0 0 1 16 0v2"/></>,
  refresh: <><path d="M20 7v5h-5M4 17v-5h5"/><path d="M6.1 6.1A8 8 0 0 1 19.6 10M4.4 14A8 8 0 0 0 17.9 17.9"/></>,
  logout: <><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4m7 14 5-5-5-5m5 5H9"/></>,
  location: <><path d="M20 10c0 6-8 11-8 11S4 16 4 10a8 8 0 1 1 16 0Z"/><circle cx="12" cy="10" r="2.5"/></>,
  arrow: <><path d="M5 12h14m-6-6 6 6-6 6"/></>,
  check: <path d="m5 12 4 4L19 6"/>,
};

export function AppIcon({name, className = "", ...props}: SVGProps<SVGSVGElement> & {name: IconName}) {
  return <svg className={`uiIcon ${className}`} width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.65" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" focusable="false" {...props}>{paths[name]}</svg>;
}
