// `node --test scripts/__tests__/` hands this directory to the test runner as
// a single module, so this entry point loads every test file next to it.
const { readdirSync } = require('node:fs');
const { join } = require('node:path');
const { pathToFileURL } = require('node:url');

const testFiles = readdirSync(__dirname)
  .filter((name) => name.endsWith('.test.mjs'))
  .sort();

for (const file of testFiles) {
  import(pathToFileURL(join(__dirname, file)).href).catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
}
