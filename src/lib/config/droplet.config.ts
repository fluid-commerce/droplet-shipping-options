/**
 * Droplet Configuration
 *
 * Per-company webhooks registered when a company installs this droplet. These
 * are separate from the droplet-level `droplet.installed` /
 * `droplet.uninstalled` webhooks, which are created once by the admin
 * dashboard's "Create Droplet" action — see src/lib/use-cases/droplet.ts.
 *
 * Callbacks live in the `callbacks` table, not here. See ./schema.ts.
 */

import type { DropletConfig } from "./schema";

export const dropletConfig: DropletConfig = {
  webhooks: [
    {
      enabled: false,
      resource: "order",
      event: "created",
      description: "Notified when a new order is created",
    },
    {
      enabled: false,
      resource: "cart",
      event: "updated",
      description: "Notified when a cart is updated",
    },
  ],
};
