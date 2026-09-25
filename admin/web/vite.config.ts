/// <reference types="vitest/config" />
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// The admin app builds into the service's static files; in development Vite proxies
// the service's routes so the passkey origin (http://localhost:5173) is the page's own.
export default defineConfig({
  plugins: [react()],
  build: {
    outDir: '../api/src/Tankbook.Admin/wwwroot',
    emptyOutDir: true,
  },
  server: {
    proxy: {
      '/api': 'http://localhost:5047',
      '/auth': 'http://localhost:5047',
      '/health': 'http://localhost:5047',
    },
  },
  test: {
    environment: 'jsdom',
    setupFiles: ['./src/test-setup.ts'],
  },
})
