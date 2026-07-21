const fs = require("fs");
const path = require("path");

const indexPath = path.resolve(__dirname, "../../AMLLOriginalThemeWeb/index.html");
let html = fs.readFileSync(indexPath, "utf8");

html = html
  .replace(/<script type="module" crossorigin src="([^"]+)"><\/script>/, '<script defer src="$1"></script>')
  .replace(/\s+crossorigin/g, "");

fs.writeFileSync(indexPath, html);
