import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { resolve } from 'path'
import { TanStackRouterVite } from '@tanstack/router-vite-plugin'

export default defineConfig({
  plugins: [
    react(),
    TanStackRouterVite(),
  ],
  root: './',
  base: '/',
  build: {
    outDir: '../priv/static',
    emptyOutDir: false,
    manifest: true,
    rollupOptions: {
      input: {
        main: resolve(__dirname, 'src/main.tsx'),
      },
      output: {
        manualChunks: {
          'syntax-highlighter': ['react-syntax-highlighter', 'prismjs', 'highlight.js'],
          'vendor': ['react', 'react-dom', 'react-markdown', '@tanstack/react-router', '@tanstack/react-query', 'lucide-react'],
        },
        entryFileNames: `assets/[name].js`,
        chunkFileNames: `assets/[name].js`,
        assetFileNames: `assets/[name].[ext]`
      }
    },
  },
  server: {
    port: 5173,
    host: '0.0.0.0',
    origin: 'http://localhost:5173',
    cors: true,
    allowedHosts: true,
    proxy: {
      '/api': {
        target: 'http://localhost:4000',
        changeOrigin: true,
        secure: false,
      }
    }
  },
})
