import { defineConfig } from 'vite';

export default defineConfig({
  build: {
    rollupOptions: {
      input: {
        main: 'index.html',
        capture: 'capture.html',
      },
    },
    outDir: 'dist',
  },
});
