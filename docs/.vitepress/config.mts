import { defineConfig } from "vitepress";

const repo = "https://github.com/dustinmichels/street-faighter";
// Site root: GitHub Pages project site at dustinmichels.github.io/street-faighter/.
const base = "/street-faighter/";

export default defineConfig({
  title: "Street fAIghter",
  description:
    "A pixel-art fighting game driven by real 3D models. Bring your own AI coding agent to build a custom fighter, then take it online.",
  lang: "en-US",
  base,
  cleanUrls: true,
  appearance: "force-dark",
  head: [
    ["link", { rel: "icon", type: "image/svg+xml", href: `${base}logo.svg` }],
    ["meta", { name: "theme-color", content: "#0b0618" }],
    ["meta", { property: "og:type", content: "website" }],
    ["meta", { property: "og:title", content: "Street fAIghter" }],
  ],
  themeConfig: {
    logo: "/logo.svg",
    siteTitle: "Street fAIghter",
    nav: [
      { text: "Play", link: "/guide/download", activeMatch: "^/guide/" },
      { text: "Develop", link: "/dev/", activeMatch: "^/dev/" },
      { text: "Download", link: `${repo}/releases/latest` },
    ],
    sidebar: {
      "/guide/": [
        {
          text: "Play",
          items: [
            { text: "Download & install", link: "/guide/download" },
            { text: "How to play", link: "/guide/playing" },
            { text: "Online multiplayer", link: "/guide/online" },
            { text: "Make your own fighter", link: "/guide/custom-characters" },
            { text: "Troubleshooting", link: "/guide/troubleshooting" },
          ],
        },
        { text: "Develop", items: [{ text: "Run from source", link: "/dev/" }] },
      ],
      "/dev/": [
        {
          text: "Develop",
          items: [
            { text: "Run from source", link: "/dev/" },
            { text: "Tests", link: "/dev/testing" },
          ],
        },
        {
          text: "Design",
          items: [
            { text: "Netcode", link: "/dev/netcode" },
            { text: "Custom character pipeline", link: "/dev/custom-characters" },
            { text: "Skeleton", link: "/dev/skeleton" },
            { text: "Research: prompt-driven animation", link: "/dev/prompt-animation" },
          ],
        },
        { text: "Play", items: [{ text: "Player guide", link: "/guide/download" }] },
      ],
    },
    socialLinks: [{ icon: "github", link: repo }],
    search: { provider: "local" },
    editLink: {
      pattern: `${repo}/edit/main/docs/:path`,
      text: "Edit this page on GitHub",
    },
    outline: [2, 3],
    footer: {
      message: "Made with Godot, Blender, and whichever AI agent you bring.",
      copyright: "Street fAIghter",
    },
  },
});
