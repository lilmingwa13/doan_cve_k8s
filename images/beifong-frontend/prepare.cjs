const fs = require('node:fs');

// Adapt only the copied frontend source in the image build. The upstream
// checkout and the FastAPI routes used for the CVE experiment stay unchanged.
const apiPath = '/web/src/services/api.js';
const apiSource = fs.readFileSync(apiPath, 'utf8');
const originalApiBase = "const API_BASE_URL = 'http://localhost:7000';";
if (!apiSource.includes(originalApiBase)) {
  throw new Error('Expected upstream API base URL was not found');
}
fs.writeFileSync(
  apiPath,
  apiSource.replace(originalApiBase, 'const API_BASE_URL = window.location.origin;'),
);

const htmlPath = '/web/public/index.html';
const htmlSource = fs.readFileSync(htmlPath, 'utf8');
const tailwindCdn = '<script src="https://cdn.jsdelivr.net/npm/@tailwindcss/browser@4"></script>';
if (!htmlSource.includes(tailwindCdn)) {
  throw new Error('Expected Tailwind browser CDN tag was not found');
}
fs.writeFileSync(
  htmlPath,
  htmlSource.replace(
    tailwindCdn,
    '<link rel="stylesheet" href="%PUBLIC_URL%/static/lab-tailwind.css" />',
  ),
);
