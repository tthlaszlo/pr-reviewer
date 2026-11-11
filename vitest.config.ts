import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  test: {
    include: ['tests/unit/**/*.test.{ts,tsx}'],
    environment: 'jsdom',
    setupFiles: ['tests/setup.ts'],
    coverage: {
      provider: 'v8',
      include: ['server/**/*.ts', 'src/**/*.tsx'],
      exclude: ['server/index.ts', 'src/main.tsx'],
      reporter: ['text', 'lcov'],
      thresholds: { statements: 90, branches: 80, functions: 90, lines: 90 },
    },
  },
});
