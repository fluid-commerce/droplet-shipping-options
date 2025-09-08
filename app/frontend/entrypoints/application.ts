import "../fontawesome"  // Import FontAwesome here instead of CSS
import "@hotwired/turbo-rails"
import "./modals"

interface AppConfig {
  environment: string;
  debug: boolean;
}

const environment = process.env.NODE_ENV || 'development';
const debug = (environment === 'development');

const config: AppConfig = { environment, debug };

if (config.debug) {
  console.log('Vite ⚡️ Rails with TypeScript', config);
}
