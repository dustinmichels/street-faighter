---
layout: home
title: Street fAIghter
titleTemplate: Bring your own AI. Build your own fighter.

hero:
  name: STREET F<span class="ai">AI</span>GHTER
  text: Bring your own AI. Build your own fighter.
  tagline: A pixel-art street fighter driven by real 3D models. Describe a fighter in a few words, let your AI coding agent build it in Blender, then take it online against a friend.
  actions:
    - theme: brand
      text: DOWNLOAD
      link: /guide/download
    - theme: alt
      text: How to play
      link: /guide/playing
    - theme: alt
      text: Make a fighter
      link: /guide/custom-characters

features:
  - icon:
      src: /icons/robot.svg
      width: 40
      height: 40
    title: Bring your own agent
    details: Answer a short questionnaire and the game writes a prompt kit. Claude Code, Codex, Gemini CLI, or any agent that runs shell commands builds the fighter in Blender.
    link: /guide/custom-characters
    linkText: Make a fighter
  - icon:
      src: /icons/net.svg
      width: 40
      height: 40
    title: Online, peer to peer
    details: One player hosts, the other joins by IP. Deterministic rollback netcode keeps both machines frame-identical, and your custom fighter is sent to your opponent automatically.
    link: /guide/online
    linkText: Play online
  - icon:
      src: /icons/stick.svg
      width: 40
      height: 40
    title: Fight the CPU
    details: Punch, block, duck, sweep, and land three clean hits to charge a special throw. The computer walks in, jabs, jumps in with air kicks, and ducks your punches to answer with a sweep.
    link: /guide/playing
    linkText: Learn the moves
  - icon:
      src: /icons/cube.svg
      width: 40
      height: 40
    title: Pixel art from real 3D
    details: Every frame is a 3D scene rendered at 480×270 with toon shading, outlines, and color quantization, so any Blender model looks like it belongs in an arcade cabinet.
  - icon:
      src: /icons/share.svg
      width: 40
      height: 40
    title: Fair by design
    details: Custom characters are cosmetic. Hitboxes and damage are the same for everyone, and every model is checked by the game's validator before it is shown.
    link: /dev/custom-characters
    linkText: How it works
  - icon:
      src: /icons/heart.svg
      width: 40
      height: 40
    title: Free, with source on GitHub
    details: Made with Godot 4.7 and Blender. Read the code, run it from source, and build your own release.
    link: /dev/
    linkText: Run from source
---

<script setup>
import { withBase } from 'vitepress'
</script>

<div class="sf-home">

<div class="sf-section">
  <p class="sf-kicker">Round 1</p>
  <h2>See it in action</h2>
  <p class="sf-lead">Two computer players on the street stage. The green fighter is Monsieur Lézard, a custom character an AI agent built from the brief below.</p>
  <div class="sf-wide sf-cabinet">
    <div class="sf-marquee"><span class="sf-blink">LIVE</span><span>CPU VS CPU</span></div>
    <div class="sf-crt">
      <video :src="withBase('/media/fight.mp4')" :poster="withBase('/media/sweep.png')" autoplay muted loop playsinline aria-label="Gameplay footage: two fighters trading blows on the street stage"></video>
    </div>
  </div>
</div>

<div class="sf-section">
  <p class="sf-kicker">Round 2</p>
  <h2>One idea in. One fighter out.</h2>
  <p class="sf-lead">You describe the fighter. Your agent writes a Blender script on the game's skeleton, renders previews to check its work, exports a <code>.glb</code>, and runs the game's validator until it passes. You press <strong>IMPORT</strong>.</p>
  <div class="sf-pipeline">
    <div class="sf-card">
      <div class="sf-card-label">1. YOUR BRIEF</div>
      <div class="sf-card-body">
        <ul class="sf-brief">
          <li><b>name</b> Monsieur Lézard</li>
          <li><b>concept</b> A french lizard man</li>
          <li><b>archetype</b> brawler</li>
          <li><b>build</b> athletic</li>
          <li><b>extras</b> french beret, tank top, shorts, tail</li>
        </ul>
      </div>
      <div class="sf-card-foot">Three short pages in the game: who it is, how it looks, and anything else.</div>
    </div>
    <div class="sf-arrow" aria-hidden="true">▶</div>
    <div class="sf-card">
      <div class="sf-card-label">2. YOUR AGENT BUILDS IT</div>
      <div class="sf-card-body sf-render">
        <img :src="withBase('/media/monsieur-lezard-render.png')" alt="Blender preview render of Monsieur Lézard in the test pose" />
      </div>
      <div class="sf-card-foot">One of the preview renders the agent makes to check its work.</div>
    </div>
    <div class="sf-arrow" aria-hidden="true">▶</div>
    <div class="sf-card">
      <div class="sf-card-label">3. YOU FIGHT WITH IT</div>
      <div class="sf-card-body sf-ingame">
        <img :src="withBase('/media/stage.png')" alt="Monsieur Lézard in a match on the street stage" />
      </div>
      <div class="sf-card-foot">Same model, in game, with the toon shader and outlines.</div>
    </div>
  </div>
</div>

<div class="sf-section">
  <p class="sf-kicker">Round 3</p>
  <h2>Get in the game</h2>
  <div class="sf-steps">
    <div class="sf-step">
      <span class="sf-step-num">01</span>
      <h3>Download</h3>
      <p>Install it in one click with the itch app, or grab the macOS, Windows, or Linux build from GitHub Releases.</p>
    </div>
    <div class="sf-step">
      <span class="sf-step-num">02</span>
      <h3>Press start</h3>
      <p>Enter your name, pick <strong>1 PLAYER VS CPU</strong>, and choose your fighter. Keyboard or gamepad.</p>
    </div>
    <div class="sf-step">
      <span class="sf-step-num">03</span>
      <h3>Make it yours</h3>
      <p>Open <strong>CHARACTERS → CREATE NEW</strong>, hand the kit to your AI agent, and import the result. Then host a match and show it off.</p>
    </div>
  </div>
  <div class="sf-shots">
    <div class="sf-crt"><img :src="withBase('/media/title.png')" alt="Title screen" /></div>
    <div class="sf-crt"><img :src="withBase('/media/sweep.png')" alt="A sweep knocks the opponent down" /></div>
  </div>
</div>

<div class="sf-cta">
  <h2>HERE COMES A NEW CHALLENGER</h2>
  <p>Free to play. Download it, press start, and bring a friend.</p>
  <div class="sf-cta-actions">
    <a class="sf-btn brand" :href="withBase('/guide/download')">Download & install</a>
    <a class="sf-btn alt" href="https://github.com/dustinmichels/street-faighter">View on GitHub</a>
  </div>
</div>

</div>
