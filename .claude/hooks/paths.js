// The hooks get Windows paths (C:\...) from the tools and Git Bash paths (/c/...) from the shell.
function normalize(p) {
  p = p.replace(/\\/g, '/');
  const drive = p.match(/^\/([a-zA-Z])\//);
  if (drive) p = `${drive[1]}:/${p.slice(3)}`;
  return p.replace(/\/+$/, '').toLowerCase();
}

// The file's path inside the project, lower case with forward slashes; null when it's outside.
function projectRelative(file) {
  const root = normalize(process.env.CLAUDE_PROJECT_DIR || process.cwd());
  const f = normalize(file);
  return f.startsWith(`${root}/`) ? f.slice(root.length + 1) : null;
}

module.exports = { projectRelative };
