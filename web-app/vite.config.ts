import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    strictPort: false, // Use next available port if 5173 is busy
    open: true, // Auto-open browser on startup
  },
  build: {
    sourcemap: true, // Enable source maps for debugging
  },
})
