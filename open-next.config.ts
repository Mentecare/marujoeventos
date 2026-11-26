import { defineCloudflareConfig } from '@opennextjs/cloudflare';

// No external cache bucket is needed: authenticated pages and APIs are dynamic.
export default defineCloudflareConfig();
