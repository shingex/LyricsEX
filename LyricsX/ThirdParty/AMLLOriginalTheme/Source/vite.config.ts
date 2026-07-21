import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

const localPackage = (name: string) => new URL(`./node_modules/${name}`, import.meta.url).pathname;

export default defineConfig({
  plugins: [react()],
  base: "./",
  resolve: {
    dedupe: ["react", "react-dom"],
    alias: {
      "@applemusic-like-lyrics/core/style.css": "/tmp/applemusic-like-lyrics/packages/core/src/styles/index.css",
      "@applemusic-like-lyrics/core": "/tmp/applemusic-like-lyrics/packages/core/src/index.ts",
      "@applemusic-like-lyrics/react": "/tmp/applemusic-like-lyrics/packages/react/src/index.ts",
      "@pixi/app": localPackage("@pixi/app"),
      "@pixi/core": localPackage("@pixi/core"),
      "@pixi/display": localPackage("@pixi/display"),
      "@pixi/filter-blur": localPackage("@pixi/filter-blur"),
      "@pixi/filter-bulge-pinch": localPackage("@pixi/filter-bulge-pinch"),
      "@pixi/filter-color-matrix": localPackage("@pixi/filter-color-matrix"),
      "@pixi/sprite": localPackage("@pixi/sprite"),
      "@ungap/structured-clone": localPackage("@ungap/structured-clone"),
      "bezier-easing": localPackage("bezier-easing"),
      "deep-freeze": localPackage("deep-freeze"),
      "gl-matrix": localPackage("gl-matrix"),
      react: localPackage("react"),
      "react-dom": localPackage("react-dom")
    }
  },
  build: {
    outDir: "../AMLLOriginalThemeWeb",
    emptyOutDir: true,
    sourcemap: false,
    assetsDir: "assets"
  }
});
