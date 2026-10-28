import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

// Check if TSX or a TypeScript ESM loader is currently active
const isTsxActive = Boolean(
  process.env.__TSX_ACTIVE === '1' ||
  (process.execArgv && process.execArgv.some(arg => arg.includes('tsx')))
);

if (!isTsxActive) {
  // Re-spawn Node with tsx loader so TypeScript files and extensionless imports resolve seamlessly
  const currentFilePath = fileURLToPath(import.meta.url);
  const child = spawn(
    process.execPath,
    ['--import', 'tsx', currentFilePath, ...process.argv.slice(2)],
    {
      stdio: 'inherit',
      env: {
        ...process.env,
        __TSX_ACTIVE: '1',
      },
    }
  );

  child.on('exit', (code, signal) => {
    if (signal) {
      process.kill(process.pid, signal);
    } else {
      process.exit(code ?? 0);
    }
  });

  process.on('SIGINT', () => child.kill('SIGINT'));
  process.on('SIGTERM', () => child.kill('SIGTERM'));
} else {
  // TSX loader is active; import and execute the primary server core
  await import('./serverCore.ts');
}
