import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

export default defineConfig({
  plugins: [vue()],
  server: {
    port: 5173,
    proxy: {
      '/events': 'http://localhost:4001',
      '/health': 'http://localhost:4001',
      '/stream': {
        target: 'ws://localhost:4001',
        ws: true,
      },
    },
  },
})
