import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  reactStrictMode: true,
  // PDFKit resolves built-in fonts relative to its own package. Keep that
  // boundary external and include the data in the deployed route trace.
  serverExternalPackages: ['pdfkit'],
  outputFileTracingIncludes: {
    '/api/quotes/*/pdf': [
      './lib/fonts/*.ttf',
      './lib/fonts/LICENSE-DejaVu.txt',
      './node_modules/pdfkit/js/standard-fonts/**/*',
      './node_modules/pdfkit/js/data/Helvetica*.afm',
    ],
  },
  async headers(){return [{source:"/o/:id",headers:[{key:"Cache-Control",value:"private, no-store, max-age=0"}]}]},
};

export default nextConfig;
