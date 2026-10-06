import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  reactStrictMode: true,
  async headers(){return [{source:"/o/:id",headers:[{key:"Cache-Control",value:"private, no-store, max-age=0"}]}]},
};

export default nextConfig;
